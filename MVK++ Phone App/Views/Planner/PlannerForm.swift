//
//  PlannerForm.swift
//  MVK++ Phone App
//

import SwiftUI

/// Tailwind's amber scale, which the planner uses for "tight" and the fallback-timetable note.
enum PlannerAmber {
    static let a200 = Color(red: 0.992, green: 0.902, blue: 0.541)
    static let a300 = Color(red: 0.988, green: 0.827, blue: 0.302)
    static let a400 = Color(red: 0.984, green: 0.749, blue: 0.141)
}

struct PlannerForm: View {
    @ObservedObject var model: RoutePlannerModel

    private static let hint: [JourneyMode: String] = [
        .past: "Múltbeli időpont: a járművek mért adataiból megmutatjuk, mi történt valójában.",
        .now: "Most: ahol a jármű már úton van, az élő késéssel számolunk.",
        .future: "Jövőbeli időpont: a várható késést a korábbi, azonos napszakos mérésekből becsüljük.",
    ]

    var body: some View {
        let mode = model.mode
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(spacing: 12) {
                    PlannerPlaceSelect(label: "Honnan", places: model.places, value: $model.form.from)
                    PlannerPlaceSelect(label: "Hova", places: model.places, value: $model.form.to)
                }
                Button {
                    withAnimation(Theme.Motion.fastAnimation) { model.swap() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 36, height: 36)
                        .background(Theme.background, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.input, lineWidth: 1))
                        .mvkShadow(Theme.Shadow.sm)
                        .contentShape(Circle())
                }
                .buttonStyle(PlannerPressStyle())
                .padding(.top, 20)
                .accessibilityLabel("Irány megfordítása")
            }

            PlannerTravelModes(model: model)
                .padding(.top, 16)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                PlannerSegmented(arriveBy: $model.form.arriveBy)
                HStack(spacing: 8) {
                    PlannerDateField(value: $model.form.date, label: model.form.arriveBy ? "Érkezés napja" : "Indulás napja")
                    PlannerTimeField(value: $model.form.time, label: model.form.arriveBy ? "Érkezés ideje" : "Indulás ideje")
                    Button("Most") { model.setNow() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            submitButton(mode: mode)
                .padding(.top, 8)

            Text(model.form.from.isEmpty || model.form.from != model.form.to ? Self.hint[mode] ?? "" : "A kiinduló- és a célpont ugyanaz.")
                .font(.system(size: 11))
                .foregroundStyle(mode == .past ? Theme.early : Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func submitButton(mode: JourneyMode) -> some View {
        let enabled = model.canSubmit && !model.isLoading
        return Button {
            model.submit()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode == .past ? "clock.arrow.circlepath" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.isLoading ? "Keresés…" : mode == .past ? "Mi történt akkor?" : "Útvonal keresése")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Theme.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.primary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isLoading) { _, loading in loading }
    }
}

/// „Indulás” / „Érkezés” — what the chosen time means.
private struct PlannerSegmented: View {
    @Binding var arriveBy: Bool

    var body: some View {
        HStack(spacing: 4) {
            option(false, "Indulás")
            option(true, "Érkezés")
        }
        .padding(4)
        .frame(height: 36)
        .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Az időpont jelentése")
    }

    private func option(_ value: Bool, _ label: String) -> some View {
        let selected = arriveBy == value
        return Button {
            withAnimation(Theme.Motion.fastAnimation) { arriveBy = value }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.mutedForeground)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .frame(minWidth: 64)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.primary)
                            .mvkShadow(Theme.Shadow.sm)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pick a stop by name (accent- and case-insensitive).
struct PlannerPlaceSelect: View {
    let label: String
    let places: [PlannerPlace]
    @Binding var value: String

    @State private var text = ""
    @FocusState private var focused: Bool

    private static let maxMatches = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.mutedForeground)

            if let selected = places.first(where: { $0.id == value }) {
                Button {
                    pick("")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                        Text(selected.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("módosít")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(Theme.primary.opacity(0.6), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(selected.name)")
                .accessibilityHint("módosít")
            } else {
                TextField("", text: $text, prompt: Text("Megálló neve…").foregroundStyle(Theme.mutedForeground))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit {
                        if let first = matches.first { pick(first.id) }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(focused ? Theme.ring : Theme.input, lineWidth: 1)
                    )
                    .accessibilityLabel(label)

                if !matches.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(matches) { place in
                            Button {
                                pick(place.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.mutedForeground)
                                    Text(place.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.foreground)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlannerRowButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Theme.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .mvkShadow(Theme.Shadow.md)
                    .transition(.opacity)
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Nincs ilyen nevű megálló.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, 4)
                }
            }
        }
        .animation(Theme.Motion.fastAnimation, value: matches.map(\.id))
    }

    private var matches: [PlannerPlace] {
        let needle = text.trimmingCharacters(in: .whitespaces).normalizedForSearch
        guard !needle.isEmpty else { return [] }
        var starts: [PlannerPlace] = []
        var contains: [PlannerPlace] = []
        for place in places {
            let name = place.name.normalizedForSearch
            if name.hasPrefix(needle) { starts.append(place) } else if name.contains(needle) { contains.append(place) }
        }
        return Array((starts + contains).prefix(Self.maxMatches))
    }

    private func pick(_ id: String) {
        value = id
        text = ""
        focused = false
    }
}

struct PlannerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}

struct PlannerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.accent : Color.clear)
    }
}

/// What to plan with: MVK always, Volán and rail can be ticked.
private struct PlannerTravelModes: View {
    @ObservedObject var model: RoutePlannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MIVEL UTAZNÁL?")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.mutedForeground)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                check("MVK", checked: true, locked: true) { _ in }
                check("Volán", checked: model.travel.coach, locked: false) { model.setTravel(coach: $0) }
                check("Vonat", checked: model.travel.rail, locked: false) { model.setTravel(rail: $0) }
            }
        }
    }

    private func check(_ label: String, checked: Bool, locked: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Button {
            guard !locked else { return }
            withAnimation(Theme.Motion.fastAnimation) { onChange(!checked) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(checked ? Theme.primary : Theme.card)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(checked ? Theme.primary : Theme.mutedForeground.opacity(0.5), lineWidth: 1)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Theme.primaryForeground)
                    }
                }
                .frame(width: 16, height: 16)
                .opacity(locked ? 0.7 : 1)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(checked ? Theme.foreground : Theme.mutedForeground)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(checked ? Theme.primary.opacity(0.10) : Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(checked ? Theme.primary.opacity(0.5) : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: checked)
        .accessibilityLabel(label)
        .accessibilityValue(checked ? "bepipálva" : "nincs bepipálva")
        .accessibilityHint(locked ? "Az MVK járatai mindig benne vannak a tervezésben." : "")
    }
}

/// The date button and its calendar, styled like the web's own date field.
private struct PlannerDateField: View {
    @Binding var value: String
    let label: String

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mutedForeground)
                Text(PlannerFormat.shortDate(value))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(PlannerFormat.longDate(value))
        .popover(isPresented: $open) {
            PlannerCalendar(value: $value, open: $open)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct PlannerCalendar: View {
    @Binding var value: String
    @Binding var open: Bool

    @State private var viewYear = 0
    @State private var viewMonth = 0

    private static let weekdays = ["H", "K", "Sze", "Cs", "P", "Szo", "V"]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                monthButton("chevron.left", "Előző hónap", -1)
                Spacer()
                Text("\(PlannerFormat.monthNames[viewMonth].capitalized) \(String(viewYear))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                monthButton("chevron.right", "Következő hónap", 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.vertical, 4)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayButton(day)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
            Button {
                value = PlannerFormat.todayLocalIso()
                open = false
            } label: {
                Text("Ma")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 256)
        .presentationBackground(Theme.card)
        .onAppear {
            let parts = value.split(separator: "-").compactMap { Int($0) }
            viewYear = parts.first ?? 2026
            viewMonth = parts.count > 1 ? max(0, min(11, parts[1] - 1)) : 0
        }
    }

    private func monthButton(_ icon: String, _ label: String, _ delta: Int) -> some View {
        Button {
            var month = viewMonth + delta
            var year = viewYear
            if month < 0 { month = 11; year -= 1 } else if month > 11 { month = 0; year += 1 }
            viewMonth = month
            viewYear = year
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var cells: [Int?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PlannerFormat.zone
        guard let first = calendar.date(from: DateComponents(year: viewYear, month: viewMonth + 1, day: 1, hour: 12)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        let weekday = (calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Int?] = Array(repeating: nil, count: weekday)
        cells.append(contentsOf: (1...days).map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func dayButton(_ day: Int) -> some View {
        let iso = String(format: "%04d-%02d-%02d", viewYear, viewMonth + 1, day)
        let selected = iso == value
        let today = iso == PlannerFormat.todayLocalIso()
        return Button {
            value = iso
            open = false
        } label: {
            Text("\(day)")
                .font(.system(size: 12, weight: selected || today ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.primaryForeground : today ? Theme.primary : Theme.foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The time button and its hour/minute columns, styled like the web's own time field.
private struct PlannerTimeField: View {
    @Binding var value: String
    let label: String

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mutedForeground)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: 88, height: 36)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .popover(isPresented: $open) {
            PlannerTimeColumns(value: $value, open: $open)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct PlannerTimeColumns: View {
    @Binding var value: String
    @Binding var open: Bool

    private var hour: Int { Int(value.split(separator: ":").first ?? "") ?? 0 }
    private var minute: Int { Int(value.split(separator: ":").dropFirst().first ?? "") ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            column(0..<24, selected: hour) { value = String(format: "%02d:%02d", $0, minute) }
            Rectangle().fill(Theme.border).frame(width: 1)
            column(0..<60, selected: minute) {
                value = String(format: "%02d:%02d", hour, $0)
                open = false
            }
        }
        .frame(height: 192)
        .presentationBackground(Theme.card)
    }

    private func column(_ range: Range<Int>, selected: Int, pick: @escaping (Int) -> Void) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { n in
                        Button {
                            pick(n)
                        } label: {
                            Text(String(format: "%02d", n))
                                .font(.system(size: 14, weight: n == selected ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(n == selected ? Theme.primary : Theme.foreground)
                                .frame(width: 56)
                                .padding(.vertical, 6)
                                .background(n == selected ? Theme.primary.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(n)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
        .frame(width: 56)
    }
}
