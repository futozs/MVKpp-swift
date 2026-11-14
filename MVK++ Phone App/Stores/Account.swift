//
//  Account.swift
//  MVK++ Phone App
//

import AuthenticationServices
import Foundation
import Security
import UIKit

/// The signed-in account on this device (web `mvk_account`). The session
/// token is device-bound: it lives in the Keychain and never travels with
/// cloud sync.
struct AccountSession: Codable, Equatable {
    let email: String
    let sessionToken: String

    private static let service = "hu.futozs.mvk.account"
    private static let account = "session"

    @MainActor static var current: AccountSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode(AccountSession.self, from: data),
              !session.email.isEmpty, !session.sessionToken.isEmpty
        else { return nil }
        return session
    }

    @MainActor static func store(_ session: AccountSession?) {
        SecItemDelete(baseQuery as CFDictionary)
        if let session, let data = try? JSONEncoder().encode(session) {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
        NotificationCenter.default.post(name: .mvkSessionChange, object: nil)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension Notification.Name {
    /// Sign-in or sign-out (web `mvk-session-change`).
    static let mvkSessionChange = Notification.Name("mvk-session-change")
}

struct BackupStatus: Decodable {
    let email: String
    let lastBackupAt: Double?
    let bytes: Int
    let credentialCount: Int
}

/// Passwordless account + cloud sync over passkeys (web `lib/account.ts`).
/// The relying party is `mvk.futozs.hu`, the same as the web app's, so one
/// passkey signs in on both.
@MainActor
enum AccountService {
    static let relyingParty = "mvk.futozs.hu"
    private static let origin = "https://mvk.futozs.hu"

    enum Failure: Error { case reason(String) }

    // MARK: - HTTP

    /// Some responses arrive empty or broken with a 2xx after a cold start on
    /// a weak connection; an invalid body is an error, retried once quietly.
    private static func postJSON(_ path: String, body: [String: Any], session: AccountSession? = nil, allowRetry: Bool = true) async -> Result<[String: Any], Failure> {
        do {
            var request = URLRequest(url: try APIClient.shared.url(path: path))
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // The server derives the RP ID and the expected origin from this.
            request.setValue(origin, forHTTPHeaderField: "Origin")
            if let session { request.setValue(session.sessionToken, forHTTPHeaderField: "X-Account-Session") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await APIClient.shared.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard (200..<300).contains(status) else {
                return .failure(.reason(object?["error"] as? String ?? "HTTP \(status)"))
            }
            guard let object else {
                if allowRetry { return await postJSON(path, body: body, session: session, allowRetry: false) }
                return .failure(.reason("A szerver érvénytelen választ adott — próbáld újra."))
            }
            return .success(object)
        } catch {
            return .failure(.reason(error.localizedDescription))
        }
    }

    private static func sessionFrom(_ object: [String: Any]) -> AccountSession? {
        guard let email = object["email"] as? String, let token = object["sessionToken"] as? String else { return nil }
        return AccountSession(email: email, sessionToken: token)
    }

    // MARK: - Ceremonies

    /// A new account with a new passkey. Fails when the address already has one.
    static func register(email: String) async -> Result<AccountSession, Failure> {
        let options: [String: Any]
        switch await postJSON("/account/passkey/register-options", body: ["email": email]) {
        case .failure(let failure): return .failure(failure)
        case .success(let object): options = object["options"] as? [String: Any] ?? [:]
        }
        let credential: [String: Any]
        switch await PasskeyCeremony.register(options: options) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): credential = value
        }
        switch await postJSON("/account/passkey/register-verify", body: ["email": email, "response": credential]) {
        case .failure(let failure): return .failure(failure)
        case .success(let object):
            guard let session = sessionFrom(object) else { return .failure(.reason("A szerver érvénytelen választ adott — próbáld újra.")) }
            AccountSession.store(session)
            return .success(session)
        }
    }

    /// Sign-in to an existing account with one of its passkeys.
    static func login(email: String) async -> Result<AccountSession, Failure> {
        let options: [String: Any]
        switch await postJSON("/account/passkey/login-options", body: ["email": email]) {
        case .failure(let failure): return .failure(failure)
        case .success(let object): options = object["options"] as? [String: Any] ?? [:]
        }
        let credential: [String: Any]
        switch await PasskeyCeremony.assert(options: options) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): credential = value
        }
        switch await postJSON("/account/passkey/login-verify", body: ["email": email, "response": credential]) {
        case .failure(let failure): return .failure(failure)
        case .success(let object):
            guard let session = sessionFrom(object) else { return .failure(.reason("A szerver érvénytelen választ adott — próbáld újra.")) }
            AccountSession.store(session)
            return .success(session)
        }
    }

    /// One more passkey (another device) for the signed-in account.
    static func addPasskey() async -> Result<Void, Failure> {
        guard let session = AccountSession.current else { return .failure(.reason("Nincs érvényes munkamenet ezen az eszközön.")) }
        let options: [String: Any]
        switch await postJSON("/account/passkey/add-options", body: [:], session: session) {
        case .failure(let failure): return .failure(failure)
        case .success(let object): options = object["options"] as? [String: Any] ?? [:]
        }
        let credential: [String: Any]
        switch await PasskeyCeremony.register(options: options) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): credential = value
        }
        switch await postJSON("/account/passkey/add-verify", body: ["response": credential], session: session) {
        case .failure(let failure): return .failure(failure)
        case .success: return .success(())
        }
    }

    /// Signs out here and invalidates the session on the server too.
    static func logout() async {
        let session = AccountSession.current
        AccountSession.store(nil)
        guard let session, let url = try? APIClient.shared.url(path: "/account/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(session.sessionToken, forHTTPHeaderField: "X-Account-Session")
        _ = try? await APIClient.shared.session.data(for: request)
    }

    static func status() async -> Result<BackupStatus, Failure> {
        guard let session = AccountSession.current else { return .failure(.reason("Nincs beállított fiók ezen az eszközön.")) }
        do {
            var request = URLRequest(url: try APIClient.shared.url(path: "/account/status"))
            request.setValue(session.sessionToken, forHTTPHeaderField: "X-Account-Session")
            let (data, response) = try await APIClient.shared.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                return .failure(.reason(object?["error"] as? String ?? "HTTP \(status)"))
            }
            return .success(try JSONDecoder().decode(BackupStatus.self, from: data))
        } catch {
            return .failure(.reason(error.localizedDescription))
        }
    }
}

// MARK: - Passkey ceremony

/// Runs the platform passkey sheet and returns the credential in the JSON
/// shape `@simplewebauthn/browser` would post, so the server verifies a
/// native passkey exactly like a browser one.
@MainActor
private final class PasskeyCeremony: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<Result<[String: Any], AccountService.Failure>, Never>?
    private static var active: PasskeyCeremony?

    static func register(options: [String: Any]) async -> Result<[String: Any], AccountService.Failure> {
        guard let challenge = (options["challenge"] as? String).flatMap(Data.init(base64URL:)),
              let user = options["user"] as? [String: Any],
              let userId = (user["id"] as? String).flatMap(Data.init(base64URL:)),
              let name = user["name"] as? String
        else { return .failure(.reason("A szerver érvénytelen választ adott — próbáld újra.")) }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: AccountService.relyingParty)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userId)
        if let exclude = options["excludeCredentials"] as? [[String: Any]] {
            request.excludedCredentials = exclude.compactMap { ($0["id"] as? String).flatMap(Data.init(base64URL:)) }
                .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        return await run(request)
    }

    static func assert(options: [String: Any]) async -> Result<[String: Any], AccountService.Failure> {
        guard let challenge = (options["challenge"] as? String).flatMap(Data.init(base64URL:)) else {
            return .failure(.reason("A szerver érvénytelen választ adott — próbáld újra."))
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: AccountService.relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if let allow = options["allowCredentials"] as? [[String: Any]] {
            request.allowedCredentials = allow.compactMap { ($0["id"] as? String).flatMap(Data.init(base64URL:)) }
                .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        return await run(request)
    }

    private static func run(_ request: ASAuthorizationRequest) async -> Result<[String: Any], AccountService.Failure> {
        let ceremony = PasskeyCeremony()
        active = ceremony
        defer { active = nil }
        return await withCheckedContinuation { continuation in
            ceremony.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = ceremony
            controller.presentationContextProvider = ceremony
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<[String: Any], AccountService.Failure>) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            let id = registration.credentialID.base64URL
            var response: [String: Any] = [
                "clientDataJSON": registration.rawClientDataJSON.base64URL,
                "transports": ["internal", "hybrid"],
            ]
            if let attestation = registration.rawAttestationObject { response["attestationObject"] = attestation.base64URL }
            finish(.success([
                "id": id, "rawId": id, "type": "public-key", "response": response,
                "clientExtensionResults": [String: Any](), "authenticatorAttachment": "platform",
            ]))
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            let id = assertion.credentialID.base64URL
            var response: [String: Any] = [
                "clientDataJSON": assertion.rawClientDataJSON.base64URL,
                "authenticatorData": assertion.rawAuthenticatorData.base64URL,
                "signature": assertion.signature.base64URL,
            ]
            if !assertion.userID.isEmpty { response["userHandle"] = assertion.userID.base64URL }
            finish(.success([
                "id": id, "rawId": id, "type": "public-key", "response": response,
                "clientExtensionResults": [String: Any](), "authenticatorAttachment": "platform",
            ]))
        } else {
            finish(.failure(.reason("Ismeretlen hiba.")))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        switch code {
        case .canceled:
            finish(.failure(.reason("Megszakítva vagy időtúllépés.")))
        case .matchedExcludedCredential:
            finish(.failure(.reason("Ez a passkey már regisztrálva van ezen az eszközön.")))
        default:
            finish(.failure(.reason(error.localizedDescription)))
        }
    }
}

extension Data {
    init?(base64URL: String) {
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
