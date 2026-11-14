//
//  WebLink.swift
//  MVK++ Phone App
//

import Foundation

/// A link into the web app: a universal link (`https://mvk.futozs.hu/?stop=SP12#multistop`,
/// `/kijelzo?m=SP1,SP2`) or the relative `url` of a push. Port of the web's
/// `lib/deepLink.ts` `parseLink`.
enum WebLink: Equatable {
    /// The shell: a tab from the hash and a stop from `?stop=`. A stop
    /// without a tab opens the Figyelő, where the stop is put.
    case app(tab: AppTab?, stopId: String?)
    case kiosk([String])

    static let origin = URL(string: "https://mvk.futozs.hu")

    /// A push's `url` is relative to the web app (`/?stop=SP12#multistop`).
    static func resolve(_ string: String) -> URL? {
        guard let url = URL(string: string, relativeTo: origin)?.absoluteURL, WebLink(url: url) != nil else { return nil }
        return url
    }

    init?(url: URL) {
        guard url.scheme == "https", url.host == Self.origin?.host else { return nil }
        switch url.path {
        case "", "/":
            let stop = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "stop" }?.value
            let stopId = stop.flatMap { Self.isStopId($0) ? $0 : nil }
            let tab = url.fragment.flatMap(AppTab.init(rawValue:)) ?? (stopId != nil ? .multistop : nil)
            self = .app(tab: tab, stopId: stopId)
        case "/kijelzo", "/kijelzo/":
            self = .kiosk(DeepLink.kioskStops(url))
        default:
            return nil
        }
    }

    /// Same rule as the server (`packages/api/src/push.ts`): `^[\w:.-]{1,32}$`.
    private static func isStopId(_ value: String) -> Bool {
        value.wholeMatch(of: /[A-Za-z0-9_:.\-]{1,32}/) != nil
    }
}
