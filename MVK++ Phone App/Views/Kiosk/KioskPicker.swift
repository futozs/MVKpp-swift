//
//  KioskPicker.swift
//  MVK++ Phone App
//

import SwiftUI

/// The board's stop picker: one to three stops, in the order picked.
struct KioskPicker: View {
    let stops: [Stop]
    @Binding var selected: [String]
    /// nil while nothing is picked yet: the board needs at least one stop.
    let onClose: (() -> Void)?

    @ObservedObject private var local = LocalStore.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var byId: [String: Stop] {
        Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The row's right side: an MVK stop's code, a regional one's kind.
    private func tag(_ s: Stop?) -> String? {
        guard let s else { return nil }
        return TransitModes.isRegionalId(s.id) ? KioskStops.kindLabel(s) : s.code
    }

    private var results: [Stop] {
        let q = query.trimmingCharacters(in: .whitespaces).normalizedForSearch
        guard !q.isEmpty else { return [] }
        // In the merged view a Volán twin is not separate: the MVK pole shows its departures.
        let merge = local.stopMerge
        let pickable = KioskStops.pickable(stops).filter { !TransitModes.isMergedTwin($0, merge: merge) }
        // Stations first (Tiszai pu., Búza téri autóbusz-állomás).
        return pickable
            .filter { $0.name.normalizedForSearch.contains(q) || $0.code.lowercased().contains(q) }
            .sorted { a, b in
                let ra = KioskStops.regionRank(a), rb = KioskStops.regionRank(b)
                if ra != rb { return ra < rb }
                return a.station && !b.station
            }
            .prefix(40)
            .map { $0 }
    }

    private var full: Bool { selected.count >= KioskStops.maxCount }

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            Theme.background.opacity(0.8)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                selectedList
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { s in
                            resultRow(s)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 8)
                .frame(maxHeight: .infinity)
                footer
            }
            .background(Theme.card, in: card)
            .clipShape(card)
            .overlay(card.strokeBorder(Theme.border, lineWidth: 1))
            .mvkShadow(Theme.Shadow.xl)
            .frame(maxWidth: 512)
            .padding(16)
        }
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kijelző: megállók")
                    .font(Theme.sans(18, weight: .bold))
                    .tracking(-0.3)
                Text("Legalább 1, legfeljebb \(KioskStops.maxCount) megálló, egymás mellett.")
                    .font(Theme.sans(12.5))
                    .foregroundStyle(Theme.mutedForeground)
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-10)
                .accessibilityLabel("Bezárás")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var selectedList: some View {
        VStack(spacing: 6) {
            ForEach(Array(selected.enumerated()), id: \.element) { index, id in
                let s = byId[id]
                let row = RoundedRectangle(cornerRadius: 12, style: .continuous)
                HStack(spacing: 12) {
                    Text("\(index + 1).")
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                    Text(s?.name ?? id)
                        .font(Theme.sans(14, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let tag = tag(s) {
                        Text(tag).font(Theme.mono(11, weight: .regular)).foregroundStyle(Theme.mutedForeground)
                    }
                    Button {
                        withAnimation(Theme.Motion.fastAnimation) { selected.removeAll { $0 == id } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(s?.name ?? id) eltávolítása")
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
                .background(Theme.background.opacity(0.6), in: row)
                .overlay(row.strokeBorder(Theme.border, lineWidth: 1))
            }
            if selected.isEmpty {
                Text("Válassz megállót lent.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.mutedForeground)
            TextField("", text: $query, prompt: Text(full ? "Legfeljebb \(KioskStops.maxCount) megálló" : "Megálló neve vagy kódja").foregroundStyle(Theme.mutedForeground))
                .font(Theme.sans(14))
                .focused($searchFocused)
                .disabled(full)
                .autocorrectionDisabled()
                .accessibilityLabel("Megálló keresése")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
        .opacity(full ? 0.5 : 1)
    }

    private func resultRow(_ s: Stop) -> some View {
        let added = selected.contains(s.id)
        return Button {
            withAnimation(Theme.Motion.fastAnimation) { selected.append(s.id) }
            query = ""
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text(s.name)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let tag = tag(s) {
                    Text(tag).font(Theme.mono(11, weight: .regular)).foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added || full)
        .opacity(added || full ? 0.4 : 1)
    }

    private var footer: some View {
        Button {
            onClose?()
        } label: {
            Text("Kijelző indítása")
        }
        .buttonStyle(.mvk(fullWidth: true, height: 44))
        .disabled(selected.isEmpty)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
