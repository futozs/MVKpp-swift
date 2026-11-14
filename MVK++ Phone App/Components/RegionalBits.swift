//
//  RegionalBits.swift
//  MVK++ Phone App
//

import SwiftUI

/// The Volán and rail extras on departure boards — the web app's
/// `transit/RegionalBits`: platform or bay (which can change live), MÁV's
/// official notices, and the tile text (a train's category and number).
extension ArrivalItem {
    /// „IC 582” for a train, the route number otherwise.
    var tileText: String {
        if mode == .rail, let trainNo, !trainNo.isEmpty { return "\(route) \(trainNo)" }
        return route
    }

    /// „TOKAJ → Budapest-Nyugati” for a named train, the headsign otherwise.
    var title: String {
        if let trainName, !trainName.isEmpty { return "\(trainName) → \(headsign)" }
        return headsign
    }

    /// The vehicle tag in a row: a Volán coach's plate; none for a train.
    var vehicleLabel: String? {
        guard let vehicle, mode != .rail else { return nil }
        return TransitIds.displayVehicleId(vehicle.id, plate: vehicle.plate)
    }

    /// Only a run the feed can locate is worth opening on the map; a
    /// cancelled one only if a vehicle is somehow on it after all.
    var isFocusable: Bool {
        live && !tripId.isEmpty && (cancelled != true || vehicle != nil)
    }
}

enum StopKind {
    /// What the header says under a stop's name: the MVK stop id stays as is.
    static func label(stopId: String, isStation: Bool = false) -> String {
        switch TransitFeed.of(id: stopId) {
        case .rail: return "Vasútállomás"
        case .coach: return isStation ? "Autóbusz-állomás" : "Volán-megálló"
        case .mvk: return stopId
        }
    }

    static func isStation(_ stopId: String) -> Bool {
        TransitFeed.of(id: stopId) == .rail
    }
}

/// Platform (rail) or bay (coach station). A change is highlighted; one not
/// announced yet — the platform earlier days used — gets a dashed frame and „~”.
struct PlatformBadge: View {
    let platform: String?
    var changed = false
    var predicted = false
    var mode: TransitMode?
    var compact = false

    var body: some View {
        if let platform, !platform.isEmpty {
            let rail = mode == .rail
            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            HStack(spacing: 4) {
                if rail {
                    Image(systemName: "road.lanes")
                        .font(.system(size: 8, weight: .bold))
                }
                Text("\(predicted ? "~" : "")\(platform)")
                    .font(Theme.mono(10.5, weight: .bold))
                if !compact {
                    Text(rail ? "vg." : "k.áll.")
                        .font(Theme.sans(10, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .foregroundStyle(predicted ? Theme.mutedForeground : changed ? Theme.late : Theme.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(predicted ? Color.clear : changed ? Theme.late.opacity(0.12) : Theme.muted, in: shape)
            .overlay {
                if predicted {
                    shape.strokeBorder(Theme.mutedForeground.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    shape.strokeBorder(changed ? Theme.late.opacity(0.5) : Theme.border, lineWidth: 1)
                }
            }
            .fixedSize()
            .accessibilityLabel(accessibilityText(platform, rail: rail))
        }
    }

    private func accessibilityText(_ platform: String, rail: Bool) -> String {
        let label = rail ? "vágány" : "kocsiállás"
        if predicted { return "Várhatóan a \(platform). \(label) még nincs kiadva, a korábbi napok alapján" }
        if changed { return "A \(label) változott: most \(platform)." }
        return "\(platform). \(label)"
    }
}

/// MÁV's official notices for a run (e.g. „Pálya állapota miatti késés”).
struct NoticeList: View {
    let notices: [String]?
    var compact = false

    var body: some View {
        if let notices, !notices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(compact ? Array(notices.prefix(1)) : notices, id: \.self) { notice in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.late)
                            .padding(.top, 1)
                        Text(notice)
                            .font(Theme.sans(compact ? 10.5 : 11.5))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(compact ? 1 : nil)
                            .fixedSize(horizontal: false, vertical: !compact)
                    }
                }
            }
        }
    }
}

/// „közös megálló”: the MVK post and the Volán stop beside it share one board.
struct SharedStopTag: View {
    let merged: [String]?

    var body: some View {
        if let merged, merged.count >= 2 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("közös megálló")
                    .font(Theme.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.foreground.opacity(0.8))
            }
            .accessibilityHint("Az MVK- és a Volán-megálló egy helyen áll: a táblán mindkettő járatai (a Beállításokban állítható).")
        }
    }
}

/// „~123” or „123”: the vehicle expected to run a departure before it shows
/// up live. A loop vehicle is not a guess, so it has no tilde.
struct PredictedVehicleTag: View {
    let predicted: PredictedVehicle
    /// The sentence under the next departure („Várhatóan a 1673 jön”) says
    /// it is a guess in words, so its tag drops the tilde (web `StopCard`).
    var inSentence = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let id = TransitIds.displayVehicleId(predicted.id)
        if PredictedVehicleTag.isLoop(predicted) {
            Text(id)
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.primary.opacity(0.12), in: shape)
                .accessibilityHint(PredictedVehicleTag.title(predicted))
        } else {
            Text(inSentence ? id : "~\(id)")
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.primary.opacity(inSentence ? 1 : 0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(shape.strokeBorder(Theme.primary.opacity(inSentence ? 0.5 : 0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .accessibilityHint(PredictedVehicleTag.title(predicted))
        }
    }

    static func isLoop(_ predicted: PredictedVehicle) -> Bool { predicted.method == "loop" }

    static func title(_ predicted: PredictedVehicle) -> String {
        if predicted.method == "matched" { return "Már úton van: a GPS-nyomvonal alapján ez a busz viszi" }
        if isLoop(predicted) { return "Ez a busz most a végállomás felé jár, és ugyanonnan fordul vissza, nem tipp" }
        return "Előrejelzés a korábbi fordák alapján, \(Int((predicted.confidence * 100).rounded()))% bizonyossággal"
    }
}

/// The small „ID” chip next to a departure's time.
struct VehicleIdChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(11, weight: .bold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .fixedSize()
    }
}

/// „törölve” / „Törölve”: MVK cancelled the run.
struct CancelledTag: View {
    var prominent = false

    var body: some View {
        if prominent {
            Text("Törölve")
                .font(Theme.sans(10, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Theme.destructive)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.destructive.opacity(0.5), lineWidth: 1)
                )
        } else {
            Text("törölve")
                .font(Theme.sans(10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.destructive)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.destructive.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .fixedSize()
        }
    }
}
