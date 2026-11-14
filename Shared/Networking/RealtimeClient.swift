//
//  RealtimeClient.swift
//  MVK++ (shared by the Phone and Watch targets)
//

import Combine
import Foundation

/// One server push. The payload stays as raw bytes so each screen decodes it
/// into its own `Decodable` type, exactly like a REST response.
struct RealtimeMessage {
    let type: String
    let topic: String?
    let data: Data

    func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    /// Top-level JSON fields, for messages small enough not to deserve a type.
    var fields: [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

/// The single shared WebSocket to `/ws`, a port of the web app's
/// `lib/realtime.ts`.
///
/// Screens subscribe to topics (`vehicles@<modes>`, `stop:SP85`, `trip:…`,
/// `runs:20261029`, `sync`, `parking`); the server pushes as soon as anything
/// changes. A dropped connection reconnects with growing backoff and restores
/// every subscription. While `connected` is false, screens fall back to
/// polling the REST endpoints.
@MainActor
final class RealtimeClient: ObservableObject {
    static let shared = RealtimeClient()

    typealias Listener = (RealtimeMessage) -> Void

    @Published private(set) var connected = false
    /// Bumps every time the server clock arrives (on each connect).
    @Published private(set) var clockVersion = 0

    private var serverOffset: TimeInterval = 0
    private var task: URLSessionWebSocketTask?
    private var listeners: [String: [UUID: Listener]] = [:]
    private var globalListeners: [UUID: Listener] = [:]
    private var retry = 0
    private var reconnectTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var auth: (token: String, deviceId: String)?
    private var lastMessageAt = Date.distantPast
    private let session = URLSession(configuration: .default)

    /// Wait this long for a pong after waking before assuming the socket died.
    private let wakeProbe: Duration = .seconds(3)
    /// The vehicle feed pushes every few seconds; this long without any
    /// message means a socket the system still calls open may be dead (a
    /// switch between Wi-Fi and cellular leaves no error behind).
    private let silenceLimit: TimeInterval = 20

    private static let url: URL = {
        let base = APIConfig.baseURL
        let scheme = base.scheme == "http" ? "ws" : "wss"
        guard let host = base.host(), let url = URL(string: "\(scheme)://\(host)/ws") else {
            fatalError("Cannot derive the WebSocket URL from \(base)")
        }
        return url
    }()

    /// The server's clock now, in unix seconds. A replayed day on the server
    /// can differ from the device clock.
    var serverNow: TimeInterval { Date().timeIntervalSince1970 + serverOffset }

    // MARK: - Subscriptions

    /// Subscribes to a topic. The returned token unsubscribes when cancelled
    /// or deallocated.
    func subscribe(_ topic: String, _ listener: @escaping Listener) -> AnyCancellable {
        let id = UUID()
        let fresh = listeners[topic] == nil
        listeners[topic, default: [:]][id] = listener
        ensure()
        if fresh, connected { send(["t": "sub", "topics": [topic]]) }
        return AnyCancellable { [weak self] in
            Task { @MainActor in self?.unsubscribe(topic, id: id) }
        }
    }

    func onAny(_ listener: @escaping Listener) -> AnyCancellable {
        let id = UUID()
        globalListeners[id] = listener
        ensure()
        return AnyCancellable { [weak self] in
            Task { @MainActor in self?.globalListeners[id] = nil }
        }
    }

    private func unsubscribe(_ topic: String, id: UUID) {
        listeners[topic]?[id] = nil
        guard listeners[topic]?.isEmpty == true else { return }
        listeners[topic] = nil
        if connected { send(["t": "unsub", "topics": [topic]]) }
    }

    /// A signed-in user: the server tells this device about changes saved on
    /// the rider's other devices.
    func authenticate(token: String?, deviceId: String) {
        auth = token.map { ($0, deviceId) }
        if let token, connected { send(["t": "auth", "token": token, "deviceId": deviceId]) }
    }

    // MARK: - Connection

    private func ensure() {
        guard task == nil, reconnectTask == nil else { return }
        let task = session.webSocketTask(with: Self.url)
        self.task = task
        task.resume()
        receive(on: task)
        // URLSessionWebSocketTask has no open callback; the first successful
        // send is the earliest moment the socket is known to be up.
        task.send(.string(#"{"t":"ping"}"#)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                if error != nil { self.drop(task) } else { self.didOpen() }
            }
        }
    }

    private func didOpen() {
        retry = 0
        connected = true
        startKeepalive()
        if let auth { send(["t": "auth", "token": auth.token, "deviceId": auth.deviceId]) }
        let topics = Array(listeners.keys)
        if !topics.isEmpty { send(["t": "sub", "topics": topics]) }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receive(on: task)
                case .failure:
                    self.drop(task)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        lastMessageAt = Date()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["t"] as? String else { return }

        if type == "hello", let now = object["now"] as? Double {
            serverOffset = now - Date().timeIntervalSince1970
            clockVersion += 1
        }

        let topic = Self.topic(of: object, type: type)
        let message = RealtimeMessage(type: type, topic: topic, data: data)
        for listener in globalListeners.values { listener(message) }
        if let topic, let topicListeners = listeners[topic] {
            for listener in topicListeners.values { listener(message) }
        }
    }

    private static func topic(of object: [String: Any], type: String) -> String? {
        // The server names the topic itself for mode-scoped topics such as
        // `vehicles@tram,bus,rail`; that wins.
        if let topic = object["topic"] as? String { return topic }
        switch type {
        case "vehicles": return "vehicles"
        case "stop": return (object["id"] as? String).map { "stop:\($0)" }
        case "trip": return (object["id"] as? String).map { "trip:\($0)" }
        case "runs": return (object["date"] as? String).map { "runs:\($0)" }
        case "sync": return "sync"
        case "parking": return "parking"
        default: return nil
        }
    }

    private func drop(_ dead: URLSessionWebSocketTask) {
        guard task === dead else { return }
        dead.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
        keepaliveTask?.cancel()
        keepaliveTask = nil
        if !listeners.isEmpty || !globalListeners.isEmpty { scheduleReconnect() }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        let delay = min(15.0, 0.5 * pow(2, Double(retry))) + Double.random(in: 0...0.4)
        retry += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconnectTask = nil
            self?.ensure()
        }
    }

    /// Coming back to the foreground: reconnect at once. A socket the system
    /// still reports as open may be long dead after sleep or a network
    /// change, so it is pinged and dropped if nothing answers.
    func wake() {
        reconnectTask?.cancel()
        reconnectTask = nil
        retry = 0
        guard let task, connected else {
            ensure()
            return
        }
        probe(task)
    }

    /// Pings, and drops the socket if nothing at all arrives in reply; the
    /// reconnect re-subscribes and the server sends every topic's full state.
    private func probe(_ task: URLSessionWebSocketTask) {
        let sentAt = Date()
        send(["t": "ping"])
        Task { [weak self] in
            try? await Task.sleep(for: self?.wakeProbe ?? .seconds(3))
            guard let self, self.task === task, self.lastMessageAt < sentAt else { return }
            self.drop(task)
        }
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, let task = self.task, self.connected else { return }
                if Date().timeIntervalSince(self.lastMessageAt) > self.silenceLimit { self.probe(task) }
            }
        }
    }

    private func send(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }
}
