//
//  PlannerInsights.swift
//  MVK++ Phone App
//

import Foundation

/// Today or later: when the rider gets in, expected and in a bad case.
struct TripForecast {
    let arrDelayS: Double?
    /// Expected arrival at the destination (unix), final walk included.
    let expectedArrival: Double?
    /// Bad case (85th percentile), when it is meaningfully later than expected.
    let worstArrival: Double?
    let hasLive: Bool
    let hasData: Bool

    init(_ trip: JourneyTrip) {
        let rides = PlannerFormat.transitLegs(trip)
        let last = rides.last
        let p = last?.prediction
        let walk = PlannerFormat.trailingWalkSec(trip)
        let arr = p?.arrDelayS
        let p85 = p?.arrDelayP85S
        let schedArr = last?.schedArr
        arrDelayS = arr
        expectedArrival = schedArr.flatMap { s in arr.map { s + $0 + walk } }
        if let schedArr, let p85, p85 - (arr ?? 0) >= PlannerFormat.onTimeSec {
            worstArrival = schedArr + p85 + walk
        } else {
            worstArrival = nil
        }
        hasLive = rides.contains { $0.prediction?.source == "live" }
        hasData = rides.contains { $0.prediction.map { $0.source != "none" } ?? false }
    }
}

enum PlannerForecast {
    /// The worst transfer — the one the card header calls out.
    static func worstTransfer(_ trip: JourneyTrip) -> (check: JourneyTransferCheck, index: Int)? {
        var best: (check: JourneyTransferCheck, index: Int)?
        for (index, check) in trip.transferChecks.enumerated() {
            guard let current = best else {
                best = (check, index)
                continue
            }
            let worse = check.risk.order > current.check.risk.order
                || (check.risk.order == current.check.risk.order && (check.chance ?? 1) < (current.check.chance ?? 1))
            if worse { best = (check, index) }
        }
        return best
    }

    /// „élő adat” / „959 korábbi mérés alapján” / „nincs adat”
    static func basisLabel(_ p: JourneyPrediction?) -> String {
        guard let p, p.source != "none" else { return "nincs adat, menetrendi idő" }
        if p.source == "live" { return "élő adat" }
        return "\(PlannerFormat.grouped(p.samples)) korábbi mérés alapján"
    }
}

/// A past journey summed up: what the measurements show against the
/// timetable. The card header and the copyable proof both read this, so the
/// two never say different things.
struct PastOutcome {
    /// Measured delay alighting from the last vehicle (s).
    let arrivalDelayS: Double?
    /// When the rider actually got there (unix), final walk included.
    let actualArrival: Double?
    let arrivalEstimated: Bool
    /// At least one run has no measurement.
    let partial: Bool
    let rideCount: Int
    let untrackedRoutes: [String]
    /// The first transfer the measured times say would have been missed.
    let missedTransfer: JourneyTransferCheck?

    init(_ trip: JourneyTrip) {
        let rides = PlannerFormat.transitLegs(trip)
        let last = rides.last?.actual
        arrivalDelayS = trip.actualOutcome?.arrivedDelayS ?? last?.arrDelayS
        actualArrival = last?.arrTs.map { $0 + PlannerFormat.trailingWalkSec(trip) }
        untrackedRoutes = rides.filter { $0.actual?.tracked != true }.map { $0.routeShortName ?? "" }
        missedTransfer = trip.transferChecks.enumerated().first { index, check in
            check.risk == .risky && PastOutcome.transferMeasured(trip, index: index)
        }?.element
        arrivalEstimated = last?.estimated ?? false
        partial = !untrackedRoutes.isEmpty
        rideCount = rides.count
    }

    /// Whether both sides of the transfer were measured (otherwise the margin is the timetable's).
    static func transferMeasured(_ trip: JourneyTrip, index: Int) -> Bool {
        let rides = PlannerFormat.transitLegs(trip)
        let before = rides.indices.contains(index) ? rides[index].actual : nil
        let after = rides.indices.contains(index + 1) ? rides[index + 1].actual : nil
        return before?.arrDelayS != nil && after?.depDelayS != nil
    }

    /// „4 p 41 mp késéssel érkeztél volna”
    var headline: String {
        if let missedTransfer { return "Lekésted volna az átszállást (\(missedTransfer.at))" }
        if untrackedRoutes.count == rideCount { return "Erről az útról nincs mérés" }
        guard let d = arrivalDelayS else { return "Az érkezésről nincs mérés" }
        if abs(d) < 30 { return "Pontosan érkeztél volna" }
        return d > 0
            ? "\(PlannerFormat.spanExact(d)) késéssel érkeztél volna"
            : "\(PlannerFormat.spanExact(d))-cel korábban érkeztél volna"
    }
}

enum PlannerProof {
    static let appUrl = "https://mvk.futozs.hu"

    private static func arrivalVerdict(_ delayS: Double) -> String {
        if abs(delayS) < 30 { return "pontosan (\(PlannerFormat.delayExact(delayS)))" }
        return delayS > 0 ? "\(PlannerFormat.spanExact(delayS)) késés" : "\(PlannerFormat.spanExact(delayS))-cel korábban"
    }

    private static func legLines(_ leg: JourneyLeg, n: Int) -> [String] {
        let head = "\(n). \(PlannerFormat.legTileText(leg)) \(leg.trainName ?? PlannerFormat.modeNoun(leg.mode))\(leg.headsign.map { " (\($0))" } ?? "")"
        var lines = [head]
        let schedDep = PlannerFormat.hm(leg.schedDep ?? PlannerFormat.unix(leg.start))
        let schedArr = PlannerFormat.hm(leg.schedArr ?? PlannerFormat.unix(leg.end))
        guard let a = leg.actual, a.tracked else {
            lines.append("   Felszállás: \(leg.fromName), menetrend szerint \(schedDep)")
            lines.append("   Leszállás: \(leg.toName), menetrend szerint \(schedArr)")
            lines.append("   Erről a menetről nincs mérés.")
            return lines
        }
        let dep: String
        if let ts = a.depTs, let d = a.depDelayS {
            dep = "valójában \(PlannerFormat.hms(ts)) (\(PlannerFormat.delayExact(d)))"
        } else {
            dep = "az indulásról nincs mérés"
        }
        let arr: String
        if let ts = a.arrTs, let d = a.arrDelayS {
            arr = "valójában \(PlannerFormat.hms(ts)) (\(PlannerFormat.delayExact(d)))\(a.estimated ? ", becsült" : "")"
        } else {
            arr = "az érkezésről nincs mérés"
        }
        lines.append("   Felszállás: \(leg.fromName), menetrend szerint \(schedDep), \(dep)")
        lines.append("   Leszállás: \(leg.toName), menetrend szerint \(schedArr), \(arr)")
        if let vehicleId = a.vehicleId { lines.append("   Jármű: \(TransitIds.displayVehicleId(vehicleId))") }
        return lines
    }

    /// Plain-text proof for the clipboard (for a teacher or an employer).
    static func text(plan: JourneyPlanResponse, trip: JourneyTrip) -> String {
        let o = PastOutcome(trip)
        var out = [
            "Utazás a mért adatok alapján  Miskolc, MVK",
            "Dátum: \(PlannerFormat.longDate(PlannerFormat.localIsoDate(trip.start)))",
            "Útvonal: \(plan.from.name) → \(plan.to.name)",
            "Menetrend szerint: \(PlannerFormat.hm(trip.start)) → \(PlannerFormat.hm(trip.end))",
            "",
        ]
        var n = 0
        var ride = 0
        for leg in trip.legs {
            n += 1
            if leg.isTransit {
                out.append(contentsOf: legLines(leg, n: n))
                if trip.transferChecks.indices.contains(ride) {
                    let check = trip.transferChecks[ride]
                    let measured = PastOutcome.transferMeasured(trip, index: ride)
                    let margin = PlannerFormat.marginText(check.marginSec)
                    let verdict = !measured
                        ? "menetrend szerint \(margin) tartalék (nincs mérés)"
                        : check.marginSec < 0
                            ? "a mérés szerint \(margin)-cel lekésted volna"
                            : "a mérés szerint \(margin) tartalék"
                    out.append("   Átszállás itt: \(check.at)  \(verdict)")
                }
                ride += 1
            } else {
                out.append("\(n). Gyalog \(PlannerFormat.minutes(leg.durationSec)) (\(Int(leg.distanceMeter.rounded())) m) → \(leg.toName)")
            }
        }
        out.append("")
        if let actual = o.actualArrival, let delay = o.arrivalDelayS {
            out.append("Érkezés: menetrend szerint \(PlannerFormat.hm(trip.end)), valójában \(PlannerFormat.hms(actual))\(o.arrivalEstimated ? " (becsült)" : "")  \(arrivalVerdict(delay)).")
        } else {
            out.append("Érkezés: menetrend szerint \(PlannerFormat.hm(trip.end)); az érkezésről nincs mérés.")
        }
        if let missed = o.missedTransfer {
            out.append("Figyelem: a mérés szerint az átszállás (\(missed.at)) nem jött volna össze.")
        }
        if o.partial {
            out.append("Megjegyzés: a(z) \(o.untrackedRoutes.joined(separator: ", ")) menetéről nincs mérés.")
        }
        out.append(contentsOf: [
            "",
            "Forrás: MVK++ (\(appUrl))  az MVK járműveinek mért helyadataiból; menetrend: \(plan.schedule.feedVersion).",
        ])
        return out.joined(separator: "\n")
    }
}
