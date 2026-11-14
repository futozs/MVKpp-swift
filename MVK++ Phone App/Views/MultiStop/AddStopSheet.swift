//
//  AddStopSheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// „Felvétel a figyelőre” — the web app's `AddStopModal`: stops, relations
/// (A → B) and train numbers. Stays open after each pick, because riders add
/// several at once.
struct AddStopSheet: View {
    let stops: [Stop]

    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var watches = TransitWatchesStore.shared
    @Environment(\.dismiss) private var dismiss

    enum Tab: Hashable { case stops, relation, train }

    @State private var tab: Tab = .stops
    @State private var query = ""
    @State private var relFrom: Stop?
    @State private var trainQuery = ""
    @State private var trainHits: [TransitSearchTrain]?
    @FocusState private var searchFocused: Bool

    private var showRail: Bool { TransitMode.enabled().contains(.rail) }

    private var tabs: [(id: Tab, label: String, icon: String)] {
        var list: [(Tab, String, String)] = [(.stops, "Megálló", "mappin"), (.relation, "Viszonylat", "point.topleft.down.to.point.bottomright.curvepath")]
        if showRail { list.append((.train, "Vonatszám", "train.side.front.car")) }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Felvétel a figyelőre")
                    .font(Theme.sans(18, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(Theme.foreground)
                Text(description)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            HairlineDivider()

            if tabs.count > 1 {
                tabBar
                HairlineDivider()
            }

            if tab == .train {
                trainTab
            } else {
                stopSearch
                HairlineDivider()
                stopResults
            }

            HairlineDivider()
            HStack(spacing: 12) {
                Text(footerText)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    relFrom = nil
                    dismiss()
                } label: {
                    Text("Kész")
                }
                .buttonStyle(.mvk(size: .small))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .mvkDialog()
        .task(id: trainSearchKey) { await searchTrains() }
    }

    // MARK: - Header texts

    private var description: String {
        switch tab {
        case .train:
            return "\(watches.trains.count) vonat a figyelőn\(watches.trains.count >= TransitWatchesStore.maxTrains ? " (több nem fér)" : "")"
        case .relation:
            if let relFrom { return "Honnan: \(relFrom.name) most válaszd ki, hová" }
            return relationsFull ? "A figyelő megtelt viszonylattal" : "Válaszd ki, honnan indulsz"
        case .stops:
            return favorites.stopIds.isEmpty ? "Még nincs figyelt megálló" : "\(favorites.stopIds.count) megálló a figyelőn"
        }
    }

    private var footerText: String {
        switch tab {
        case .relation: return "\(watches.relations.count) viszonylat a figyelőn"
        case .train: return "\(watches.trains.count) vonat a figyelőn"
        case .stops:
            return favorites.stopIds.isEmpty ? "Még nincs kiválasztott megálló" : "\(favorites.stopIds.count) megálló kiválasztva"
        }
    }

    private var relationsFull: Bool { watches.relations.count >= TransitWatchesStore.maxRelations }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.id) { item in
                let on = tab == item.id
                Button {
                    withAnimation(Theme.Motion.fastAnimation) {
                        tab = item.id
                        relFrom = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon).font(.system(size: 12, weight: .semibold))
                        Text(item.label).font(Theme.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.none)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(8)
    }

    // MARK: - Stops and relations

    private var stopSearch: some View {
        VStack(spacing: 10) {
            if tab == .relation, let relFrom {
                HStack(spacing: 8) {
                    Text(relFrom.name)
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    Text("hová?")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.mutedForeground)
                    Button {
                        self.relFrom = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kiinduló megálló törlése")
                }
                .padding(.leading, 12)
                .padding(.vertical, 2)
                .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.primary.opacity(0.30), lineWidth: 1)
                )
            }

            SearchField(
                text: $query,
                icon: "magnifyingglass",
                placeholder: tab == .relation ? (relFrom == nil ? "Honnan? (pl. Tiszai)" : "Hová? (pl. Füzesabony)") : "Név vagy megállókód",
                focused: $searchFocused
            )
            .accessibilityLabel("Megálló keresése")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var stopResults: some View {
        Group {
            if results.isEmpty {
                let needle = query.trimmingCharacters(in: .whitespaces)
                Text(needle.isEmpty ? "Megállók betöltése…" : "Nincs „\(needle)” nevű megálló a menetrendben.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, stop in
                            if index > 0 { HairlineDivider(opacity: 0.6) }
                            stopRow(stop)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func stopRow(_ stop: Stop) -> some View {
        let selected = tab == .stops ? favorites.contains(stop.id) : relFrom?.id == stop.id
        let disabled = tab == .relation
            ? relationsFull
            : !selected && favorites.stopIds.count >= FavoritesStore.maxCount
        let kind = StopKind.label(stopId: stop.id)
        return Button {
            pick(stop)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark" : TransitFeed.of(id: stop.id) == .rail ? "train.side.front.car" : "mappin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Theme.primaryForeground : Theme.mutedForeground)
                    .frame(width: 32, height: 32)
                    .background(selected ? Theme.primary : Theme.muted, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .mvkShadow(selected ? Theme.Shadow.sm : Theme.Shadow.none)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stop.name)
                        .font(Theme.sans(14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text(kind)
                        .font(kind == stop.id ? Theme.mono(11, weight: .regular) : Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !selected {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(selected ? Theme.primary.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowHighlightStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ stop: Stop) {
        guard tab == .relation else {
            favorites.toggle(stop.id)
            return
        }
        guard let from = relFrom else {
            relFrom = stop
            query = ""
            searchFocused = true
            return
        }
        if stop.id == from.id {
            relFrom = nil
            return
        }
        watches.addRelation(RelationWatch(from: from.id, to: stop.id))
        relFrom = nil
        query = ""
    }

    /// Stations first, regional stops outside the county last; 60 without a
    /// search term, 80 with one.
    private var results: [Stop] {
        let needle = query.trimmingCharacters(in: .whitespaces).normalizedForSearch
        let ranked = stops.enumerated().sorted { a, b in
            let ra = Self.regionRank(a.element), rb = Self.regionRank(b.element)
            if ra != rb { return ra < rb }
            let sa = StopKind.isStation(a.element.id), sb = StopKind.isStation(b.element.id)
            if sa != sb { return sa }
            return a.offset < b.offset
        }.map(\.element)
        guard !needle.isEmpty else { return Array(ranked.prefix(60)) }
        return Array(ranked.filter {
            $0.name.normalizedForSearch.contains(needle)
                || $0.code.normalizedForSearch.contains(needle)
                || $0.id.lowercased().contains(needle)
        }.prefix(80))
    }

    private static let regionPolygon: [(Double, Double)] = [
        (48.3, 20.08), (48.3, 20.36), (48.47, 20.48), (48.56, 20.75), (48.55, 21.1), (48.52, 21.25), (48.57, 21.45),
        (48.41, 21.7), (48.38, 22.12), (48.25, 21.93), (48.18, 21.7), (48.1, 21.42), (48.0, 21.1), (47.88, 21.09),
        (47.64, 20.88), (47.7, 20.6), (47.7, 20.35), (47.95, 20.47), (48.08, 20.45), (48.12, 20.2), (48.2, 20.06),
    ]

    private static func regionRank(_ stop: Stop) -> Int {
        guard TransitIds.isRegional(stop.id) else { return 0 }
        var inside = false
        var j = regionPolygon.count - 1
        for i in regionPolygon.indices {
            let (yi, xi) = regionPolygon[i], (yj, xj) = regionPolygon[j]
            if (yi > stop.lat) != (yj > stop.lat), stop.lon < (xj - xi) * (stop.lat - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside ? 0 : 1
    }

    // MARK: - Trains

    private var trainSearchKey: String { tab == .train ? trainQuery : "" }

    private func searchTrains() async {
        let number = trainQuery.trimmingCharacters(in: .whitespaces)
        guard tab == .train, (2...6).contains(number.count), number.allSatisfy(\.isNumber) else {
            trainHits = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            trainHits = try await APIClient.shared.searchTransit(number).trains
        } catch {
            guard !(error is CancellationError) else { return }
            trainHits = []
        }
    }

    private var trainTab: some View {
        let number = trainQuery.trimmingCharacters(in: .whitespaces)
        let full = watches.trains.count >= TransitWatchesStore.maxTrains
        var seen = Set<String>()
        let hits = (trainHits ?? []).filter { !watches.trains.contains($0.no) && seen.insert($0.no).inserted }
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SearchField(
                    text: Binding(get: { trainQuery }, set: { trainQuery = String($0.filter(\.isNumber).prefix(6)) }),
                    icon: "train.side.front.car",
                    placeholder: "Vonatszám, pl. 5139 vagy 582",
                    mono: true,
                    keyboard: .numberPad,
                    focused: $searchFocused
                )
                .accessibilityLabel("Vonatszám")
                Text("A vonat minden nap ugyanazzal a számmal jár: a kártya mindig a ma (vagy ha már elment, a holnap) közlekedőt mutatja.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            HairlineDivider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(watches.trains, id: \.self) { train in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.primaryForeground)
                                .frame(width: 32, height: 32)
                                .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .mvkShadow(Theme.Shadow.sm)
                            Text("\(HungarianText.withSuffix(train)) vonat")
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Levétel") { watches.toggleTrain(train) }
                                .buttonStyle(.mvk(.ghost, size: .small))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        HairlineDivider(opacity: 0.6)
                    }
                    ForEach(hits) { hit in
                        Button {
                            watches.toggleTrain(hit.no)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "train.side.front.car")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.name)
                                        .font(Theme.sans(14, weight: .medium))
                                        .foregroundStyle(Theme.foreground)
                                        .lineLimit(1)
                                    Text("\(hit.from) \(hit.departure) → \(hit.headsign)\(hit.today ? "" : " · holnap")")
                                        .font(Theme.sans(11))
                                        .foregroundStyle(Theme.mutedForeground)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowHighlightStyle())
                        .disabled(full)
                        .opacity(full ? 0.5 : 1)
                        HairlineDivider(opacity: 0.6)
                    }
                    if (2...6).contains(number.count), let trainHits, trainHits.isEmpty, !watches.trains.contains(number) {
                        Text("Ma és holnap nincs \(HungarianText.withSuffix(number)) vonat a megyét érintve.")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 32)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// The shadcn `Input` with a leading icon.
struct SearchField: View {
    @Binding var text: String
    let icon: String
    let placeholder: String
    var mono = false
    var keyboard: UIKeyboardType = .default
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.mutedForeground))
                .font(mono ? Theme.mono(16, weight: .regular) : Theme.sans(16))
                .foregroundStyle(Theme.foreground)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused(focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keresés törlése")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Theme.ring : Theme.input, lineWidth: 1)
        )
        .mvkShadow(Theme.Shadow.sm)
    }
}
