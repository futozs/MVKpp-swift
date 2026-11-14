//
//  NewsViews.swift
//  MVK++ Watch App
//

import SwiftUI

/// MVK hírek: the announcements, newest first, readable on the wrist.
struct NewsListView: View {
    @EnvironmentObject private var router: WatchRouter
    @State private var feed: NewsFeed?
    @State private var error: String?

    var body: some View {
        List {
            if let feed {
                if feed.stale {
                    Text("Az MVK most nem válaszol, a legutóbbi lista látszik.")
                        .font(.caption2)
                        .foregroundStyle(Theme.offline)
                }
                ForEach(feed.items) { item in
                    Button {
                        router.push(.newsItem(item))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(3)
                            HStack(spacing: 4) {
                                ForEach(item.routes.prefix(4), id: \.self) { routeId in
                                    if let route = feed.routes[routeId] {
                                        RouteTile(short: route.short, colorHex: route.color, textHex: route.text, size: .small)
                                    }
                                }
                                Text(NewsTime.published(item.modifiedAt))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.late)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Hírek")
        .task {
            do {
                feed = try await APIClient.shared.news()
            } catch APIError.badStatus(503) {
                error = "Az MVK hírei most nem érhetők el."
            } catch {
                self.error = "Nem sikerült betölteni."
            }
        }
    }
}

struct NewsDetailView: View {
    let item: NewsItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(NewsTime.published(item.modifiedAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
                ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
        .navigationTitle(item.type ?? "Hír")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func blockView(_ block: NewsBlock) -> some View {
        switch block {
        case .paragraph(let runs):
            text(runs).font(.system(size: 13))
        case .heading(let runs):
            text(runs).font(.system(size: 14, weight: .bold))
        case .label(let runs):
            text(runs).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("•").foregroundStyle(Theme.primary)
                        text((entry.lead ?? []) + entry.runs).font(.system(size: 13))
                    }
                }
            }
        }
    }

    private func text(_ runs: [NewsRun]) -> Text {
        runs.reduce(Text("")) { result, run in
            var piece = Text(run.text)
            if run.bold == true { piece = piece.bold() }
            if run.italic == true { piece = piece.italic() }
            if run.href != nil { piece = piece.foregroundColor(Theme.primary) }
            return result + piece
        }
    }
}
