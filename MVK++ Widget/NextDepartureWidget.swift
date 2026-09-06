//
//  NextDepartureWidget.swift
//  MVK++ Widget
//

import SwiftUI
import WidgetKit

struct NextDepartureEntry: TimelineEntry {
    let date: Date
    let stopName: String?
    let arrival: ArrivalItem?
    /// Locally-decremented ETA for the minutes between real network
    /// refreshes, so the widget visibly counts down instead of sitting on
    /// stale data until WidgetKit gets around to calling the provider again.
    let etaOverride: Int?
    let message: String?
}

struct NextDepartureProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDepartureEntry {
        NextDepartureEntry(date: Date(), stopName: "Megálló", arrival: nil, etaOverride: nil, message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDepartureEntry) -> Void) {
        if context.isPreview {
            completion(NextDepartureEntry(date: Date(), stopName: "Megálló", arrival: nil, etaOverride: nil, message: nil))
            return
        }
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDepartureEntry>) -> Void) {
        Task {
            let base = await fetchEntry()
            let now = Date()
            var timelineEntries: [NextDepartureEntry] = []

            if let arrival = base.arrival {
                let steps = min(arrival.etaMin, 5)
                for minute in 0...steps {
                    let entryDate = Calendar.current.date(byAdding: .minute, value: minute, to: now) ?? now
                    timelineEntries.append(
                        NextDepartureEntry(
                            date: entryDate,
                            stopName: base.stopName,
                            arrival: arrival,
                            etaOverride: max(0, arrival.etaMin - minute),
                            message: nil
                        )
                    )
                }
            } else {
                timelineEntries = [base]
            }

            // A real re-fetch every few minutes — long enough to respect the
            // system's refresh budget, short enough that vehicle/delay data
            // doesn't go stale. The app itself also nudges a reload every
            // ~20s via WidgetCenter while it's open and actively polling.
            let nextRefresh = now.addingTimeInterval(3 * 60)
            completion(Timeline(entries: timelineEntries, policy: .after(nextRefresh)))
        }
    }

    private func fetchEntry() async -> NextDepartureEntry {
        let suite = UserDefaults(suiteName: FavoritesStore.appGroupID)
        guard let stopId = suite?.string(forKey: FavoritesStore.widgetStopKey), !stopId.isEmpty else {
            return NextDepartureEntry(date: Date(), stopName: nil, arrival: nil, etaOverride: nil, message: "Válassz widget megállót a telefonon")
        }
        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: 1)
            guard let arrival = response.arrivals.first else {
                return NextDepartureEntry(date: Date(), stopName: response.stop.name ?? stopId, arrival: nil, etaOverride: nil, message: "Nincs induló járat")
            }
            return NextDepartureEntry(date: Date(), stopName: response.stop.name ?? stopId, arrival: arrival, etaOverride: arrival.etaMin, message: nil)
        } catch {
            return NextDepartureEntry(date: Date(), stopName: stopId, arrival: nil, etaOverride: nil, message: "Nincs kapcsolat")
        }
    }
}

struct NextDepartureWidgetView: View {
    let entry: NextDepartureEntry

    private var routeLengthScale: CGFloat {
        guard let route = entry.arrival?.route else { return 1.0 }
        switch route.count {
        case 0...1: return 1.0
        case 2: return 0.88
        case 3: return 0.76
        default: return 0.66
        }
    }

    var body: some View {
        if let arrival = entry.arrival {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(arrival.route)
                        .font(.system(size: 12 * routeLengthScale, design: .rounded))
                        .fontWeight(.heavy)
                        .padding(.horizontal, 5 * routeLengthScale)
                        .padding(.vertical, 1)
                        .background(Theme.hex(arrival.color.isEmpty ? "888888" : arrival.color))
                        .foregroundStyle(Theme.hex(arrival.text.isEmpty ? "FFFFFF" : arrival.text))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    if let stopName = entry.stopName {
                        Text(stopName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    if let vehicleId = arrival.vehicle?.id {
                        Text("#\(vehicleId)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    delayText(arrival.delaySec)
                    Spacer(minLength: 0)
                    let etaMin = entry.etaOverride ?? arrival.etaMin
                    Text(etaMin <= 0 ? "MOST" : "\(etaMin) perc")
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.bold)
                }
            }
        } else {
            Text(entry.message ?? "Nincs adat")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func delayText(_ delaySec: Int?) -> some View {
        Group {
            if let delaySec {
                if abs(delaySec) < 45 {
                    Text("0").foregroundStyle(Theme.ontime)
                } else {
                    let minutes = Int((Double(abs(delaySec)) / 60).rounded())
                    Text(delaySec > 0 ? "+\(minutes)" : "-\(minutes)")
                        .foregroundStyle(delaySec > 0 ? Theme.late : Theme.early)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .fontWeight(.semibold)
    }
}

struct NextDepartureWidget: Widget {
    let kind = "NextDepartureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDepartureProvider()) { entry in
            NextDepartureWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.card
                }
        }
        .configurationDisplayName("MVK++")
        .description("A kiválasztott megálló következő indulása.")
        .supportedFamilies([.accessoryRectangular])
    }
}
