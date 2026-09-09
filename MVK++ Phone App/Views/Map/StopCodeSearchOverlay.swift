//
//  StopCodeSearchOverlay.swift
//  MVK++ Phone App
//

import CoreLocation
import SwiftUI

/// Jump straight to a stop by the number printed on its sign.
///
/// GTFS calls it `SP569`; the sign says `569`. Both are accepted.
///
/// The lookup is resolved on the device wherever it can be — first from the
/// catalog this session loaded, then from the App Group mirror a previous
/// session left behind — and only asks the gateway when neither knows the
/// code. Typing a stop number is the one thing a rider does *because* they are
/// standing at a stop with no signal, so it must not depend on one.
struct StopCodeSearchOverlay: View {
    let stops: [Stop]
    var onClose: () -> Void
    var onResolved: (String, CLLocationCoordinate2D?) -> Void

    @State private var code = ""
    @State private var errorText: String?
    @State private var isBusy = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("MEGÁLLÓKÓD")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 8)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bezárás")
                }

                HStack(spacing: 10) {
                    TextField("", text: $code, prompt: Text("1").foregroundStyle(.white.opacity(0.4)))
                        .font(Theme.mono(26))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .textFieldStyle(.plain)
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        .onChange(of: code) { _, value in
                            let digits = value.filter(\.isNumber)
                            if digits != value { code = digits }
                            errorText = nil
                        }
                        .onSubmit { Task { await resolve() } }

                    Button {
                        Task { await resolve() }
                    } label: {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(code.isEmpty ? .white.opacity(0.4) : Theme.primaryForeground)
                            .frame(width: 54, height: 54)
                            .background(
                                code.isEmpty ? Color.white.opacity(0.14) : Theme.primary,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(code.isEmpty || isBusy)
                    .accessibilityLabel("Ugrás a megállóhoz")
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.late)
                } else {
                    Text("A megállótáblán kiírt szám.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(18)
            .frame(maxWidth: 320)
            .floatingGlass(cornerRadius: Theme.Radius.xxl)
            .padding(.horizontal, 24)
        }
        .onAppear { isFocused = true }
    }

    private func resolve() async {
        let raw = code.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        if let local = findLocally(raw) {
            onResolved(local.id, CLLocationCoordinate2D(latitude: local.lat, longitude: local.lon))
            return
        }

        if let mirrored = findInMirror(raw) {
            onResolved(mirrored.id, CLLocationCoordinate2D(latitude: mirrored.lat, longitude: mirrored.lon))
            return
        }

        isBusy = true
        defer { isBusy = false }

        // Nothing on the device knows it. The gateway sometimes does — it sees
        // stops the static feed has not caught up with.
        do {
            let response = try await APIClient.shared.arrivals(stopId: "SP\(raw)", limit: 16)
            let coordinate = (response.stop.lat).flatMap { lat in
                (response.stop.lon).map { CLLocationCoordinate2D(latitude: lat, longitude: $0) }
            }
            onResolved(response.stop.id, coordinate)
        } catch {
            // Two different answers, and the rider needs to know which: the
            // code is wrong, or the code is unverifiable right now.
            errorText = hasLocalCatalog
                ? "Nincs \(raw) kódú megálló."
                : "Nincs kapcsolat, és nincs letöltött megállólista."
        }
    }

    /// The catalog this session loaded — online or rehydrated from the mirror.
    private func findLocally(_ raw: String) -> Stop? {
        let needle = normalized(raw)
        guard !needle.isEmpty else { return nil }
        return stops.first { $0.id.lowercased() == "sp\(needle)" }
            ?? stops.first { $0.id.lowercased() == needle }
    }

    /// The App Group mirror, for the case where the map opened before the
    /// catalog finished loading — or never could.
    private func findInMirror(_ raw: String) -> CachedStop? {
        let needle = normalized(raw)
        guard !needle.isEmpty else { return nil }
        let mirrored = SharedStopCache.load()
        return mirrored.first { $0.id.lowercased() == "sp\(needle)" }
            ?? mirrored.first { $0.riderCode == needle }
    }

    private func normalized(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "sp", with: "")
    }

    private var hasLocalCatalog: Bool {
        !stops.isEmpty || SharedStopCache.lastUpdated != nil
    }
}
