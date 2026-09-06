//
//  StopCodeSearchOverlay.swift
//  MVK++ Phone App
//

import CoreLocation
import SwiftUI

/// Jump straight to a stop by the number printed on its sign.
///
/// GTFS calls it `SP569`; the sign says `569`. Both are accepted, and if the
/// loaded catalog does not know the code, the arrivals endpoint is asked —
/// it sometimes knows stops the static feed has not caught up with.
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

        isBusy = true
        defer { isBusy = false }

        let id = "SP\(raw)"
        do {
            let response = try await APIClient.shared.arrivals(stopId: id, limit: 16)
            let coordinate = (response.stop.lat).flatMap { lat in
                (response.stop.lon).map { CLLocationCoordinate2D(latitude: lat, longitude: $0) }
            }
            onResolved(response.stop.id, coordinate)
        } catch {
            errorText = "Nincs \(raw) kódú megálló."
        }
    }

    private func findLocally(_ raw: String) -> Stop? {
        let needle = raw.lowercased().replacingOccurrences(of: "sp", with: "")
        guard !needle.isEmpty else { return nil }
        return stops.first { $0.id.lowercased() == "sp\(needle)" }
            ?? stops.first { $0.id.lowercased() == needle }
    }
}
