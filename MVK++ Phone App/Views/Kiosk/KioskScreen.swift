//
//  KioskScreen.swift
//  MVK++ Phone App
//

import SwiftUI
import UIKit

/// The passenger-information board (web `/kijelzo`): one to three stops side
/// by side (stacked on a portrait screen), full screen, live. Type scales to
/// the screen; the controls fade out when nobody touches it.
struct KioskScreen: View {
    let onClose: () -> Void

    @EnvironmentObject private var store: TransitStore
    @ObservedObject private var local = LocalStore.shared
    @ObservedObject private var realtime = RealtimeClient.shared

    @State private var ids: [String]
    @State private var picking: Bool
    @State private var idle = false
    @State private var hidesStatusBar = false
    @State private var now = Date()
    @State private var idleTask: Task<Void, Never>?

    private static let idleDelay: Duration = .seconds(4)

    /// Starting stops: the ones passed in (the web's `?m=`), the last board,
    /// or the first three watched stops.
    init(stopIds: [String], onClose: @escaping () -> Void) {
        self.onClose = onClose
        let initial: [String]
        if !stopIds.isEmpty {
            initial = Array(stopIds.prefix(KioskStops.maxCount))
        } else {
            let last = LocalStore.shared.stringList(KioskStops.storageKey)
            initial = Array((last.isEmpty ? FavoritesStore.storedStopIds : last).prefix(KioskStops.maxCount))
        }
        _ids = State(initialValue: initial)
        _picking = State(initialValue: initial.isEmpty)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest")
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let n = max(1, ids.count)
            let portrait = size.height > size.width && n > 1
            let topH = (max(48, min(96, size.height * 0.085))).rounded()
            let colW = portrait ? size.width : size.width / CGFloat(n)
            let colH = portrait ? (size.height - topH) / CGFloat(n) : size.height - topH
            // A column wants roughly 28 em of width and 25 em of height.
            let em = max(12, min(40, colW / 28, colH / 25))
            // Under the featured departure as many rows as fit (header + featured ≈ 9.5 em, a row ≈ 3.4 em).
            let restRows = max(3, min(9, Int(((colH / em) - 9.5) / 3.4)))
            let byId = Dictionary(store.stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let boardKey = local.boardKey

            VStack(spacing: 0) {
                topBar(width: size.width, height: topH)
                let layout = portrait ? AnyLayout(VStackLayout(spacing: 0.6 * em)) : AnyLayout(HStackLayout(spacing: 0.6 * em))
                layout {
                    ForEach(ids, id: \.self) { id in
                        KioskColumn(stop: byId[id], stopId: id, rows: restRows, em: em, boardKey: boardKey)
                            .id("\(id)@\(boardKey)")
                    }
                }
                .padding(.horizontal, 0.6 * em)
                .padding(.bottom, 0.6 * em)
            }
            .overlay(alignment: .bottomTrailing) { controls }
            .overlay {
                if picking {
                    KioskPicker(stops: store.stops, selected: $ids, onClose: ids.isEmpty ? nil : { picking = false })
                        .transition(.opacity)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .statusBarHidden(hidesStatusBar)
        .persistentSystemOverlays(hidesStatusBar ? .hidden : .automatic)
        .contentShape(Rectangle())
        // Any touch wakes the controls, the buttons and the picker included.
        .simultaneousGesture(TapGesture().onEnded { wake() })
        .task {
            while !Task.isCancelled {
                now = Date(timeIntervalSince1970: realtime.serverNow)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            UsageReporter.shared.track("kiosk")
            UIApplication.shared.isIdleTimerDisabled = !picking
            wake()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTask?.cancel()
        }
        .onChange(of: ids) { _, next in
            wake()
            guard !next.isEmpty else { return }
            local.setJSON(KioskStops.storageKey, next)
        }
        // The screen stays on for the board, not while picking (web `useWakeLock(!picking)`).
        .onChange(of: picking) { _, isPicking in
            UIApplication.shared.isIdleTimerDisabled = !isPicking
            wake()
        }
        .animation(Theme.Motion.normalAnimation, value: picking)
    }

    private func topBar(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("MVK++")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.primaryForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                if width >= 640 {
                    Text(Self.dateFormatter.string(from: now))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                if realtime.connected {
                    LiveDot(size: 8).accessibilityLabel("élő")
                } else {
                    Circle().fill(Theme.mutedForeground.opacity(0.5)).frame(width: 8, height: 8).accessibilityLabel("kapcsolódás…")
                }
            }
            Spacer(minLength: 0)
            Text(Self.timeFormatter.string(from: now))
                .font(Theme.mono(height * 0.5, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, max(8, width * 0.02))
        .frame(height: height)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Label("Kilépés", systemImage: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            Button {
                picking = true
            } label: {
                Label("Megállók", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            Button {
                hidesStatusBar.toggle()
            } label: {
                Image(systemName: hidesStatusBar ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(hidesStatusBar ? "Kilépés a teljes képernyőből" : "Teljes képernyő")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.foreground)
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(16)
        .opacity(idle && !picking ? 0 : 1)
        .allowsHitTesting(!(idle && !picking))
        .animation(Theme.Motion.normalAnimation, value: idle)
    }

    /// Without a touch the controls fade out.
    private func wake() {
        idle = false
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            idle = true
        }
    }
}
