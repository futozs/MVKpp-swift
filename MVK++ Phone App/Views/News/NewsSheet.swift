//
//  NewsSheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// The map's news control (web `NewsButton`): only a small dot says there is
/// unseen news; opening marks everything seen.
struct NewsButton: View {
    /// Leave only this route on the map.
    let onShowRoute: (String) -> Void

    @StateObject private var news = NewsModel()
    @State private var isOpen = false
    @State private var fresh: Set<Int> = []

    var body: some View {
        let unseen = news.unseenCount
        GlassCircleButton {
            fresh = news.markAllSeen()
            news.refreshIfOld()
            isOpen = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOpen ? Theme.primary : Theme.foreground)
                .overlay(alignment: .topTrailing) {
                    if unseen > 0 {
                        Circle().fill(Theme.primary)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2).padding(-2))
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(unseen > 0 ? "Hírek, \(unseen) új" : "Hírek")
        .task { news.start() }
        .sheet(isPresented: $isOpen) {
            NewsSheet(news: news, fresh: fresh) { routeId in
                isOpen = false
                onShowRoute(routeId)
            }
            .mvkSheet()
        }
    }
}

/// MVK's news: list → article within one sheet (web `NewsDialog`).
struct NewsSheet: View {
    @ObservedObject var news: NewsModel
    let fresh: Set<Int>
    let onShowRoute: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let rowRoutesMax = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                list
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NewsItem.self) { item in
                NewsArticle(item: item, routes: news.feed?.routes ?? [:], onShowRoute: onShowRoute)
            }
        }
        .presentationDetents([.fraction(0.88), .large])
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hírek").font(.system(size: 17, weight: .bold))
                Text("Az MVK Zrt. közleményei\(news.feed.map { $0.items.isEmpty ? "" : " · \($0.items.count) aktuális" } ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                if news.feed?.stale == true {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.nosignal).frame(width: 6, height: 6)
                        Text("Az MVK most nem válaszol a legutóbb letöltött hírek látszanak.")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.nosignal)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            SheetCloseButton { dismiss() }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var list: some View {
        if news.feed == nil && news.isLoading {
            skeleton
        } else if let feed = news.feed {
            if feed.items.isEmpty {
                Text("Most nincs aktuális MVK-közlemény.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(feed.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                            NavigationLink(value: item) { row(item, routes: feed.routes) }
                                .buttonStyle(RowHighlightStyle(opacity: 0.45))
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                Text(news.error ?? "Az MVK hírei most nem érhetők el.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button { Task { await news.load() } } label: {
                    Label("Újra", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.mvk(.outline))
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ item: NewsItem, routes: [String: NewsRoute]) -> some View {
        let isFresh = fresh.contains(item.id)
        return HStack(alignment: .top, spacing: 14) {
            dateTab(item.modifiedAt, isFresh: isFresh)
            VStack(alignment: .leading, spacing: 0) {
                if let type = item.type {
                    Text(type.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.bottom, 2)
                }
                Text(item.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.summary.isEmpty, item.summary != item.title {
                    Text(item.summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .padding(.top, 4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.routes.isEmpty { routeStrip(item.routes, routes: routes).padding(.top, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground.opacity(0.45))
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityLabel((isFresh ? "Új: " : "") + item.title)
    }

    /// A small calendar leaf: the day of the last change; a dot when unseen.
    private func dateTab(_ unix: Double, isFresh: Bool) -> some View {
        let tab = NewsTime.dateTab(unix)
        return VStack(spacing: 4) {
            Text(tab.day).font(Theme.mono(16, weight: .bold)).foregroundStyle(Theme.foreground)
            Text(tab.month.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.mutedForeground)
        }
        .frame(width: 44, height: 44)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(isFresh ? Theme.primary.opacity(0.45) : Theme.border.opacity(0.8), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if isFresh {
                Circle().fill(Theme.primary).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2).padding(-2))
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityHidden(true)
    }

    private func routeStrip(_ ids: [String], routes: [String: NewsRoute]) -> some View {
        let shown = ids.filter { routes[$0] != nil }.prefix(Self.rowRoutesMax)
        let rest = ids.count - shown.count
        return HStack(spacing: 4) {
            ForEach(Array(shown), id: \.self) { id in
                if let route = routes[id] { RouteTile(short: route.short, colorHex: route.color, textHex: route.text, size: .small) }
            }
            if rest > 0 {
                Text("+\(rest)").font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.mutedForeground).padding(.leading, 2)
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.muted).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.muted).frame(height: 14).frame(maxWidth: .infinity).padding(.trailing, 50)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.muted.opacity(0.7)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.muted.opacity(0.7)).frame(height: 12).padding(.trailing, 90)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            Spacer()
        }
        .phaseAnimator([0.55, 1]) { content, phase in content.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityLabel("Betöltés")
    }
}

/// One announcement: date, title, the affected routes (tap: only that route
/// stays on the map), then the body.
private struct NewsArticle: View {
    let item: NewsItem
    let routes: [String: NewsRoute]
    let onShowRoute: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(NewsTime.published(item.modifiedAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                    if let type = item.type {
                        Text(type.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md - 4).strokeBorder(Theme.border, lineWidth: 1))
                    }
                }
                Text(item.title)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                let affected = item.routes.filter { routes[$0] != nil }
                if !affected.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        CapsLabel("Érintett járatok")
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(affected, id: \.self) { id in
                                if let route = routes[id] {
                                    Button { onShowRoute(id) } label: {
                                        RouteTile(short: route.short, colorHex: route.color, textHex: route.text)
                                    }
                                    .buttonStyle(PressScaleStyle())
                                    .accessibilityLabel("\(route.short): csak ez a járat a térképen")
                                }
                            }
                        }
                        Text("Koppints egy járatra: csak az marad a térképen.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    .padding(.top, 16)
                }

                NewsBodyView(blocks: item.blocks, routes: routes)
                    .padding(.top, 20)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1).offset(y: 0) }
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle("Hírek")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// An announcement body from the worker's blocks — no HTML, so nothing from
/// MVK's text can run. A route mentioned in the text shows in its own colours.
struct NewsBodyView: View {
    let blocks: [NewsBlock]
    let routes: [String: NewsRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .padding(.top, gap(index > 0 ? blocks[index - 1].kind : nil, block.kind))
            }
        }
        .font(.system(size: 14.5))
        .lineSpacing(5)
        .foregroundStyle(Theme.foreground.opacity(0.85))
        .tint(Theme.primary)
    }

    /// A heading separates, a label sticks to its content.
    private func gap(_ previous: String?, _ current: String) -> CGFloat {
        guard let previous else { return 0 }
        if current == "h" { return 28 }
        if previous == "h" || previous == "label" { return current == "label" ? 12 : 8 }
        return current == "label" ? 20 : 14
    }

    @ViewBuilder
    private func blockView(_ block: NewsBlock) -> some View {
        switch block {
        case .heading(let runs):
            Text(attributed(runs)).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.foreground)
        case .label(let runs):
            Text(attributed(runs)).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.foreground)
        case .paragraph(let runs):
            Text(attributed(runs))
        case .list(let items):
            listView(items)
        }
    }

    @ViewBuilder
    private func listView(_ items: [NewsListItem]) -> some View {
        // "Végállomásról: times" rows: label above, content below, on one card.
        if items.allSatisfy({ $0.lead != nil }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attributed(item.lead ?? [])).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.foreground)
                        itemBody(item.runs)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border.opacity(0.8), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.mutedForeground.opacity(0.6)).frame(width: 5, height: 5).offset(y: -3)
                        Text(listLine(item))
                    }
                }
            }
        }
    }

    /// Only times ("15:20, 16:20, 17:20") → a mono row.
    @ViewBuilder
    private func itemBody(_ runs: [NewsRun]) -> some View {
        let text = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^\d{1,2}:\d{2}(?:,\s*\d{1,2}:\d{2})+$"#, options: .regularExpression) != nil {
            FlowLayout(spacing: 12, lineSpacing: 2) {
                ForEach(text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { time in
                    Text(time).font(Theme.mono(13, weight: .regular)).foregroundStyle(Theme.foreground)
                }
            }
            .padding(.top, 2)
        } else {
            Text(attributed(runs)).font(.system(size: 14))
        }
    }

    private func listLine(_ item: NewsListItem) -> AttributedString {
        guard let lead = item.lead else { return attributed(item.runs) }
        var head = attributed(lead)
        head.font = .system(size: 14.5, weight: .semibold)
        head.foregroundColor = Theme.foreground
        return head + AttributedString(": ") + attributed(item.runs)
    }

    private func attributed(_ runs: [NewsRun]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var text = run.href != nil && run.text == run.href ? NewsTime.prettyURL(run.text) : run.text
            if let routeId = run.route, let route = routes[routeId] {
                text = "\u{2009}\(text)\u{2009}"
                var piece = AttributedString(text)
                piece.backgroundColor = Theme.hex(route.color)
                piece.foregroundColor = Theme.hex(route.text, fallback: .white)
                piece.font = .system(size: 12, weight: .heavy).monospacedDigit()
                out += piece
                continue
            }
            var piece = AttributedString(text)
            if run.bold == true {
                piece.font = .system(size: 14.5, weight: .semibold)
                piece.foregroundColor = Theme.foreground
            }
            if run.italic == true { piece.font = .system(size: 14.5).italic() }
            if let href = run.href, let url = URL(string: href) {
                piece.link = url
                piece.foregroundColor = Theme.primary
                piece.underlineStyle = .single
                piece += AttributedString(" ↗")
            }
            out += piece
        }
        return out
    }
}
