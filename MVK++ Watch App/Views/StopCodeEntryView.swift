//
//  StopCodeEntryView.swift
//  MVK++ Watch App
//

import SwiftUI
import WatchKit

/// Passcode-style numeric keypad for typing a stop's rider-facing number
/// (the digits in its id, e.g. "84" for "SP84") straight in, instead of
/// spelling out the stop's name in the text search.
///
/// Serves both entry points on the root list: `.lookup` just opens the stop
/// (a throwaway check, nothing is saved), `.add` puts it on the watched list.
///
/// The layout is driven by the available height so the readout, all ten
/// digits, backspace and the submit key always fit on a single screen —
/// even on a 40mm watch — without scrolling.
struct StopCodeEntryView: View {
    /// What the checkmark does with the stop the typed code resolves to.
    enum Mode {
        /// Open it once, without touching the watched list.
        case lookup
        /// Add it to the watched list.
        case add
    }

    let mode: Mode
    /// Called with the resolved stop id in `.lookup` mode, after the sheet
    /// asks to dismiss — the caller navigates once it is actually gone.
    var onLookup: (String) -> Void = { _ in }

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var errorMessage: String?

    private static let maxDigits = 4

    /// Bottom row pairs backspace and submit around the zero, so ten digits
    /// plus both actions live in four rows instead of five.
    private enum Key: Hashable {
        case digit(String)
        case backspace
        case submit
    }

    private static let rows: [[Key]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.backspace, .digit("0"), .submit],
    ]

    private static let readoutHeight: CGFloat = 26
    private static let gap: CGFloat = 3
    private static let minKeyHeight: CGFloat = 20
    private static let maxKeyHeight: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            let keyHeight = keyHeight(forAvailable: proxy.size.height)

            VStack(spacing: Self.gap) {
                readout

                ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.gap) {
                        ForEach(row, id: \.self) { key in
                            keypadButton(key, height: keyHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 4)
        .mvkBackground()
        .task {
            await catalog.loadIfNeeded()
        }
    }

    /// Splits whatever vertical room the sheet actually got between the four
    /// key rows, clamped so keys stay tappable but never overflow.
    private func keyHeight(forAvailable height: CGFloat) -> CGFloat {
        let rowCount = CGFloat(Self.rows.count)
        let free = height - Self.readoutHeight - Self.gap * rowCount
        return min(max(free / rowCount, Self.minKeyHeight), Self.maxKeyHeight)
    }

    private var readout: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.card.opacity(0.9))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.late)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 5)
            } else {
                Text(digits.isEmpty ? placeholder : digits)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(digits.isEmpty ? Theme.mutedForeground : Theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 5)
            }
        }
        .frame(height: Self.readoutHeight)
    }

    private var placeholder: String {
        switch mode {
        case .lookup: "Kód"
        case .add: "Új kedvenc"
        }
    }

    @ViewBuilder
    private func keypadButton(_ key: Key, height: CGFloat) -> some View {
        Button {
            handle(key)
        } label: {
            keyLabel(key, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fill(for: key))
                )
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .disabled(isDisabled(key))
        .opacity(isDisabled(key) ? 0.35 : 1)
    }

    @ViewBuilder
    private func keyLabel(_ key: Key, height: CGFloat) -> some View {
        switch key {
        case .digit(let value):
            Text(value)
                .font(.system(size: min(height * 0.55, 20), weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.foreground)
        case .backspace:
            Image(systemName: "delete.left.fill")
                .font(.system(size: min(height * 0.42, 15), weight: .semibold))
                .foregroundStyle(Theme.foreground)
        case .submit:
            Image(systemName: "checkmark")
                .font(.system(size: min(height * 0.48, 17), weight: .bold))
                .foregroundStyle(.black)
        }
    }

    private func fill(for key: Key) -> Color {
        switch key {
        case .submit: Theme.primary
        case .backspace: Theme.card.opacity(0.65)
        case .digit: Theme.card
        }
    }

    private func isDisabled(_ key: Key) -> Bool {
        switch key {
        case .submit, .backspace: digits.isEmpty
        case .digit: digits.count >= Self.maxDigits
        }
    }

    private func handle(_ key: Key) {
        errorMessage = nil
        switch key {
        case .backspace:
            guard !digits.isEmpty else { return }
            digits.removeLast()
            WKInterfaceDevice.current().play(.click)
        case .digit(let value):
            guard digits.count < Self.maxDigits else { return }
            digits += value
            WKInterfaceDevice.current().play(.click)
        case .submit:
            search()
        }
    }

    private func search() {
        guard let stop = resolvedStop() else {
            errorMessage = "Nincs ilyen kód"
            WKInterfaceDevice.current().play(.failure)
            return
        }

        switch mode {
        case .lookup:
            WKInterfaceDevice.current().play(.click)
            onLookup(stop.id)
            dismiss()
        case .add:
            guard !favorites.stopIds.contains(stop.id) else {
                errorMessage = "Már hozzáadva"
                WKInterfaceDevice.current().play(.failure)
                return
            }
            guard favorites.stopIds.count < FavoritesStore.maxCount else {
                errorMessage = "Max \(FavoritesStore.maxCount) megálló"
                WKInterfaceDevice.current().play(.failure)
                return
            }
            favorites.add(stop.id)
            WKInterfaceDevice.current().play(.success)
            dismiss()
        }
    }

    /// Prefers the exact "SP<digits>" id, then falls back to the catalog's
    /// own fuzzy match so codes that don't follow that shape still resolve.
    private func resolvedStop() -> Stop? {
        catalog.stops.first { $0.id == "SP\(digits)" }
            ?? catalog.stops.first { $0.matches(digits) }
    }
}

#Preview("Megnyitás") {
    StopCodeEntryView(mode: .lookup)
        .environmentObject(FavoritesStore())
        .environmentObject(StopsCatalog())
}

#Preview("Hozzáadás") {
    StopCodeEntryView(mode: .add)
        .environmentObject(FavoritesStore())
        .environmentObject(StopsCatalog())
}
