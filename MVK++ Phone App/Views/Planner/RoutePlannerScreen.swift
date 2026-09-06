//
//  RoutePlannerScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// A→B by place name: which service, from where, at what time — annotated
/// with how punctual that boarding usually is, which the operator's own
/// planner does not tell you.
struct RoutePlannerScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var location: LocationProvider

    @StateObject private var model = RoutePlannerModel()

    @State private var from: Stop?
    @State private var to: Stop?
    @State private var departure = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchCard

                    if model.isLoading {
                        ProgressView()
                            .tint(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    if !model.trips.isEmpty {
                        SectionLabel("Lehetséges útvonalak", trailing: routeSummary)
                        ForEach(model.trips) { trip in
                            TripPlanCard(trip: trip, model: model)
                        }
                    }

                    if let historic = model.historic {
                        SectionLabel("Történeti becslés", trailing: routeSummary)
                        HistoricEstimateCard(estimate: historic)
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Útvonaltervező")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlacePicker(title: "Honnan", places: places, selection: $from, userLocation: location.position)
            PlacePicker(title: "Hova", places: places, selection: $to, userLocation: location.position)

            HStack(spacing: 10) {
                DatePicker("Mikor", selection: $departure)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Theme.primary)

                Spacer(minLength: 0)

                Button {
                    swap(&from, &to)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Irány megfordítása")
            }

            Button {
                guard let from, let to else { return }
                Task { await model.plan(from: from, to: to, at: departure) }
            } label: {
                Label(
                    isPast ? "Történeti becslés" : "Útvonal keresése",
                    systemImage: isPast ? "clock.arrow.circlepath" : "bolt.fill"
                )
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.primary)
            .disabled(from == nil || to == nil || model.isLoading)

            if let error = model.errorMessage {
                ErrorNotice(message: error)
            }
        }
        .padding(16)
        .dataCard(cornerRadius: Theme.Radius.xxl)
    }

    // MARK: - Derived data

    private var isPast: Bool { RoutePlannerModel.isPast(departure) }

    private var routeSummary: String? {
        guard let from, let to else { return nil }
        return "\(from.name) → \(to.name)"
    }

    /// One entry per place name. GTFS lists a row per platform, and a planner
    /// asked for "Búza tér" does not care which pole the rider means.
    private var places: [Stop] {
        var byName: [String: Stop] = [:]
        for stop in store.stops where byName[stop.name] == nil {
            byName[stop.name] = stop
        }
        return byName.values.sorted {
            $0.name.compare($1.name, options: [], range: nil, locale: Locale(identifier: "hu_HU")) == .orderedAscending
        }
    }
}

/// Type-ahead place field. Nearby places lead the list when a fix exists —
/// the origin is almost always where the rider is standing.
private struct PlacePicker: View {
    let title: String
    let places: [Stop]
    @Binding var selection: Stop?
    let userLocation: GeoPosition?

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.mutedForeground)

            if let selection {
                Button {
                    self.selection = nil
                    text = ""
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.primary.opacity(0.7))
                        Text(selection.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("módosít")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Theme.primary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.primary, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                TextField("Település, városrész vagy megálló neve…", text: $text)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Theme.input, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .accessibilityLabel(title)

                if !matches.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(matches) { place in
                            Button {
                                selection = place
                                text = ""
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.mutedForeground)
                                    Text(place.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.foreground)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if let km = distance(to: place) {
                                        Text(Geo.formatDistance(km))
                                            .font(Theme.mono(11, weight: .regular))
                                            .foregroundStyle(Theme.primary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Theme.border.opacity(0.5))
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Nincs ilyen nevű hely a hálózatban.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
    }

    private var matches: [Stop] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let hits = places.filter { $0.name.containsNormalized(needle) }

        guard let userLocation else { return Array(hits.prefix(8)) }
        return hits
            .sorted {
                Geo.distanceKm(userLocation.lat, userLocation.lon, $0.lat, $0.lon)
                    < Geo.distanceKm(userLocation.lat, userLocation.lon, $1.lat, $1.lon)
            }
            .prefix(8)
            .map { $0 }
    }

    private func distance(to place: Stop) -> Double? {
        guard let userLocation else { return nil }
        return Geo.distanceKm(userLocation.lat, userLocation.lon, place.lat, place.lon)
    }
}
