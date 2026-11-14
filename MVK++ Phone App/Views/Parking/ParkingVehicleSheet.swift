//
//  ParkingVehicleSheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// Where one vehicle is in the snapshot.
enum ParkingLocated {
    case terminus(place: String, v: ParkingVehicle)
    case depot(place: String, v: ParkingVehicle)
    case nosignal(place: String?, v: ParkingVehicle)
    case service(ParkingServiceVehicle)

    static func locate(_ snap: ParkingSnapshot, id: String) -> ParkingLocated? {
        for t in snap.terminals + (snap.regional?.terminals ?? []) {
            if let v = t.vehicles.first(where: { $0.id == id }) { return .terminus(place: t.name, v: v) }
        }
        for d in snap.depots {
            if let v = d.vehicles.first(where: { $0.id == id }) { return .depot(place: d.name, v: v) }
        }
        if let n = snap.nosignal.first(where: { $0.id == id }) { return .nosignal(place: n.place, v: n) }
        if let s = snap.service.first(where: { $0.id == id }) { return .service(s) }
        return nil
    }

    var id: String {
        switch self {
        case .terminus(_, let v), .depot(_, let v), .nosignal(_, let v): return v.id
        case .service(let s): return s.id
        }
    }

    var kind: ParkingFleetKind {
        switch self {
        case .terminus(_, let v), .depot(_, let v), .nosignal(_, let v): return v.kind
        case .service(let s): return s.kind
        }
    }

    var place: String? {
        switch self {
        case .terminus(let p, _), .depot(let p, _): return p
        case .nosignal(let p, _): return p
        case .service: return nil
        }
    }

    var label: String {
        switch self {
        case .terminus: return "Végállomáson parkol"
        case .depot: return "Kocsiszínben"
        case .nosignal: return "Jel nélkül"
        case .service: return "Bevetésen"
        }
    }

    var tone: Color {
        switch self {
        case .terminus: return Theme.park
        case .depot: return Theme.depot
        case .nosignal: return Theme.nosignal
        case .service: return Theme.primary
        }
    }

    /// The map makes sense for a running vehicle or one with a live fix.
    var canShowOnMap: Bool {
        switch self {
        case .service: return true
        case .terminus(_, let v), .depot(_, let v), .nosignal(_, let v): return v.online
        }
    }
}

/// One vehicle's card: where it is, how it got there, its last two weeks.
struct ParkingVehicleSheet: View {
    let snap: ParkingSnapshot
    let id: String
    let now: Double
    let lookup: ParkingRouteLookup
    let onFocusVehicle: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let hit = ParkingLocated.locate(snap, id: id) {
                let history = snap.fleet[id]
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(TransitModes.displayVehicleId(hit.id))
                                .font(Theme.mono(28, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(hit.kind == .tram ? "villamos" : "busz")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        HStack(spacing: 8) {
                            Text(hit.label)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(hit.tone)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(hit.tone.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            if let place = hit.place {
                                Text(place).font(.system(size: 13))
                            }
                        }
                    }
                    .padding(.trailing, 24)

                    whereBox(hit, history: history)
                    if let history { historyBox(history) }

                    if hit.canShowOnMap {
                        Button {
                            onFocusVehicle(hit.id)
                            dismiss()
                        } label: {
                            Label("Megnézem a térképen", systemImage: "mappin.and.ellipse")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .foregroundStyle(Theme.primaryForeground)
                    }
                }
                .padding(20)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).foregroundStyle(Theme.mutedForeground).fixedSize()
            Spacer(minLength: 0)
            content().multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func whereBox(_ hit: ParkingLocated, history: ParkingFleetHistory?) -> some View {
        let box = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 0) {
            switch hit {
            case .service(let v):
                row("Most") {
                    if v.deadhead {
                        Text("menet nélkül úton (átállás)")
                    } else {
                        HStack(spacing: 6) {
                            ParkingRouteChip(route: v.route, lookup: lookup)
                            Text(v.headsign ?? "")
                        }
                    }
                }
                if let delay = v.delayS {
                    Divider().overlay(Theme.border.opacity(0.7))
                    row("Késés") {
                        Text(delay >= 60 ? "+\(Int((delay / 60).rounded())) perc" : delay <= -60 ? "\(ParkingFormat.jsRound(delay / 60)) perc (siet)" : "pontos")
                    }
                }
            case .terminus(_, let v), .depot(_, let v), .nosignal(_, let v):
                let rows = parkedRows(hit, v: v, history: history)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider().overlay(Theme.border.opacity(0.7)) }
                    item
                }
            }
        }
        .padding(.horizontal, 12)
        .overlay(box.strokeBorder(Theme.border, lineWidth: 1))
    }

    private func parkedRows(_ hit: ParkingLocated, v: ParkingVehicle, history: ParkingFleetHistory?) -> [AnyView] {
        var out: [AnyView] = []
        if case .depot = hit, let reason = v.reason {
            out.append(AnyView(row("Hogyan került ide") {
                Text("\(ParkingFormat.reasonLabel(reason).lowercased()) \(ParkingFormat.depotLine(v, history: history, serviceDate: snap.serviceDate))")
            }))
        }
        if let since = v.since {
            let isSilent: Bool = { if case .nosignal = hit { return true } else { return false } }()
            out.append(AnyView(row(isSilent ? "Utolsó jel" : "Itt áll") {
                Text("\(ParkingFormat.clock(since)) óta · \(ParkingFormat.duration(max(0, now - since)))")
            }))
        }
        out.append(AnyView(row("GPS") {
            HStack(spacing: 6) {
                ParkingSignalDot(online: v.online)
                Text(v.online ? "élő" : v.lastSeen.map { "utoljára \(ParkingFormat.clock($0))" } ?? "ma nem jelentkezett")
            }
        }))
        if let lastRoute = v.lastRoute {
            out.append(AnyView(row("Utolsó menet") {
                HStack(spacing: 6) {
                    ParkingRouteChip(route: lastRoute, lookup: lookup)
                    Text(v.lastHeadsign ?? "")
                }
            }))
        }
        if let tip = v.next {
            out.append(AnyView(row(tip.certain ? "Következő menete" : "Várható következő") {
                VStack(alignment: .trailing, spacing: 4) {
                    ParkingTipChip(tip: tip, lookup: lookup, midnight: snap.midnight, now: now)
                        .fixedSize()
                    Text(tip.certain ? "az MVK már kiadta neki" : "előrejelzés, \(ParkingFormat.pct(tip.confidence)) bizonyossággal")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }))
        }
        return out
    }

    private func historyBox(_ h: ParkingFleetHistory) -> some View {
        let since = h.lastDate.map { ParkingFormat.daysBetween($0, snap.serviceDate) }
        let box = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text("AZ UTOLSÓ 14 NAP")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.mutedForeground)
            ParkingPresenceStrip(recent: h.recent, tall: true)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(h.streakDays > 0
                     ? "\(h.streakDays) napja egyfolytában kint van (tegnapig)"
                     : since.map { "\($0 - 1) napja nem volt kint" } ?? "régóta nem volt kint")
                if let share = h.outShare {
                    (Text("Az ilyen napok ")
                     + Text(ParkingFormat.pct(share)).font(Theme.mono(12.5, weight: .semibold))
                     + Text("-án kint van")
                     + (h.usualOutS.map { Text(", általában ") + Text(ParkingFormat.hm(daySec: $0)).font(Theme.mono(12.5, weight: .semibold)) + Text("-kor áll ki") } ?? Text("")))
                }
                if !h.topRoutes.isEmpty {
                    HStack(spacing: 6) {
                        Text("Legtöbbet:")
                        ForEach(h.topRoutes, id: \.self) { ParkingRouteChip(route: $0, lookup: lookup) }
                    }
                }
            }
            .font(.system(size: 12.5))
            .padding(.top, 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.3), in: box)
        .overlay(box.strokeBorder(Theme.border, lineWidth: 1))
    }
}
