import Foundation

/// Minimal client for LG's official ThinQ Connect API (Personal Access Token).
/// Mirrors the headers used by LG's own `thinqconnect` SDK.
struct ThinQClient {
    enum Failure: LocalizedError {
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "HTTP \(code): \(body.prefix(160))"
            case .badResponse: return L("Unexpected response from LG")
            }
        }
    }

    /// Public key shipped in LG's open-source SDK; identifies third-party clients, not the user.
    private static let apiKey = "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3"

    let token: String
    let country: String
    let clientID: String

    private var baseURL: URL {
        URL(string: "https://api-\(Self.region(for: country)).lgthinq.com/")!
    }

    static func region(for country: String) -> String {
        let americas: Set<String> = ["AR", "BR", "CA", "CL", "CO", "CR", "DO", "EC", "GT", "HN", "JM",
                                     "MX", "NI", "PA", "PE", "PR", "PY", "SV", "US", "UY", "VE"]
        let asia: Set<String> = ["AU", "CN", "HK", "ID", "IN", "JP", "KR", "MY", "NZ", "PH", "SG", "TH", "TW", "VN"]
        if americas.contains(country) { return "aic" }
        if asia.contains(country) { return "kic" }
        return "eic"
    }

    func devices() async throws -> [[String: Any]] {
        try await request("devices") as? [[String: Any]] ?? []
    }

    func profile(_ id: String) async throws -> [String: Any] {
        try await request("devices/\(id)/profile") as? [String: Any] ?? [:]
    }

    func state(_ id: String) async throws -> [String: Any] {
        try await request("devices/\(id)/state") as? [String: Any] ?? [:]
    }

    func control(_ id: String, _ payload: [String: Any]) async throws {
        _ = try await request("devices/\(id)/control", method: "POST", body: payload)
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any? {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(country, forHTTPHeaderField: "x-country")
        req.setValue(Self.messageID(), forHTTPHeaderField: "x-message-id")
        req.setValue(clientID, forHTTPHeaderField: "x-client-id")
        req.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("OP", forHTTPHeaderField: "x-service-phase")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.setValue("true", forHTTPHeaderField: "x-conditional-control")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if data.isEmpty { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["response"]
    }

    /// 22-char URL-safe base64 of a random UUID, as the SDK generates it.
    private static func messageID() -> String {
        let uuid = UUID().uuid
        let bytes = withUnsafeBytes(of: uuid) { Data($0) }
        return String(bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .dropLast(2))
    }
}
