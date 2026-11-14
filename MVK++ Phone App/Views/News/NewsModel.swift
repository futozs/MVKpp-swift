//
//  NewsModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The news list with its seen-state (web `useNews`): refreshed every
/// 10 minutes, re-asked on open when older than 2.
@MainActor
final class NewsModel: ObservableObject {
    @Published private(set) var feed: NewsFeed?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = true

    /// The seen IDs — synced, so a read item is read on every device.
    private static let seenKey = "mvk_news_seen"
    private static let seenMax = 80
    private var loadedAt = Date.distantPast
    private var timer: Task<Void, Never>?

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                try? await Task.sleep(for: .seconds(10 * 60))
            }
        }
    }

    deinit { timer?.cancel() }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let url = try APIClient.shared.url(path: "/engine/news")
            let (data, response) = try await APIClient.shared.session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw NewsError.message(status == 503 ? "Az MVK hírei most nem érhetők el." : "Nem sikerült betölteni (\(status)).")
            }
            feed = try JSONDecoder().decode(NewsFeed.self, from: data)
            error = nil
            loadedAt = Date()
        } catch NewsError.message(let message) {
            error = message
        } catch {
            self.error = "Nem sikerült betölteni."
        }
    }

    private enum NewsError: Error { case message(String) }

    private var seen: Set<Int> { Set(LocalStore.shared.json(Self.seenKey, as: [Int].self) ?? []) }

    var unseenCount: Int {
        let seen = seen
        return (feed?.items ?? []).filter { !seen.contains($0.id) }.count
    }

    /// On opening the list: what is new now is returned, and all of it is
    /// marked seen.
    func markAllSeen() -> Set<Int> {
        let seenNow = seen
        let fresh = Set((feed?.items ?? []).map(\.id).filter { !seenNow.contains($0) })
        if !fresh.isEmpty, let feed {
            var list = LocalStore.shared.json(Self.seenKey, as: [Int].self) ?? []
            for id in feed.items.map(\.id) where !list.contains(id) { list.append(id) }
            LocalStore.shared.setJSON(Self.seenKey, Array(list.suffix(Self.seenMax)))
        }
        return fresh
    }

    func refreshIfOld() {
        guard Date().timeIntervalSince(loadedAt) > 2 * 60 else { return }
        Task { await load() }
    }
}
