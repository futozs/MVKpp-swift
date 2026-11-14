//
//  TimetableDayPicker.swift
//  MVK++ Phone App
//

import SwiftUI

/// Previous day · date field · next day, in one bordered strip — the web
/// timetable's `DayPicker`.
struct TimetableDayPicker: View {
    let value: String
    let minIso: String?
    let maxIso: String?
    /// „Ma” here means the service day, which turns at 03:00.
    let todayIso: String
    var onShift: (Int) -> Void
    var onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            shiftButton(systemImage: "chevron.left", label: "Előző nap", days: -1, enabled: minIso.map { value > $0 } ?? true)
            TimetableDateField(value: value, minIso: minIso, maxIso: maxIso, todayIso: todayIso, onPick: onPick)
                .frame(maxWidth: .infinity)
            shiftButton(systemImage: "chevron.right", label: "Következő nap", days: 1, enabled: maxIso.map { value < $0 } ?? true)
        }
        .padding(2)
        .background(Theme.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func shiftButton(systemImage: String, label: String, days: Int, enabled: Bool) -> some View {
        Button {
            onShift(days)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(TimetablePressStyle(cornerRadius: 6))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(label)
    }
}

/// The date button and its month calendar — the web's own `DateField`, which
/// exists so the picker looks the same dark everywhere.
struct TimetableDateField: View {
    let value: String
    let minIso: String?
    let maxIso: String?
    let todayIso: String
    var onPick: (String) -> Void

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                Text(TimetableModel.fieldLabel(value))
                    .font(Theme.sans(12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(TimetablePressStyle(cornerRadius: 6))
        .accessibilityLabel("Menetrend napja")
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            TimetableCalendar(value: value, minIso: minIso, maxIso: maxIso, todayIso: todayIso) { iso in
                onPick(iso)
                isOpen = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The month grid of the date field.
private struct TimetableCalendar: View {
    let value: String
    let minIso: String?
    let maxIso: String?
    let todayIso: String
    var onPick: (String) -> Void

    @State private var viewYear: Int
    @State private var viewMonth: Int

    init(value: String, minIso: String?, maxIso: String?, todayIso: String, onPick: @escaping (String) -> Void) {
        self.value = value
        self.minIso = minIso
        self.maxIso = maxIso
        self.todayIso = todayIso
        self.onPick = onPick
        let parts = value.split(separator: "-").compactMap { Int($0) }
        _viewYear = State(initialValue: parts.count == 3 ? parts[0] : 2026)
        _viewMonth = State(initialValue: parts.count == 3 ? parts[1] : 1)
    }

    private static let weekdays = ["H", "K", "Sze", "Cs", "P", "Szo", "V"]
    private static let months = [
        "január", "február", "március", "április", "május", "június",
        "július", "augusztus", "szeptember", "október", "november", "december",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                monthButton("chevron.left", label: "Előző hónap", delta: -1)
                Spacer()
                Text("\(Self.months[viewMonth - 1].capitalized) \(String(viewYear))")
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                monthButton("chevron.right", label: "Következő hónap", delta: 1)
            }
            .padding(.bottom, 8)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day.uppercased())
                        .font(Theme.sans(10, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.vertical, 4)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }

            Button {
                onPick(todayIso)
            } label: {
                Text("Ma")
                    .font(Theme.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TimetablePressStyle(cornerRadius: 6))
            .padding(.top, 8)
        }
        .padding(10)
        .frame(width: 256)
        .background(Theme.card)
    }

    private func monthButton(_ systemImage: String, label: String, delta: Int) -> some View {
        Button {
            var month = viewMonth + delta
            var year = viewYear
            if month < 1 { month = 12; year -= 1 }
            if month > 12 { month = 1; year += 1 }
            viewMonth = month
            viewYear = year
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(TimetablePressStyle(cornerRadius: 6))
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: Int) -> some View {
        let iso = String(format: "%04d-%02d-%02d", viewYear, viewMonth, day)
        let disabled = (minIso.map { iso < $0 } ?? false) || (maxIso.map { iso > $0 } ?? false)
        let selected = iso == value
        let isToday = iso == todayIso
        return Button {
            onPick(iso)
        } label: {
            Text("\(day)")
                .font(.system(size: 12, weight: selected || isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.primaryForeground : isToday ? Theme.primary : Theme.foreground)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(selected ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(TimetablePressStyle(cornerRadius: 6))
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    /// The month as a Monday-first grid with blank leading and trailing cells.
    private var cells: [Int?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let first = calendar.date(from: DateComponents(year: viewYear, month: viewMonth, day: 1, hour: 12)),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Int?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: range.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}

/// The web's hover/active feedback on a touch screen: the accent fill while pressed.
struct TimetablePressStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.Radius.sm

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Theme.accent : .clear,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}
