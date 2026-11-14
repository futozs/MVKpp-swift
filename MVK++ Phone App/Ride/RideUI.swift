//
//  RideUI.swift
//  MVK++ Phone App
//
//  Building blocks shared by the ride screens: the web's shadcn buttons, the
//  stop picker (`StopChoiceList`) and the timetable trip picker (`PastTripList`).
//

import SwiftUI

struct RideButton: View {
    let title: String
    var systemImage: String?
    var variant: MVKButtonStyle.Variant = .primary
    var size: MVKButtonStyle.Size = .regular
    var fullWidth = false
    var busy = false
    var iconTint: Color?
    var fill: Color?
    var border: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconTint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
                }
                Text(title).truncationMode(.tail)
            }
        }
        .buttonStyle(.mvk(variant, size: size, fullWidth: fullWidth, fill: fill, border: border))
        .fixedSize(horizontal: !fullWidth, vertical: false)
        .layoutPriority(fullWidth ? 0 : 1)
    }
}

struct RidePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}

/// Small uppercase eyebrow label: `text-[11px] font-semibold uppercase tracking-wide`.
struct RideEyebrow: View {
    let text: String
    var systemImage: String?
    var color: Color = Theme.primary
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: size, weight: .semibold)) }
            Text(text.uppercased())
                .font(Theme.sans(size, weight: .semibold))
                .tracking(0.5)
                .lineLimit(1)
        }
        .foregroundStyle(color)
    }
}

/// The trip's stops to pick the boarding or alighting stop. Where the bus has
/// already been its actual time shows (departure for boarding, arrival for
/// alighting) — that is easier to recall.
struct StopChoiceList: View {
    enum TimeOf { case dep, arr }

    let stops: [TripStop]
    let lo: Int
    let hi: Int
    let times: [Int: RideStopTime]
    let timeOf: TimeOf
    let selected: Int?
    var marks: [Int: String] = [:]
    /// Kept in view without a selection (e.g. where the bus is now) — not a suggestion.
    var focusIdx: Int?
    var focusLabel: String?
    let onPick: (Int) -> Void

    private var rows: ArraySlice<TripStop> {
        let a = max(0, lo)
        let b = min(stops.count - 1, max(lo, hi))
        guard a <= b, !stops.isEmpty else { return [] }
        return stops[a...b]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.idx) { s in row(s).id(s.idx) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let target = selected ?? focusIdx { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private func row(_ s: TripStop) -> some View {
        let t = times[s.idx]
        let at = t.map { timeOf == .dep ? ($0.dep ?? $0.arr) : $0.arr }
        let on = selected == s.idx
        let focus = focusIdx == s.idx
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onPick(s.idx)
        } label: {
            HStack(spacing: 8) {
                Text(at.map(BudapestClock.hm) ?? s.schedTime)
                    .font(Theme.mono(12, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(at == nil ? Theme.mutedForeground : Theme.foreground)
                    .frame(width: 48, alignment: .leading)
                Text(s.name)
                    .font(Theme.sans(13, weight: on ? .semibold : .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if focus, let focusLabel {
                        Text(focusLabel).font(Theme.sans(10.5, weight: .medium)).foregroundStyle(Theme.mutedForeground)
                    }
                    if let mark = marks[s.idx] {
                        Text(mark).font(Theme.sans(10.5, weight: .semibold)).foregroundStyle(Theme.primary)
                    }
                    if on {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
            .background(on ? Theme.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                if on { RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.primary.opacity(0.45), lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

/// Timetabled trips to pick from: departure, direction, and which bus ran it
/// (if the system saw it). `focusId` is kept in view.
struct PastTripList: View {
    let trips: [PastTripRow]
    var focusId: String?
    /// A note beside the trip (e.g. „ez a busz”).
    var badge: (PastTripRow) -> String? = { _ in nil }
    let onPick: (PastTripRow) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(trips) { t in row(t).id(t.tripId) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let focusId { proxy.scrollTo(focusId, anchor: .center) }
            }
        }
    }

    private func row(_ t: PastTripRow) -> some View {
        Button {
            onPick(t)
        } label: {
            HStack(spacing: 10) {
                Text(BudapestClock.hm(t.depTs))
                    .font(Theme.mono(13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 48, alignment: .leading)
                RouteTile(short: t.route, colorHex: t.color, textHex: t.text, size: .small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(t.destinationName) felé")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text("\(t.originName) · érk. \(BudapestClock.hm(t.endTs))")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    if let run = t.run {
                        Text(TransitIds.displayVehicleId(run.vehicleId))
                            .font(Theme.mono(11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let note = badge(t) {
                        Text(note).font(Theme.sans(10, weight: .semibold)).foregroundStyle(Theme.primary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// The step heading with an optional back arrow (`RideSetup`'s `StepHead`).
struct RideStepHead: View {
    let title: String
    let hint: String
    var onBack: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Vissza")
                .padding(.leading, -6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.sans(14, weight: .bold)).foregroundStyle(Theme.foreground)
                Text(hint).font(Theme.sans(11.5)).foregroundStyle(Theme.mutedForeground).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// Centred muted line for loading, empty and error states.
struct RideMessage: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.sans(14))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
    }
}

enum RideFormat {
    static func minText(_ s: Double) -> String { "\(max(1, Int((s / 60).rounded()))) perc" }

    static func km(_ m: Double?) -> String? {
        guard let m else { return nil }
        return "\(oneDecimal(m / 1000)) km"
    }

    static func oneDecimal(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// „2 óra 14 perc” / „38 perc” / „2 óra”; two days and more in days.
    static func minutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) perc" }
        let h = minutes / 60
        if h >= 48 { return "\(oneDecimal((Double(minutes) / 60 / 24 * 10).rounded() / 10)) nap" }
        return minutes % 60 != 0 ? "\(h) óra \(minutes % 60) perc" : "\(h) óra"
    }

    static func delayLabel(_ s: Double?) -> String { DelayFormat.label(s.map { Int($0.rounded()) }) }
    static func delayTone(_ s: Double?) -> Color { DelayFormat.tone(s.map { Int($0.rounded()) }) }

    static func trafficColor(_ level: Double) -> Color { TrafficColor.color(level) }
}
