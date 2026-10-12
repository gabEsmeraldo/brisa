import CryptoKit
import Foundation

/// LG's private ThinQ v2 API (the one the ThinQ phone app uses).
/// Only used for features the official API doesn't expose, such as Jet mode.
/// Auth: the user signs in on LG's own login page; we keep just the refresh token.
/// Protocol details follow the open-source homebridge-lg-thinq project.
@MainActor
final class LegacyThinQ {
    enum Failure: LocalizedError {
        case notLinked, badResponse, api(String)
        var errorDescription: String? {
            switch self {
            case .notLinked: return L("LG account not linked")
            case .badResponse: return L("Unexpected response from LG")
            case .api(let message): return message
            }
        }
    }

    struct Device { let id: String; let alias: String; let model: String; let snapshot: [String: Any] }

    private static let gatewayURL = URL(string: "https://route.lgthinq.com:46030/v1/service/application/gateway-uri")!
    private static let clientID = "LGAO221A02"
    private static let oauthSecret = "c053c2a6ddeb7ad97cb0eed0dcb31cf8"
    private static let apiKey = "VGhpblEyLjAgU0VSVklDRQ=="
    private static let apiClientID = "c713ea8e50f657534ff8b9d373dfebfc2ed70b88285c26b8ade49868c0b164d9"
    private static let applicationKey = "6V1V8H2BN5P9ZQGOI5DAQ92YZBDO3EK9"
    static let redirectScheme = "lgaccount.lgsmartthinq"
    private static let redirectURI = "lgaccount.lgsmartthinq:/"

    let country: String
    let language: String
    private var gateway: [String: String]?
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var userNo: String?

    private var refreshToken: String? {
        get { Keychain.read(account: "thinq-refresh") }
        set { Keychain.save(newValue ?? "", account: "thinq-refresh") }
    }
    private var oauthBase: String {
        get { UserDefaults.standard.string(forKey: "lgOAuthBase") ?? "https://\(country.lowercased()).lgeapi.com/" }
        set { UserDefaults.standard.set(newValue, forKey: "lgOAuthBase") }
    }

    var isLinked: Bool { refreshToken != nil }

    init(country: String, language: String) {
        self.country = country
        self.language = language
    }

    // MARK: Login

    /// LG's hosted sign-in page; it redirects to `lgaccount.lgsmartthinq:/?code=…` on success.
    func loginURL() async throws -> URL {
        let gw = try await loadGateway()
        let params: [(String, String)] = [
            ("country", country), ("language", language), ("client_id", Self.clientID),
            ("svc_list", "SVC202"), ("svc_integrated", "Y"), ("redirect_uri", Self.redirectURI),
            ("show_thirdparty_login", "LGE,MYLG,GGL,AMZ,FBK,APPL"), ("division", "ha:T20"),
            ("callback_url", Self.redirectURI), ("oauth2State", "12345"), ("show_select_country", "N"),
        ]
        guard let base = gw["empSpxUri"], let url = URL(string: base + "/login/signIn?" + Self.query(params))
        else { throw Failure.badResponse }
        return url
    }

    /// Exchanges the code from the login redirect for tokens.
    func completeLogin(redirect: URL) async throws {
        let items = URLComponents(url: redirect, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            // returnCode 910 (confirm_ggl/apple/…): LG asks the phone app to run its native
            // social sign-in, which a desktop app can't do.
            if items.first(where: { $0.name == "returnCode" })?.value == "910" {
                throw Failure.api(L("Google/Apple sign-in only works inside LG's phone app. Sign in with your LG email and password instead."))
            }
            // LG reports sign-in problems as query parameters on the redirect.
            let reason = items.first(where: { ["error", "error_description", "message", "returnMsg"].contains($0.name) })?.value
            throw Failure.api(reason ?? "no code in redirect")
        }
        if let backend = items.first(where: { $0.name == "oauth2_backend_url" })?.value, !backend.isEmpty {
            oauthBase = backend.hasSuffix("/") ? backend : backend + "/"
        }
        let token = try await oauthToken([("code", code), ("grant_type", "authorization_code"),
                                          ("redirect_uri", Self.redirectURI)])
        guard let refresh = token["refresh_token"] as? String else { throw Failure.badResponse }
        refreshToken = refresh
        if let backend = token["oauth2_backend_url"] as? String, !backend.isEmpty { oauthBase = backend }
        storeAccess(token)
        userNo = nil
    }

    func signOut() {
        refreshToken = nil
        accessToken = nil
        userNo = nil
    }

    // MARK: Devices

    func devices() async throws -> [Device] {
        let homes = try await get("service/homes")
        let items = (homes as? [String: Any])?["item"] as? [[String: Any]] ?? []
        var result: [Device] = []
        for home in items {
            guard let homeID = home["homeId"] as? String else { continue }
            let detail = try await get("service/homes/\(homeID)") as? [String: Any]
            for d in detail?["devices"] as? [[String: Any]] ?? [] {
                guard let id = d["deviceId"] as? String else { continue }
                result.append(Device(id: id, alias: d["alias"] as? String ?? "",
                                     model: d["modelName"] as? String ?? "",
                                     snapshot: d["snapshot"] as? [String: Any] ?? [:]))
            }
        }
        return result
    }

    func snapshot(_ id: String) async throws -> [String: Any] {
        (try await get("service/devices/\(id)") as? [String: Any])?["snapshot"] as? [String: Any] ?? [:]
    }

    func set(_ id: String, key: String, value: Any) async throws {
        _ = try await request("service/devices/\(id)/control-sync", body: [
            "ctrlKey": "basicCtrl", "command": "Set", "dataKey": key, "dataValue": value,
        ])
    }

    // MARK: Transport

    private func get(_ path: String) async throws -> Any? { try await request(path, body: nil) }

    private func request(_ path: String, body: [String: Any]?, retried: Bool = false) async throws -> Any? {
        let gw = try await loadGateway()
        guard let base = gw["thinq2Uri"], let url = URL(string: base + "/" + path) else { throw Failure.badResponse }
        let token = try await validAccessToken()
        if userNo == nil { userNo = try await fetchUserNo(token) }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        baseHeaders().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue(token, forHTTPHeaderField: "x-emp-token")
        req.setValue(userNo, forHTTPHeaderField: "x-user-no")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.badResponse }
        let code = json["resultCode"] as? String ?? ""
        if code == "0000" { return json["result"] }
        // 0102: access token expired.
        if code == "0102" && !retried {
            accessToken = nil
            return try await request(path, body: body, retried: true)
        }
        throw Failure.api(code)
    }

    private func baseHeaders() -> [String: String] {
        [
            "x-api-key": Self.apiKey,
            "x-client-id": Self.apiClientID,
            "x-thinq-app-ver": "3.6.1200",
            "x-thinq-app-type": "NUTS",
            "x-thinq-app-level": "PRD",
            "x-thinq-app-os": "ANDROID",
            "x-thinq-app-logintype": "LGE",
            "x-service-code": "SVC202",
            "x-country-code": country,
            "x-language-code": language,
            "x-service-phase": "OP",
            "x-origin": "app-native",
            "x-model-name": "samsung/SM-G930L",
            "x-os-version": "AOS/7.1.2",
            "x-app-version": "LG ThinQ/3.6.12110",
            "x-message-id": Self.randomString(22),
            "user-agent": "okhttp/3.14.9",
            "Accept": "application/json",
        ]
    }

    private func loadGateway() async throws -> [String: String] {
        if let gateway { return gateway }
        var req = URLRequest(url: Self.gatewayURL)
        baseHeaders().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [String: Any] else { throw Failure.badResponse }
        let gw = result.compactMapValues { $0 as? String }
        gateway = gw
        return gw
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, Date() < accessExpiry { return accessToken }
        guard let refresh = refreshToken else { throw Failure.notLinked }
        let token = try await oauthToken([("grant_type", "refresh_token"), ("refresh_token", refresh)])
        storeAccess(token)
        guard let accessToken else { throw Failure.badResponse }
        return accessToken
    }

    private func storeAccess(_ token: [String: Any]) {
        accessToken = token["access_token"] as? String
        let expiresIn = Double(token["expires_in"] as? String ?? "") ?? (token["expires_in"] as? Double) ?? 3600
        accessExpiry = Date().addingTimeInterval(expiresIn - 60)
    }

    /// Signed POST to LG's OAuth token endpoint.
    private func oauthToken(_ params: [(String, String)]) async throws -> [String: Any] {
        let query = Self.query(params)
        let date = Self.rfc2822()
        var req = URLRequest(url: URL(string: oauthBase + "oauth/1.0/oauth2/token")!)
        req.httpMethod = "POST"
        req.httpBody = Data(query.utf8)
        req.setValue("ADR", forHTTPHeaderField: "x-lge-app-os")
        req.setValue(Self.clientID, forHTTPHeaderField: "x-lge-appkey")
        req.setValue(Self.sign("/oauth/1.0/oauth2/token?\(query)\n\(date)"), forHTTPHeaderField: "x-lge-oauth-signature")
        req.setValue(date, forHTTPHeaderField: "x-lge-oauth-date")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if (response as? HTTPURLResponse)?.statusCode == 400 || (response as? HTTPURLResponse)?.statusCode == 401 {
                refreshToken = nil  // refresh token revoked; ask to sign in again
            }
            throw Failure.api(String(data: data, encoding: .utf8)?.prefix(80).description ?? "oauth")
        }
        return json
    }

    private func fetchUserNo(_ token: String) async throws -> String {
        let date = Self.rfc2822()
        var req = URLRequest(url: URL(string: oauthBase + "users/profile")!)
        [
            "Accept": "application/json",
            "Authorization": "Bearer " + token,
            "X-Lge-Svccode": "SVC202",
            "X-Application-Key": Self.applicationKey,
            "lgemp-x-app-key": Self.clientID,
            "X-Device-Type": "M01",
            "X-Device-Platform": "ADR",
            "x-lge-oauth-date": date,
            "x-lge-oauth-signature": Self.sign("/users/profile\n\(date)"),
        ].forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let no = (json?["account"] as? [String: Any])?["userNo"] as? String else { throw Failure.badResponse }
        return no
    }

    // MARK: Helpers

    private static func sign(_ message: String) -> String {
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(oauthSecret.utf8)))
        return Data(mac).base64EncodedString()
    }

    private static func rfc2822() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: Date())
    }

    /// Form encoding matching the `qs` package (RFC 3986 unreserved characters only).
    static func query(_ params: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $1)" }
            .joined(separator: "&")
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}
