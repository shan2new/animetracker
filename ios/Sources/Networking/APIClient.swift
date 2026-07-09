import Foundation
import os

// Supplies the current bearer token for outgoing requests. Implemented by the auth layer
// (Clerk session token, or a `dev:<clerkId>` token for local DEV_AUTH_BYPASS testing).
protocol TokenProvider: Sendable {
    func currentToken() async -> String?
}

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case http(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .unauthorized: return "You're signed out. Please sign in again."
        case let .http(code, body): return "Server error (\(code)). \(body)"
        case let .decoding(err): return "Couldn't read the server response. \(err.localizedDescription)"
        case let .transport(err): return "Network error. \(err.localizedDescription)"
        }
    }
}

extension CharacterSet {
    /// Characters safe inside a single query VALUE. Starts from `.urlQueryAllowed` and removes
    /// the delimiters it permits (`&` splits parameters, `=` splits key/value, `+` decodes as a
    /// space on the server, `?`/`#` end the component).
    static let strictQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}

// URLSession-backed client implementing every endpoint in the API contract.
final class APIClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProvider
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfig.apiBaseURL,
         tokenProvider: TokenProvider,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Endpoints

    func health() async throws -> OKResponse {
        try await request("/health", auth: false)
    }

    func trending(limit: Int = 30) async throws -> [FranchiseSummary] {
        let res: FranchiseListResponse = try await request("/franchises/trending?limit=\(limit)")
        return res.franchises
    }

    func search(query: String) async throws -> [FranchiseSummary] {
        // .urlQueryAllowed leaves `&`, `+`, and `=` unescaped, which corrupts the q parameter
        // (searching "X & Y" truncated at the ampersand). Escape the value strictly.
        let q = query.addingPercentEncoding(withAllowedCharacters: .strictQueryValueAllowed) ?? ""
        let res: FranchiseListResponse = try await request("/search?q=\(q)")
        return res.franchises
    }

    func franchise(id: String) async throws -> Franchise {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await request("/franchises/\(encoded)")
    }

    func library() async throws -> LibraryResponse {
        try await request("/me/library")
    }

    @discardableResult
    func subscribe(franchiseId: String, status: WatchStatus? = nil) async throws -> OKResponse {
        try await request("/me/subscriptions", method: "POST",
                          body: SubscribeBody(franchiseId: franchiseId, status: status))
    }

    @discardableResult
    func setStatus(franchiseId: String, status: WatchStatus) async throws -> OKResponse {
        let encoded = franchiseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? franchiseId
        return try await request("/me/subscriptions/\(encoded)", method: "PATCH",
                                 body: StatusBody(status: status))
    }

    @discardableResult
    func unsubscribe(franchiseId: String) async throws -> OKResponse {
        let encoded = franchiseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? franchiseId
        return try await request("/me/subscriptions/\(encoded)", method: "DELETE")
    }

    @discardableResult
    func setProgress(mediaId: Int, episodes: Int) async throws -> OKResponse {
        try await request("/me/progress", method: "PUT",
                          body: ProgressBody(mediaId: mediaId, episodes: episodes))
    }

    @discardableResult
    func markOpened() async throws -> OpenedResponse {
        try await request("/me/opened", method: "POST")
    }

    // MARK: - Core request machinery

    private func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        auth: Bool = true
    ) async throws -> Response {
        try await send(path: path, method: method, body: Optional<Data>.none, auth: auth)
    }

    private func request<Response: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        body: Body,
        auth: Bool = true
    ) async throws -> Response {
        let data: Data
        do { data = try encoder.encode(body) }
        catch { throw APIError.decoding(error) }
        return try await send(path: path, method: method, body: data, auth: auth)
    }

    // Failure diagnostics land in the unified log (`log stream --predicate 'subsystem ==
    // "com.anitrack.app"'`) so "the app says unreachable" is attributable to a concrete cause.
    private static let log = Logger(subsystem: "com.anitrack.app", category: "api")

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        auth: Bool
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth {
            if let token = await tokenProvider.currentToken() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                APIClient.log.error("\(method) \(path): no auth token available (signed out or token fetch failed)")
                throw APIError.unauthorized
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            APIClient.log.error("\(method) \(url.absoluteString): transport error: \(error)")
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            APIClient.log.error("\(method) \(path): HTTP \(http.statusCode) (unauthorized)")
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            APIClient.log.error("\(method) \(path): HTTP \(http.statusCode): \(bodyText, privacy: .public)")
            throw APIError.http(http.statusCode, bodyText)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            APIClient.log.error("\(method) \(path): decoding failed: \(error)")
            throw APIError.decoding(error)
        }
    }
}
