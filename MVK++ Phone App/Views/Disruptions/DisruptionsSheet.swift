//
//  DisruptionsSheet.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

@MainActor
private final class DisruptionsModel: ObservableObject {
    @Published var data: Disruptions?
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var nearKey = ""

    func start(near: [String]) {
        let key = near.joined(separator: ",")
        guard task == nil || key != nearKey else { return }
        nearKey = key
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load(key)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func load(_ near: String) async {
        do {
            let items = near.isEmpty ? [] : [URLQueryItem(name: "near", value: near)]
            var request = URLRequest(url: try APIClient.shared.url(path: "/engine/disruptions", queryItems: items))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (raw, response) = try await APIClient.shared.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                error = status == 503 ? "A mai menetrend még töltődik. Próbáld újra pár másodperc múlva." : "Hiba (\(status))"
                return
            }
            data = try JSONDecoder().decode(Disruptions.self, from: raw)
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "Nem sikerült betölteni" }
        }
    }
}

/// Mai zavarok (web `DisruptionsDialog`): every trip dropping out today in
/// one place — official cancellations, trips missing now and the ones not
/// seen earlier, with the replacement run. With a known position, the trips
/// stopping where the rider stands come first.
///
/// Opened from the Statisztika and the Menetrend. A pick hands the trip to
/// the Menetrend through `AppNavigation.openTimetableTrip`; pass `onPickTrip`
/// to handle it yourself.
struct DisruptionsSheet: View {
    var onPickTrip: ((DisruptionTrip) -> Void)?

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var location: LocationProvider
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DisruptionsModel()
    @State private var filter: DisruptionKind?
    @State private var route: String?

    private static let nearM = 300.0
    private static let nearMax = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView { content.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24) }
        }
        .presentationDetents([.large])
        .onAppear { model.start(near: nearStopIds) }
        .onDisappear { model.stop() }
        .onChange(of: nearStopIds) { _, ids in model.start(near: ids) }
    }

    /// Stops within 300 m, nearest first.
    private var nearStopIds: [String] {
        guard let position = location.position else { return [] }
        return store.stops
            .map { ($0.id, Geo.distanceKm(position.lat, position.lon, $0.lat, $0.lon)) }
            .filter { $0.1 * 1000 <= Self.nearM }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.nearMax)
            .map(\.0)
    }

    private func pick(_ trip: DisruptionTrip) {
        if let onPickTrip {
            onPickTrip(trip)
        } else {
            navigation.openTimetableTrip(TimetableTripRequest(routeId: trip.routeId, dir: trip.dir, tripId: trip.tripId))
        }
        dismiss()
    }

    // MARK: - Header

    private var total: Int {
        guard let data = model.data else { return 0 }
        return data.counts.cancelled + data.counts.missing + data.counts.unseen
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if (model.data?.counts.missing ?? 0) > 0 {
                            Circle().fill(Theme.late).frame(width: 8, height: 8).livePulse()
                        } else {
                            Circle().fill(Theme.ontime).frame(width: 8, height: 8)
                        }
                        Text("Mai zavarok").font(Theme.sans(16, weight: .bold))
                    }
                    Group {
                        if let data = model.data {
                            Text("\(total) kieső menet ma, \(data.counts.routes) vonalon. Koppints egy menetre, és megnyitom a menetrendben.\(data.stale ? " Az MVK törlési listája most nem frissül, a legutóbbi ismert állapot látszik." : "")")
                        } else {
                            Text("Betöltés…")
                        }
                    }
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 32)
            }

            if let data = model.data {
                HStack(spacing: 8) {
                    ForEach(DisruptionKind.allCases, id: \.self) { kind in countCard(kind, data: data) }
                }
                if !data.byHour.isEmpty { HourStrip(rows: data.byHour, nowS: data.nowS) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func countCard(_ kind: DisruptionKind, data: Disruptions) -> some View {
        let isOn = filter == kind
        return Button { filter = isOn ? nil : kind } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: kind.icon).font(.system(size: 10))
                    Text(kind.short.uppercased()).lineLimit(1)
                }
                .font(Theme.sans(10.5, weight: .semibold))
                .foregroundStyle(kind.tone)
                Text("\(data.count(kind))")
                    .font(Theme.mono(20, weight: .bold))
                    .foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Theme.primary.opacity(0.1) : Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(isOn ? Theme.primary : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Content

    private struct View3 {
        var here: [DisruptionTrip] = []
        var ahead: [DisruptionTrip] = []
        var past: [DisruptionTrip] = []
    }

    private var grouped: View3 {
        let trips = (model.data?.trips ?? []).filter { (filter == nil || $0.kind == filter) && (route == nil || $0.route == route) }
        let here = trips.filter { $0.near != nil }.sorted {
            if $0.upcoming != $1.upcoming { return $0.upcoming && !$1.upcoming }
            return ($0.near?.timeS ?? 0) < ($1.near?.timeS ?? 0)
        }
        return View3(
            here: here,
            ahead: trips.filter { $0.upcoming && $0.near == nil },
            past: trips.filter { !$0.upcoming && $0.near == nil }.reversed()
        )
    }

    /// The "may start late" list only in the full view (the kind filter is
    /// about trips dropping out).
    private var atRisk: [DisruptionTrip] {
        guard filter == nil else { return [] }
        return (model.data?.atRisk ?? []).filter { route == nil || $0.route == route }
    }

    private var routeChips: [(route: String, color: String, text: String, n: Int)] {
        var counts: [String: (route: String, color: String, text: String, n: Int)] = [:]
        for trip in model.data?.trips ?? [] {
            var entry = counts[trip.route] ?? (trip.route, trip.color, trip.text, 0)
            entry.n += 1
            counts[trip.route] = entry
        }
        return counts.values.sorted { $0.n != $1.n ? $0.n > $1.n : $0.route.localizedStandardCompare($1.route) == .orderedAscending }
    }

    @ViewBuilder
    private var content: some View {
        let view = grouped
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.error {
                DestructiveNote(text: error, icon: nil).padding(.bottom, 12)
            }

            let chips = routeChips
            if chips.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button { route = nil } label: {
                            Text("Minden vonal")
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(route == nil ? Theme.primaryForeground : Theme.mutedForeground)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(route == nil ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(route == nil ? Theme.primary : Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        ForEach(chips, id: \.route) { chip in
                            let isOn = route == chip.route
                            Button { route = isOn ? nil : chip.route } label: {
                                HStack(spacing: 4) {
                                    RouteTile(short: chip.route, colorHex: chip.color, textHex: chip.text, size: .small)
                                    Text("\(chip.n)").font(Theme.mono(11, weight: .bold)).foregroundStyle(Theme.mutedForeground).padding(.trailing, 4)
                                }
                                .padding(.horizontal, 4)
                                .frame(height: 28)
                                .background(isOn ? Theme.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(isOn ? Theme.primary : Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            nearSection(view.here).padding(.bottom, 16)

            if model.data != nil, view.ahead.isEmpty, view.past.isEmpty, view.here.isEmpty {
                Text(total > 0 ? "A szűrésnek nincs találata." : "Ma eddig nem esett ki menet.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }

            if !atRisk.isEmpty {
                group("Késve indulhat", atRisk.count) {
                    ForEach(Array(atRisk.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { divider }
                        riskRow(trip)
                    }
                }
            }
            if !view.ahead.isEmpty {
                group("Hátralévő", view.ahead.count) {
                    ForEach(Array(view.ahead.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { divider }
                        tripRow(trip, at: nil)
                    }
                }
            }
            if !view.past.isEmpty {
                group("Már esedékes volt", view.past.count, muted: true) {
                    ForEach(Array(view.past.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { divider }
                        tripRow(trip, at: nil)
                    }
                }
            }

            legend.padding(.top, 16)
        }
    }

    private var divider: some View { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1) }

    private func nearSection(_ here: [DisruptionTrip]) -> some View {
        let nearName = model.data?.nearStops.first?.name
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 12))
                Text((nearName.map { "Itt, a(z) \($0) megállónál" } ?? "A közeled").uppercased())
            }
            .font(Theme.sans(11, weight: .semibold))
            .foregroundStyle(Theme.early)
            if nearName != nil {
                if here.isEmpty {
                    Text("Ma egyetlen itt megálló menet sem esett ki. Ha nem jön a busz, az késés, nem kimaradás.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.mutedForeground)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(here.enumerated()), id: \.element.id) { index, trip in
                            if index > 0 { divider }
                            tripRow(trip, at: trip.near)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ha tudom, hol állsz, az ott megálló kieső menetek kerülnek előre.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.mutedForeground)
                    HereChip(stops: store.stops)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.early.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.early.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A közeled")
    }

    private func group<Rows: View>(_ title: String, _ n: Int, muted: Bool = false, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased()).font(Theme.sans(11, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(muted ? Theme.mutedForeground : Theme.foreground)
                Text("\(n)").font(Theme.mono(11, weight: .regular)).foregroundStyle(Theme.mutedForeground)
            }
            VStack(spacing: 0) { rows() }.opacity(muted ? 0.8 : 1)
        }
        .padding(.bottom, 12)
    }

    private func tripRow(_ trip: DisruptionTrip, at near: DisruptionTrip.Near?) -> some View {
        let kind = trip.kind ?? .missing
        return Button { pick(trip) } label: {
            HStack(alignment: .top, spacing: 10) {
                RouteTile(short: trip.route, colorHex: trip.color, textHex: trip.text)
                Text(near?.time ?? trip.depTime)
                    .font(Theme.mono(14, weight: .bold))
                    .strikethrough(kind == .cancelled, color: Theme.destructive.opacity(0.7))
                    .frame(width: 48, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.headsign.isEmpty ? trip.to : trip.headsign)
                        .font(Theme.sans(13, weight: .semibold))
                        .lineLimit(1)
                    FlowLayout(spacing: 8, lineSpacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: kind.icon).font(.system(size: 10))
                            Text(kind.short)
                        }
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(kind.tone)
                        .accessibilityHint(kind.hint)
                        Text(near.map { "itt \($0.time) · indul \(trip.from) \(trip.depTime)" } ?? "\(trip.from) → \(trip.to), \(trip.depTime)–\(trip.arrTime)")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                        if let planned = trip.plannedVehicle {
                            Text("\(TransitModes.displayVehicleId(planned)) vitte volna")
                                .font(Theme.mono(11, weight: .regular))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    if let replacement = trip.replacement {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                            Text("helyette \(replacement.depTime)").font(Theme.sans(11, weight: .semibold))
                            Text("(+\(replacement.gapMin) perc)").font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground)
                        }
                        .foregroundStyle(Theme.ontime)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.ontime.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.md - 4, style: .continuous))
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowHighlightStyle())
    }

    /// Not dropped yet, but its bus is late on the previous trip.
    private func riskRow(_ trip: DisruptionTrip) -> some View {
        Button {
            var picked = trip
            picked.kind = .missing
            picked.replacement = nil
            picked.plannedVehicle = nil
            pick(picked)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RouteTile(short: trip.route, colorHex: trip.color, textHex: trip.text)
                Text(trip.near?.time ?? trip.depTime)
                    .font(Theme.mono(14, weight: .bold))
                    .frame(width: 48, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.headsign.isEmpty ? trip.to : trip.headsign).font(Theme.sans(13, weight: .semibold)).lineLimit(1)
                    Text(trip.near.map { "itt \($0.time) · indul \(trip.from) \(trip.depTime)" } ?? "\(trip.from) → \(trip.to), \(trip.depTime)–\(trip.arrTime)")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                    if let risk = trip.risk { StartRiskText(risk: risk).padding(.top, 2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowHighlightStyle())
    }

    private var legend: some View {
        (Text("Törölve").bold().foregroundStyle(Theme.foreground) + Text(": az MVK hivatalos törlési listája. ")
         + Text("Kimarad").bold().foregroundStyle(Theme.foreground) + Text(": 15–90 perce esedékes, egyetlen busz sem kezdte el, és késő busz sem tart felé. ")
         + Text("Nem indult").bold().foregroundStyle(Theme.foreground) + Text(": korábban ma esedékes volt, nincs kihúzva, mégsem láttuk, miközben a vonal szomszédos meneteit igen. Nem számoljuk az „igény esetén” járatokat, a garázsból kiálló meneteket, és azt sem, amelyiket a busz adat nélkül vitte le (pontosan érkezésre feltűnt a végállomáson, a következő menetén)."))
            .font(Theme.sans(11))
            .foregroundStyle(Theme.mutedForeground)
            .lineSpacing(3)
    }
}

/// "Várhatóan kb. 6 perc késéssel indul: a busza (1644) még a 21-es vonalon
/// jár, 14:32 körül ér be." (web `StartRiskLine`)
struct StartRiskText: View {
    let risk: StartRisk

    var body: some View {
        let missed = risk.level == "likely-missed"
        let minutes = "\(max(1, Int((risk.expectedDelayS / 60).rounded()))) perc"
        let whereText = risk.prevRoute.map { "még a \(HungarianText.withSuffix($0)) vonalon jár" } ?? "még az előző menetén jár"
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest")
        formatter.dateFormat = "HH:mm"
        let end = formatter.string(from: Date(timeIntervalSince1970: risk.prevEndUnix))
        let lead = missed ? "Valószínűleg kimarad vagy nagyon késve indul" : "Várhatóan kb. \(minutes) késéssel indul"
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "hourglass").font(.system(size: 11)).padding(.top, 1)
            Text("\(lead): a busza (\(risk.predicted ? "~" : "")\(risk.vehicleId)) \(whereText), \(end) körül ér be.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.sans(11.5, weight: .semibold))
        .foregroundStyle(missed ? Theme.late : Theme.amber300)
    }
}

/// Trips dropping out per hour (start of day → now → end); the current hour
/// is outlined.
private struct HourStrip: View {
    let rows: [Disruptions.Hour]
    let nowS: Int

    var body: some View {
        let from = min(4, rows.map(\.h).min() ?? 4)
        let to = max(23, rows.map(\.h).max() ?? 23)
        let byHour = Dictionary(rows.map { ($0.h, $0) }, uniquingKeysWith: { first, _ in first })
        let maxCount = max(1, rows.map { $0.cancelled + $0.missing + $0.unseen }.max() ?? 1)
        let nowH = nowS / 3600
        VStack(spacing: 4) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(from...to, id: \.self) { hour in
                        let row = byHour[hour]
                        let n = row.map { $0.cancelled + $0.missing + $0.unseen } ?? 0
                        let height = max(0.08, Double(n) / Double(maxCount)) * proxy.size.height
                        VStack(spacing: 0) {
                            if let row, n > 0 {
                                ForEach([DisruptionKind.unseen, .missing, .cancelled], id: \.self) { kind in
                                    let value = kind == .cancelled ? row.cancelled : kind == .missing ? row.missing : row.unseen
                                    if value > 0 {
                                        kind.bar.frame(height: height * Double(value) / Double(n))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottom)
                        .background(Theme.muted.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(hour == nowH ? Theme.primary : .clear, lineWidth: 1))
                        .accessibilityLabel("\(String(format: "%02d", hour % 24)) óra: \(n) kieső menet")
                    }
                }
            }
            .frame(height: 40)
            HStack {
                Text(String(format: "%02d", from % 24))
                Spacer()
                Text(String(format: "%02d", ((from + to) / 2) % 24))
                Spacer()
                Text(String(format: "%02d", to % 24))
            }
            .font(Theme.mono(9.5, weight: .regular))
            .foregroundStyle(Theme.mutedForeground)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kieső menetek óránként")
    }
}
