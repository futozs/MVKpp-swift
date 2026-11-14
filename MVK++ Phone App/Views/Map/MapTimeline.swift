//
//  MapTimeline.swift
//  MVK++ Phone App
//
//  „Idővonal”: any moment of an earlier day, replayed on the map or played
//  back fast (`MapTimeline.tsx`, `TimelineSlider.tsx`, `TimelineDayPicker.tsx`,
//  `useTimelinePlayback.ts`).
//

import Combine
import SwiftUI

enum MapPlaybackSpeed: Int, CaseIterable {
    case x1 = 1, x10 = 10, x60 = 60, x300 = 300
}

/// The cursor moves every frame; the published state follows it only every
/// 100 ms, so the screen does not re-render per frame. At a window edge the
/// cursor waits for the next window to load.
@MainActor
final class MapTimelinePlayback: ObservableObject {
    @Published private(set) var cursor: Double
    @Published private(set) var playing = false
    @Published private(set) var buffering = false
    @Published private(set) var speed: MapPlaybackSpeed = .x60
    @Published private(set) var stats = MapHistoryRenderResult(ready: false, visible: 0)

    struct Bounds {
        let start: Double
        let end: Double
        /// The latest available moment: today it moves with the clock, a
        /// minute behind it (web `useTimelinePlayback`).
        @MainActor var limit: Double {
            max(start, min(end - 1, RealtimeClient.shared.serverNow.rounded(.down) - MapTimelinePlayback.liveMargin))
        }

        init(_ range: MapHistoryTime.DayRange) {
            start = range.start
            end = range.end
        }
    }

    static let liveMargin: Double = 60

    var bounds: Bounds
    var getWindow: (Double) -> MapHistoryWindow? = { _ in nil }
    var render: (Double) -> MapHistoryRenderResult = { _ in MapHistoryRenderResult(ready: false, visible: 0) }

    private var t: Double
    private var scrubbing = false
    private var dirty = true
    private var loop: Task<Void, Never>?
    private var lastFrame: Date?
    private var lastUi = Date.distantPast

    private static let maxFrameDt: Double = 0.25
    private static let uiRefresh: TimeInterval = 0.1

    init(initial: Double, bounds: Bounds) {
        cursor = initial
        t = initial
        self.bounds = bounds
    }

    private func advance(_ t: Double, by delta: Double) -> Double {
        let here = MapHistoryData.windowStart(of: t)
        guard getWindow(here) != nil else { return t }
        var next = min(t + delta, bounds.limit)
        let there = MapHistoryData.windowStart(of: next)
        if there != here, getWindow(there) == nil { next = max(t, there - 0.001) }
        return next
    }

    private func frame() {
        let now = Date()
        let dt = lastFrame.map { min(Self.maxFrameDt, now.timeIntervalSince($0)) } ?? 0
        lastFrame = now
        var stalled = false
        if playing, !scrubbing, dt > 0 {
            let next = advance(t, by: dt * Double(speed.rawValue))
            stalled = next == t
            if !stalled {
                t = next
                dirty = true
            }
            if t >= bounds.limit {
                playing = false
                stalled = false
            }
        } else if playing, scrubbing {
            stalled = buffering
        }
        if stalled != buffering { buffering = stalled }
        if dirty {
            dirty = false
            let result = render(t)
            if result != stats { stats = result }
        }
        if !playing || now.timeIntervalSince(lastUi) >= Self.uiRefresh {
            lastUi = now
            cursor = t
        }
    }

    private func ensureLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.frame()
                if !self.playing && !self.dirty { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            self?.loop = nil
            self?.lastFrame = nil
        }
    }

    func invalidate() {
        dirty = true
        if loop == nil { frame() }
    }

    func seek(_ value: Double, bounds next: Bounds? = nil) {
        if let next { bounds = next }
        t = min(max(value, bounds.start), max(bounds.start, bounds.limit))
        cursor = t
        invalidate()
    }

    func step(_ delta: Double) { seek(t + delta) }

    func togglePlay() {
        let next = !playing
        let limit = bounds.limit
        if next, t >= limit - 1 {
            t = bounds.start
            cursor = t
        }
        playing = next
        if !next, buffering { buffering = false }
        lastFrame = nil
        dirty = true
        if next { ensureLoop() } else { frame() }
    }

    func setSpeed(_ value: MapPlaybackSpeed) { speed = value }

    func scrubStart() { scrubbing = true }

    func scrubEnd() {
        scrubbing = false
        lastFrame = nil
        invalidate()
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}

/// The bar at the bottom of the map.
struct MapTimelineBar: View {
    let routes: [String: Route]
    let filters: FilterState
    @ObservedObject var camera: MapCameraController
    @Binding var selectedHistoryId: String?
    var onExit: () -> Void

    @StateObject private var days = MapHistoryDays()
    @State private var narrow = false

    var body: some View {
        Group {
            if let error = days.error {
                status(error) {
                    Button("Újra") { Task { await days.load() } }
                        .buttonStyle(.mvk(.outline, size: .small))
                }
            } else if let list = days.days {
                if list.isEmpty {
                    status("Még egyetlen napról sincs rögzített GPS-adat.") { EmptyView() }
                } else {
                    MapTimelinePlayer(days: list, routes: routes, filters: filters, camera: camera, selectedHistoryId: $selectedHistoryId, exitIcon: !narrow, onExit: onExit)
                }
            } else {
                status("Rögzített napok betöltése…") { EmptyView() }
            }
        }
        .padding(12)
        .frame(maxWidth: 880)
        // The bar sits 12 pt in from each screen edge; the web hides the exit icon below a 400 px viewport.
        .onGeometryChange(for: Bool.self) { $0.size.width + 24 < 400 } action: { narrow = $0 }
        .background(Theme.card.opacity(0.95), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border))
        .mvkShadow(Theme.Shadow.xxl)
        .task { await days.load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Idővonal")
    }

    private func status<Extra: View>(_ text: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
            extra()
            MapTimelineExitButton(compact: false, action: onExit)
        }
    }
}

struct MapTimelineExitButton: View {
    let compact: Bool
    var showIcon = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if showIcon {
                Label("Vissza élőbe", systemImage: "dot.radiowaves.left.and.right")
            } else {
                Text("Vissza élőbe")
            }
        }
        .buttonStyle(.mvk(.secondary, size: compact ? .small : .regular, height: compact ? 44 : nil))
    }
}

private struct MapTimelinePlayer: View {
    let days: [String]
    let routes: [String: Route]
    let filters: FilterState
    @ObservedObject var camera: MapCameraController
    @Binding var selectedHistoryId: String?
    let exitIcon: Bool
    var onExit: () -> Void

    @StateObject private var frames = MapHistoryFrames()
    @StateObject private var playback: MapTimelinePlayback
    @State private var day: String
    @State private var dayListOpen = false
    @Environment(\.isTabActive) private var isTabActive

    private static let prefetchLead: Double = 15 * 60

    init(days: [String], routes: [String: Route], filters: FilterState, camera: MapCameraController, selectedHistoryId: Binding<String?>, exitIcon: Bool, onExit: @escaping () -> Void) {
        self.days = days
        self.routes = routes
        self.filters = filters
        self.camera = camera
        _selectedHistoryId = selectedHistoryId
        self.exitIcon = exitIcon
        self.onExit = onExit
        let first = days[0]
        _day = State(initialValue: first)
        let range = MapHistoryTime.serviceDayRange(first)
        let now = RealtimeClient.shared.serverNow.rounded(.down)
        let offset = now - MapHistoryTime.serviceDayRange(MapHistoryTime.serviceDay(of: now)).start
        let bounds = MapTimelinePlayback.Bounds(range)
        _playback = StateObject(wrappedValue: MapTimelinePlayback(
            initial: min(bounds.limit, range.start + offset),
            bounds: bounds
        ))
    }

    private var range: MapHistoryTime.DayRange { MapHistoryTime.serviceDayRange(day) }

    private var routeByShort: [String: Route] {
        var map: [String: Route] = [:]
        for r in routes.values {
            let key = r.key ?? r.short
            if map[key] == nil { map[key] = r }
        }
        return map
    }

    private var options: MapHistoryRenderOptions {
        let byShort = routeByShort
        var targets = filters.watch.map(\.normalizedForSearch)
        let q = filters.vq.trimmingCharacters(in: .whitespaces).normalizedForSearch
        if !q.isEmpty, !targets.contains(q) { targets.append(q) }
        let shorts: Set<String>? = filters.routes.isEmpty ? nil : Set(filters.routes.compactMap { routes[$0]?.key ?? routes[$0]?.short })
        let modes = filters.modes
        let watch = Set(filters.watch.map { $0.lowercased() })
        let query = filters.vq.trimmingCharacters(in: .whitespaces).lowercased()
        return MapHistoryRenderOptions(
            routeByShort: byShort,
            isVisible: { id, short in
                if !targets.isEmpty {
                    let vid = id.lowercased()
                    return targets.contains { vid.contains($0) }
                }
                if !modes.isEmpty {
                    let r = short.flatMap { byShort[$0] }
                    if !modes.contains(TransitIds.vehicleMode(id: id, mode: nil, routeType: r?.type)) { return false }
                }
                guard let shorts else { return true }
                return short.map(shorts.contains) ?? false
            },
            isTracked: { id in
                let vid = id.lowercased()
                return watch.contains(vid) || (!query.isEmpty && vid.contains(query))
            },
            showIds: filters.labels
        )
    }

    private var wanted: [Double] {
        let cursor = playback.cursor
        let here = MapHistoryData.windowStart(of: cursor)
        let offset = cursor - here
        var out = [here]
        if playback.playing || offset > MapHistoryData.windowSec - Self.prefetchLead { out.append(here + MapHistoryData.windowSec) }
        if offset < MapHistorySampler.maxGapSec { out.append(here - MapHistoryData.windowSec) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                playButton
                clock
                MapTimelineExitButton(compact: true, showIcon: exitIcon, action: onExit)
            }
            // Today's limit moves with the clock; one slider point is minutes.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                MapTimelineSlider(
                    range: range,
                    value: playback.cursor,
                    maxValue: playback.bounds.limit,
                    valueText: "\(MapHistoryTime.clockShort(playback.cursor)), \(MapHistoryTime.dateOf(playback.cursor))",
                    onScrub: { playback.seek($0) },
                    onScrubStart: playback.scrubStart,
                    onScrubEnd: playback.scrubEnd
                )
            }
            .padding(.horizontal, -4)
            .padding(.top, 6)
            HStack(spacing: 8) {
                dayPicker
                speedControl
            }
            .padding(.top, 4)
        }
        .overlay(alignment: .top) {
            if let id = selectedHistoryId {
                let info = camera.historySample(id)
                MapHistoryPopup(
                    vehicleId: id,
                    route: info.route.flatMap { routeByShort[$0] },
                    routeShort: info.route,
                    time: playback.cursor,
                    sample: info.sample,
                    onClose: { selectedHistoryId = nil }
                )
                .alignmentGuide(.top) { $0[.bottom] + 24 }
                .transition(.opacity)
            }
        }
        .onAppear(perform: wire)
        .onChange(of: playback.cursor) { _, _ in dropGonePopup() }
        .onChange(of: playback.stats) { _, _ in dropGonePopup() }
        .onChange(of: isTabActive) { _, active in
            if !active, playback.playing { playback.togglePlay() }
        }
        .onDisappear {
            playback.stop()
            frames.cancelAll()
            camera.clearHistory()
        }
        .onChange(of: frames.version) { _, _ in
            frames.ensure(wanted)
            playback.invalidate()
        }
        .onChange(of: wanted) { _, value in frames.ensure(value) }
        .onChange(of: filters) { _, _ in
            wire()
            playback.invalidate()
            dropGonePopup()
        }
        .onChange(of: routeSignature) { _, _ in
            wire()
            playback.invalidate()
        }
    }

    /// What a redraw depends on; the route count alone misses a recoloured
    /// or renamed route.
    private var routeSignature: Int {
        var hasher = Hasher()
        for r in routes.values.sorted(by: { $0.id < $1.id }) {
            hasher.combine(r.id)
            hasher.combine(r.short)
            hasher.combine(r.key)
            hasher.combine(r.color)
            hasher.combine(r.text)
            hasher.combine(r.type)
        }
        return hasher.finalize()
    }

    /// The popup closes once its vehicle is no longer on the map.
    private func dropGonePopup() {
        guard let id = selectedHistoryId, camera.historySample(id).sample == nil else { return }
        selectedHistoryId = nil
    }

    private func wire() {
        let frames = frames
        let camera = camera
        let options = options
        playback.getWindow = { frames.get($0) }
        playback.render = { camera.renderHistory($0, frames: frames, options: options) }
        frames.ensure(wanted)
        playback.invalidate()
    }

    private var playButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            playback.togglePlay()
        } label: {
            Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.primaryForeground)
                .frame(width: 44, height: 44)
                .background(Theme.primary, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playback.playing ? "Szünet" : "Lejátszás")
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MapHistoryTime.clock(playback.cursor))
                .font(Theme.mono(26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 6) {
                Text(MapHistoryTime.dateOf(playback.cursor)).lineLimit(1)
                Text("·").accessibilityHidden(true)
                statusView
            }
            .font(Theme.sans(11))
            .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusView: some View {
        if !playback.stats.ready || playback.buffering {
            if frames.error != nil {
                Button("Betöltési hiba. Újra") { frames.retry() }
                    .font(Theme.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
                    .underline()
                    .buttonStyle(.plain)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Theme.primary).frame(width: 6, height: 6)
                        .loadingPulse()
                    Text("Betöltés…")
                }
                .foregroundStyle(Theme.primary)
            }
        } else {
            Text("\(playback.stats.visible) jármű").font(Theme.mono(11, weight: .regular))
        }
    }

    /// Only the recorded days (`TimelineDayPicker.tsx`). The bar sits at the
    /// bottom of the screen, so the list opens upwards.
    private var dayPicker: some View {
        Button {
            withAnimation(Theme.Motion.fastAnimation) { dayListOpen.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(MapHistoryTime.dayLabel(day, short: true))
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .rotationEffect(.degrees(dayListOpen ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nap: \(MapHistoryTime.dayLabel(day))")
        .accessibilityValue(dayListOpen ? "kinyitva" : "")
        .overlay(alignment: .bottomLeading) {
            if dayListOpen {
                dayList
                    .alignmentGuide(.bottom) { $0[.bottom] + 44 + 8 }
                    .transition(.opacity)
            }
        }
        .zIndex(1)
    }

    private var dayList: some View {
        let today = MapHistoryTime.serviceDay(of: RealtimeClient.shared.serverNow)
        return ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        let selected = d == day
                        let hint = d == today ? "ma" : d == MapHistoryTime.addDays(today, -1) ? "tegnap" : nil
                        Button {
                            changeDay(d)
                            withAnimation(Theme.Motion.fastAnimation) { dayListOpen = false }
                        } label: {
                            HStack(spacing: 8) {
                                Text(MapHistoryTime.dayLabel(d))
                                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let hint {
                                    Text(hint)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .foregroundStyle(selected ? Theme.primary : Theme.foreground)
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(selected ? Theme.primary.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(d)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 288)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { reader.scrollTo(day) }
        }
        .frame(minWidth: 220)
        .background(Theme.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border))
        .mvkShadow(Theme.Shadow.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rögzített napok")
    }

    private func changeDay(_ next: String) {
        let dayOffset = playback.cursor - range.start
        let nextRange = MapHistoryTime.serviceDayRange(next)
        day = next
        playback.seek(nextRange.start + dayOffset, bounds: MapTimelinePlayback.Bounds(nextRange))
    }

    private var speedControl: some View {
        HStack(spacing: 2) {
            ForEach(MapPlaybackSpeed.allCases, id: \.self) { s in
                let on = playback.speed == s
                Button {
                    playback.setSpeed(s)
                } label: {
                    // Every cell is as wide as the widest label (the web's `grid-cols-4`).
                    ZStack {
                        Text("\(MapPlaybackSpeed.x300.rawValue)×").hidden()
                        Text("\(s.rawValue)×")
                    }
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 38, maxHeight: .infinity)
                    .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.none)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(Theme.Motion.fastAnimation, value: playback.speed)
        .padding(2)
        .frame(height: 44)
        .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lejátszási sebesség")
    }
}

/// The day's track with hour ticks; the part of today still to come cannot
/// be dragged into.
struct MapTimelineSlider: View {
    let range: MapHistoryTime.DayRange
    let value: Double
    let maxValue: Double
    let valueText: String
    var onScrub: (Double) -> Void
    var onScrubStart: () -> Void
    var onScrubEnd: () -> Void

    @State private var dragging = false
    private static let majorEvery = 3

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 32
            let span = range.end - range.start
            let pct = min(1, max(0, (value - range.start) / span))
            let available = min(1, max(0, (maxValue - range.start) / span))
            let ticks = MapHistoryTime.hourTicks(range)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.muted)
                    .frame(width: width, height: 6)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.primary.opacity(0.75)).frame(width: width * pct, height: 6)
                    }
                    .overlay(alignment: .trailing) {
                        if available < 1 {
                            Rectangle().fill(Theme.background.opacity(0.7)).frame(width: width * (1 - available), height: 6)
                        }
                    }
                    .clipShape(Capsule())
                    .offset(x: 16, y: 13)

                ForEach(Array(ticks.enumerated()), id: \.element.id) { i, tick in
                    let x = 16 + width * (tick.t - range.start) / span
                    let major = i % Self.majorEvery == 0
                    Rectangle()
                        .fill(major ? Theme.mutedForeground.opacity(0.6) : Theme.border)
                        .frame(width: 1, height: major ? 8 : 6)
                        .offset(x: x, y: 23)
                    if major {
                        Text(tick.label)
                            .font(Theme.mono(10, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize()
                            .frame(width: 30)
                            .offset(x: x - 15, y: 32)
                    }
                }

                Circle()
                    .fill(Theme.primary)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    .background(
                        Circle().fill(Theme.primary.opacity(dragging ? 0.3 : 0)).padding(-4)
                            .animation(Theme.Motion.fastAnimation, value: dragging)
                    )
                    .mvkShadow(Theme.Shadow.md)
                    .offset(x: 16 + width * pct - 10, y: 6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            onScrubStart()
                        }
                        let f = min(1, max(0, (g.location.x - 16) / max(width, 1)))
                        onScrub((range.start + f * span).rounded())
                    }
                    .onEnded { _ in
                        dragging = false
                        onScrubEnd()
                    }
            )
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel("Időpont a forgalmi napon")
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            onScrub(value + (direction == .increment ? 60 : -60))
        }
    }
}
