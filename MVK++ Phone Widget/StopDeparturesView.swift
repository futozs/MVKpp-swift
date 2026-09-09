//
//  StopDeparturesView.swift
//  MVK++ Phone Widget
//

import SwiftUI
import WidgetKit

/// The home screen widget.
///
/// Laid out as a departure board rather than a card grid: the stop sign plate
/// on top, then one line per bus, with the countdown set as the largest thing
/// on the widget because it is the only number anyone reads while walking.
struct StopDeparturesView: View {

    let entry: StopDeparturesEntry
    @Environment(\.widgetFamily) private var family

    /// Two on the medium family. Three fit only on paper — the third row
    /// ends up clipped against the widget's bottom edge, and a departure you
    /// cannot fully read is worse than one that isn't there.
    private var rowLimit: Int {
        switch family {
        case .systemLarge: return 4
        case .systemMedium: return 2
        default: return 1
        }
    }

    /// Clock time of the departure, e.g. "14:12". Built once per render
    /// rather than per row.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                accessory
            } else {
                board
            }
        }
        .widgetURL(stopURL)
    }

    // MARK: - Home screen

    private var board: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(Theme.border)
                .padding(.vertical, family == .systemLarge ? 10 : 7)

            if entry.departures.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entry.departures.prefix(rowLimit).enumerated()), id: \.element.id) { index, departure in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.border.opacity(0.55))
                                .frame(height: 1)
                        }
                        row(departure)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The stop sign, restated: green-edged plate with the number riders
    /// actually look for, then the name. Tapping it opens that stop in the
    /// app — the header is the button.
    private var header: some View {
        Link(destination: stopURL) {
            HStack(spacing: 8) {
                if !entry.stopCode.isEmpty {
                    Text(entry.stopCode)
                        .font(Theme.mono(13, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.primary.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Theme.primary.opacity(0.55), lineWidth: 1)
                                )
                        )
                }

                Text(entry.stopName)
                    .font(.system(size: family == .systemLarge ? 17 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                // Nothing reached the gateway, so every number below is a
                // scheduled one. Said with a glyph rather than a word: the
                // header has no room, and the rows already say "menetrend".
                if entry.isOffline {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.offline)
                        .accessibilityLabel("Offline — menetrend szerinti idők")
                }

                // The tap opens the Megállófigyelő on this stop, so the
                // header wears that screen's own glyph rather than a bare
                // chevron.
                HStack(spacing: 2) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ departure: DepartureSnapshot) -> some View {
        Link(destination: tripURL(departure)) {
            HStack(spacing: 9) {
                routeBadge(departure)

                VStack(alignment: .leading, spacing: 1) {
                    Text(departure.headsign)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 5) {
                        if entry.showsVehicle, let vehicleId = departure.vehicleId {
                            Text(vehicleId)
                                .font(Theme.mono(10, weight: .medium))
                                .foregroundStyle(Theme.mutedForeground)
                            separator
                        }
                        // "3 perc" answers when to leave; "14:12" answers
                        // whether that fits the rest of the morning. Both are
                        // worth the line.
                        Text(Self.clock.string(from: departure.due))
                            .font(Theme.mono(10, weight: .semibold))
                            .foregroundStyle(Theme.foreground.opacity(0.85))
                        separator
                        Text(DelayFormat.label(departure.delaySec))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DelayFormat.tone(departure.delaySec))
                        if !departure.isLive {
                            Text("menetrend")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.mutedForeground.opacity(0.75))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 4)

                countdown(departure)
            }
            .padding(.vertical, family == .systemLarge ? 9 : 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.mutedForeground.opacity(0.5))
    }

    private func routeBadge(_ departure: DepartureSnapshot) -> some View {
        // Long route labels ("21A", "101B") would otherwise blow the badge
        // out and shove the headsign off the row.
        let scale: CGFloat = departure.route.count > 3 ? 0.72 : (departure.route.count > 2 ? 0.85 : 1)
        return Text(departure.route)
            .font(.system(size: 14 * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.hex(departure.textColor))
            .frame(minWidth: 30)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.hex(departure.color))
            )
    }

    private func countdown(_ departure: DepartureSnapshot) -> some View {
        let minutes = departure.minutes(at: entry.date)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            if minutes <= 0 {
                Text("MOST")
                    .font(Theme.mono(13, weight: .heavy))
                    .foregroundStyle(Theme.primary)
            } else {
                let parts = Countdown.parts(minutes: minutes)
                Text(parts.value)
                    .font(Theme.mono(family == .systemLarge ? 24 : 21, weight: .heavy))
                    .foregroundStyle(Theme.foreground)
                Text(parts.unit == "perc" ? "p" : parts.unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.stopId == nil ? "hand.tap" : "moon.zzz")
                .font(.system(size: 18))
                .foregroundStyle(Theme.primary)
            Text(entry.message ?? "Nincs adat")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Lock screen

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if !entry.stopCode.isEmpty {
                    Text(entry.stopCode).font(Theme.mono(11, weight: .heavy))
                }
                Text(entry.stopName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if entry.isOffline {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityLabel("Offline")
                }
            }
            if let departure = entry.departures.first {
                HStack(spacing: 5) {
                    Text(departure.route).font(.system(size: 12, weight: .heavy, design: .rounded))
                    Text(departure.headsign).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(Self.clock.string(from: departure.due)).font(Theme.mono(11, weight: .semibold))
                    let minutes = departure.minutes(at: entry.date)
                    Text(minutes <= 0 ? "MOST" : Countdown.compact(minutes: minutes))
                        .font(Theme.mono(12, weight: .heavy))
                }
            } else {
                Text(entry.message ?? "Nincs induló járat")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Links

    /// Opens the Megállófigyelő on this stop — the screen that shows the
    /// full departure list for the stops the rider watches, which is the
    /// natural next step from a widget row.
    private var stopURL: URL {
        guard let stopId = entry.stopId else { return DeepLink.home.url }
        return DeepLink.watchlist(stopId).url
    }

    /// A row leads to the bus itself, not the stop: from the widget the rider
    /// already knows which stop they picked, and the useful next screen is
    /// "where is it now".
    private func tripURL(_ departure: DepartureSnapshot) -> URL {
        DeepLink.trip(tripId: departure.tripId, vehicleId: departure.vehicleId).url
    }
}
