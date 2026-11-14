//
//  AppHeader.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// The mobile header (web `MobileHeader`): the brand mark, the live status,
/// the temperature, and the notifications and settings buttons. The bar
/// floats as Liquid Glass over whatever the tab shows.
struct AppHeader: View {
    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject var weather: WeatherModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                BrandMark { navigation.tab = .map }

                LiveStatusPill(
                    vehicleCount: store.liveVehicles.count,
                    lastUpdated: store.lastUpdated,
                    isRefreshing: store.isRefreshing,
                    weather: weather.weather,
                    onRefresh: { Task { await store.refreshLive() } }
                )
                .layoutPriority(1)

                Spacer(minLength: 0)

                if let temp = weather.weather?.tempC {
                    Text("\(Int(temp.rounded()))°")
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .glassEffect(.regular.tint(Theme.glassTint), in: Capsule())
                        .accessibilityLabel("Miskolc most \(WeatherResponse.format(temp)), \(weather.weather?.text ?? "")")
                }

                HeaderIconButton(systemImage: "bell", label: "Értesítések") {
                    navigation.isNotificationsOpen = true
                }
                HeaderIconButton(systemImage: "gearshape", label: "Beállítások") {
                    navigation.isSettingsOpen = true
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
        }
        .overlay(alignment: .bottom) { RefreshSweep(isRefreshing: store.isRefreshing) }
    }
}

/// The text mark. The tile echoes the route tiles running on the map — same
/// weight, corner and inner light — so header and map speak one language.
struct BrandMark: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("MVK")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(-0.4)
                Text("++")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(-0.6)
                    .opacity(0.6)
            }
            .foregroundStyle(Theme.primaryForeground)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .mvkShadow(Theme.Shadow.sm)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("MVK++ ugrás a forgalmi térképre")
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}

struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.glassTint).interactive(), in: Circle())
        .accessibilityLabel(label)
    }
}

/// A sweep along the header's bottom edge, only while data is loading.
struct RefreshSweep: View {
    let isRefreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            if isRefreshing && !reduceMotion {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Theme.primary, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width / 4, height: 2)
                    .offset(x: phase ? proxy.size.width * 1.05 : -proxy.size.width * 0.3)
                    .onAppear {
                        phase = false
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.2).repeatForever(autoreverses: false)) { phase = true }
                    }
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Live status

/// Tells the truth: "Élő" only while the WebSocket channel is really up.
/// Briefly "Kapcsolódás…" at launch; if the channel does not come up in that
/// time, or drops later: "Újracsatlakozás…" (the polling fallback runs then).
struct LiveStatusModel {
    enum LinkState { case live, connecting, reconnecting }

    let state: LinkState
    let isStale: Bool
    let ageMin: Int?

    static let staleAfter: TimeInterval = 2 * 60

    var label: String {
        switch state {
        case .live: return "Élő"
        case .connecting: return "Kapcsolódás…"
        case .reconnecting: return "Újracsatlakozás…"
        }
    }

    var title: String {
        switch state {
        case .live: return "Élő kapcsolat"
        case .connecting: return "Kapcsolódás…"
        case .reconnecting: return "Újracsatlakozás…"
        }
    }

    var body: String {
        switch state {
        case .live: return "A szerver azonnal küldi a járműpozíciókat, amint változnak nem kell kézzel frissíteni."
        case .connecting: return "Épül a valós idejű csatorna. Addig néhány másodpercenként lekérdezéssel frissítünk."
        case .reconnecting: return "Megszakadt a valós idejű csatorna. Amíg helyreáll, néhány másodpercenként lekérdezéssel frissítünk, így a pozíciók kicsit késhetnek."
        }
    }

    var textColor: Color {
        switch state {
        case .live: return Theme.live
        case .connecting: return Theme.mutedForeground
        case .reconnecting: return Theme.amber300
        }
    }

    var dotColor: Color {
        switch state {
        case .live: return Theme.live
        case .connecting: return Theme.mutedForeground
        case .reconnecting: return Theme.amber400
        }
    }

    static func clock(_ date: Date, seconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        return formatter.string(from: date)
    }
}

/// The state machine behind the pill: the 3 s connect grace and the
/// "has ever connected" memory.
@MainActor
final class LiveStatusTracker: ObservableObject {
    static let shared = LiveStatusTracker()

    @Published private(set) var inGrace = true
    @Published private(set) var hasConnected = false
    @Published private(set) var now = Date()
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        RealtimeClient.shared.$connected
            .sink { [weak self] connected in if connected { self?.hasConnected = true } }
            .store(in: &cancellables)
        Timer.publish(every: 15, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in self?.now = date }
            .store(in: &cancellables)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.inGrace = false
        }
    }

    func model(connected: Bool, lastUpdated: Date?) -> LiveStatusModel {
        let state: LiveStatusModel.LinkState = connected ? .live : (!hasConnected && inGrace ? .connecting : .reconnecting)
        let age = lastUpdated.map { max(0, now.timeIntervalSince($0)) }
        return LiveStatusModel(state: state, isStale: (age ?? 0) > LiveStatusModel.staleAfter, ageMin: age.map { Int($0 / 60) })
    }
}

/// The mobile status chip; a tap opens the explanation and the manual refresh.
struct LiveStatusPill: View {
    let vehicleCount: Int
    let lastUpdated: Date?
    let isRefreshing: Bool
    let weather: WeatherResponse?
    let onRefresh: () -> Void

    @ObservedObject private var realtime = RealtimeClient.shared
    @ObservedObject private var tracker = LiveStatusTracker.shared
    @State private var isOpen = false

    var body: some View {
        let status = tracker.model(connected: realtime.connected, lastUpdated: lastUpdated)
        Button { isOpen = true } label: {
            HStack(spacing: 8) {
                StatusDot(state: status.state)
                Text(status.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.textColor)
                    .lineLimit(1)
                if status.state == .live {
                    Divider().frame(height: 14).overlay(Theme.border)
                    HStack(spacing: 4) {
                        Image(systemName: "bus")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.mutedForeground)
                        Text("\(vehicleCount)")
                            .font(Theme.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                    }
                    .fixedSize()
                }
                if let lastUpdated {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Divider().frame(height: 14).overlay(Theme.border)
                            Text(LiveStatusModel.clock(lastUpdated, seconds: false))
                                .font(Theme.mono(12, weight: .regular))
                                .foregroundStyle(status.isStale ? Theme.amber300 : Theme.mutedForeground)
                                .fixedSize()
                        }
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(glass(status.state), in: Capsule())
        .accessibilityLabel("\(summary(status)). Részletek")
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 14) {
                LiveStatusDetails(status: status, vehicleCount: vehicleCount, lastUpdated: lastUpdated, weather: weather)
                Button(action: onRefresh) {
                    Label(isRefreshing ? "Frissítés…" : "Frissítés most", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: isRefreshing)
                }
                .buttonStyle(.mvk(.outline, size: .large, fullWidth: true))
                .disabled(isRefreshing)
            }
            .padding(14)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Theme.popover)
        }
    }

    private func glass(_ state: LiveStatusModel.LinkState) -> Glass {
        state == .reconnecting ? .regular.tint(Theme.amber400.opacity(0.22)).interactive() : .regular.tint(Theme.glassTint).interactive()
    }

    /// "Élő kapcsolat. 88 jármű, utolsó adat 01:08:24"
    private func summary(_ status: LiveStatusModel) -> String {
        let time = lastUpdated.map { ", utolsó adat \(LiveStatusModel.clock($0, seconds: true))" } ?? ""
        return "\(status.title.replacingOccurrences(of: "…", with: "")). \(vehicleCount) jármű\(time)"
    }
}

struct StatusDot: View {
    let state: LiveStatusModel.LinkState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if state == .live {
                Circle().fill(Theme.live)
                    .scaleEffect(pulse ? 0.75 : 1)
                    .opacity(pulse ? 0.4 : 1)
            }
            Circle().fill(color).opacity(state != .live && pulse ? 0.5 : 1)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .live: return Theme.live
        case .connecting: return Theme.mutedForeground
        case .reconnecting: return Theme.amber400
        }
    }
}

/// What the state means and where the number comes from.
struct LiveStatusDetails: View {
    let status: LiveStatusModel
    let vehicleCount: Int
    let lastUpdated: Date?
    let weather: WeatherResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusDot(state: status.state)
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status.state == .reconnecting ? Theme.amber300 : Theme.foreground)
            }
            Text(status.body)
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedForeground)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.bottom, 4)
                row("Élő járművek") {
                    Text("\(vehicleCount)").font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.foreground)
                }
                row("Utolsó adat") {
                    HStack(spacing: 6) {
                        Text(lastUpdated.map { LiveStatusModel.clock($0, seconds: true) } ?? "")
                            .font(Theme.mono(12, weight: .semibold))
                        if status.isStale, let age = status.ageMin {
                            Text("· \(age) perce").font(.system(size: 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(status.isStale ? Theme.amber300 : Theme.foreground)
                }
                if let weather, let temp = weather.tempC {
                    row("Időjárás") {
                        HStack(spacing: 6) {
                            Text(WeatherResponse.format(temp)).font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.foreground)
                            Text(weather.text).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
            }
            if let weather, weather.tempC != nil, !weather.extras.isEmpty {
                Text("Miskolc · \(weather.extras)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func row<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
            Spacer(minLength: 16)
            value()
        }
    }
}
