//
//  LocalStore.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import SwiftUI

/// The phone's equivalent of the web app's `localStorage`: string values
/// under the web's `mvk_*` key names, in the web's encoding (`usePreference`
/// writes `JSON.stringify(value)`, so a switch is `"true"`/`"false"` and a
/// choice is `"\"all\""`).
///
/// Keeping the web's names and encoding is what lets cloud sync carry a
/// rider's settings between the browser and the iPhone without translation.
@MainActor
final class LocalStore: ObservableObject {
    static let shared = LocalStore()

    let defaults = UserDefaults.standard
    /// Every key written through this store, as it is written.
    let changes = PassthroughSubject<String, Never>()

    private var observer: NSObjectProtocol?
    private var refreshScheduled = false

    private init() {
        // Writes that bypass this store (another store's own persistence, a
        // sync being applied) still refresh every view reading a preference.
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshScheduled = false
            self?.objectWillChange.send()
        }
    }

    // MARK: - Raw strings

    func string(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ key: String, _ value: String?) {
        guard defaults.string(forKey: key) != value else { return }
        objectWillChange.send()
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        changes.send(key)
    }

    // MARK: - JSON values (usePreference)

    func json<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let raw = string(key), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setJSON<T: Encodable>(_ key: String, _ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return }
        set(key, text)
    }

    /// A web switch: anything but a stored `false` counts as on.
    func bool(_ key: String, default fallback: Bool = true) -> Bool {
        json(key, as: Bool.self) ?? fallback
    }

    func setBool(_ key: String, _ value: Bool) {
        setJSON(key, value)
    }

    func stringList(_ key: String) -> [String] {
        json(key, as: [String].self) ?? []
    }

    // MARK: - Bindings

    func boolBinding(_ key: String, default fallback: Bool = true) -> Binding<Bool> {
        Binding(get: { self.bool(key, default: fallback) }, set: { self.setBool(key, $0) })
    }
}
