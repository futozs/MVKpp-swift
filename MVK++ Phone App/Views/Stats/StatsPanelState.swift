//
//  StatsPanelState.swift
//  MVK++ Phone App
//

import SwiftUI

// The shared states and pickers of `components/stats/PanelState.tsx`.

/// Unavailable / error / loading / empty, then the content.
struct StatsQueryBoundary<T, Content: View>: View {
    @ObservedObject var query: StatsQuery<T>
    var empty: ((T) -> Bool)?
    @ViewBuilder var content: (T) -> Content

    init(_ query: StatsQuery<T>, empty: ((T) -> Bool)? = nil, @ViewBuilder content: @escaping (T) -> Content) {
        self.query = query
        self.empty = empty
        self.content = content
    }

    var body: some View {
        if query.unavailable {
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.xmark")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.mutedForeground)
                Text("Az adatraktár nem érhető el")
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text("npm run db:migrate")
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .statsDashed(radius: 16, fill: Theme.card.opacity(0.5))
        } else if let error = query.error {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14))
                Text(error)
                    .font(Theme.sans(12))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.destructive)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .statsCard(radius: 16, fill: Theme.destructive.opacity(0.10), stroke: Theme.destructive.opacity(0.30))
        } else if query.loading && query.data == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.mutedForeground)
                Text("Betöltés…")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .statsCard(radius: 16)
        } else if let data = query.data, !(empty?(data) ?? false) {
            content(data)
        } else {
            Text("Erre az időszakra még nincs adat")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .statsDashed(radius: 16, fill: Theme.card.opacity(0.5))
        }
    }
}

/// A panel heading: `text-lg font-bold tracking-tight`.
struct StatsHeading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.sans(18, weight: .bold))
            .tracking(-0.4)
            .foregroundStyle(Theme.foreground)
    }
}

struct StatsPillItem<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    var sub: String?
    var color: String?
    var search: String?
}

/// A horizontally scrolling row of choice pills, optionally with a star.
struct StatsPillPicker<ID: Hashable>: View {
    let items: [StatsPillItem<ID>]
    let value: ID?
    let onChange: (ID) -> Void
    var isFavorite: ((ID) -> Bool)?
    var onToggleFavorite: ((ID) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    pill(item)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func pill(_ item: StatsPillItem<ID>) -> some View {
        let active = item.id == value
        let favorite = isFavorite?(item.id) ?? false
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 4) {
            Button {
                onChange(item.id)
            } label: {
                HStack(spacing: 6) {
                    if let color = item.color {
                        Circle().fill(Theme.hex(color)).frame(width: 8, height: 8)
                    }
                    Text(item.label)
                        .monospacedDigit()
                    if let sub = item.sub {
                        Text(sub)
                            .lineLimit(1)
                            .frame(maxWidth: 144, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .opacity(0.6)
                    }
                }
                .font(Theme.sans(12, weight: .semibold))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onToggleFavorite {
                Button {
                    onToggleFavorite(item.id)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(favorite ? (active ? Theme.primaryForeground : Theme.early) : (active ? Theme.primaryForeground : Theme.mutedForeground))
                        .opacity(favorite ? 1 : 0.6)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? "Eltávolítás a kedvencekből" : "Kedvencnek jelölés")
            }
        }
        .foregroundStyle(active ? Theme.primaryForeground : Theme.mutedForeground)
        .padding(.leading, 10)
        .padding(.trailing, onToggleFavorite == nil ? 10 : 6)
        .padding(.vertical, 7)
        .background(active ? Theme.primary : Theme.card, in: shape)
        .overlay(shape.strokeBorder(active ? Theme.primary : Theme.border, lineWidth: 1))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The search input of the stats panels (`Input` with a leading magnifier).
struct StatsSearchField: View {
    @Binding var text: String
    let placeholder: String
    var clearable = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.mutedForeground))
                .font(Theme.sans(16))
                .foregroundStyle(Theme.foreground)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if clearable, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keresés törlése")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
    }
}

/// A filter field ahead of the pill row: hundreds of vehicles or routes are
/// unusable as a horizontal scroll alone.
struct StatsSearchablePicker<ID: Hashable>: View {
    let items: [StatsPillItem<ID>]
    let value: ID?
    let onChange: (ID) -> Void
    let placeholder: String
    var limit = 120
    var isFavorite: ((ID) -> Bool)?
    var onToggleFavorite: ((ID) -> Void)?

    @State private var query = ""

    var body: some View {
        let filtered = filter()
        VStack(alignment: .leading, spacing: 8) {
            StatsSearchField(text: $query, placeholder: placeholder)
            if filtered.isEmpty {
                Text("Nincs „\(query)” találat.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 4)
            } else {
                StatsPillPicker(items: filtered, value: value, onChange: onChange, isFavorite: isFavorite, onToggleFavorite: onToggleFavorite)
                if items.count > filtered.count {
                    Text(verbatim: "\(filtered.count) látszik a(z) \(items.count) elemből szűkíts a kereséssel.")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func filter() -> [StatsPillItem<ID>] {
        let t = query.trimmingCharacters(in: .whitespaces).normalizedForSearch
        guard !t.isEmpty else { return Array(items.prefix(limit)) }
        return Array(items.filter {
            $0.label.normalizedForSearch.contains(t)
                || ($0.sub ?? "").normalizedForSearch.contains(t)
                || ($0.search ?? "").normalizedForSearch.contains(t)
        }.prefix(limit))
    }
}

/// shadcn `Button` look-alikes used on the panels.
struct StatsButtonStyle: ButtonStyle {
    enum Variant { case outline, ghost }
    var variant: Variant = .outline
    var icon = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return configuration.label
            .font(Theme.sans(12, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, icon ? 0 : 12)
            .frame(minWidth: icon ? 36 : nil, minHeight: icon ? 36 : 32)
            .background(
                configuration.isPressed ? Theme.accent : (variant == .outline ? Theme.background : .clear),
                in: shape
            )
            .overlay {
                if variant == .outline { shape.strokeBorder(Theme.input, lineWidth: 1) }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(shape)
    }
}

/// The `RoutePill` of the prediction lists: mono, 18 pt high.
struct StatsRoutePill: View {
    let route: String
    let color: String?
    let text: String?

    var body: some View {
        Text(route)
            .font(Theme.mono(11, weight: .bold))
            .lineLimit(1)
            .foregroundStyle(Theme.hex(text ?? "FFFFFF", fallback: .white))
            .padding(.horizontal, 4)
            .frame(minWidth: 26, minHeight: 18)
            .background(Theme.hex(color ?? "64748B"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}
