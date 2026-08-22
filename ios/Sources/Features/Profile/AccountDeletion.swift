import Foundation

// In-app account deletion — App Store guideline 5.1.1(v). `DELETE /me` on the backend erases the
// account's subscriptions, progress, notifications and the user row itself, in one transaction.
//
// It deliberately does NOT go through `APIClient`. That client is built for reads and for writes
// the app can replay: it retries transport failures and silently refreshes a 401. Both behaviours
// are wrong here. A request the app is not certain reached the server must be REPORTED, not quietly
// repeated, and a session that has expired must be re-authenticated by the user before their
// account is destroyed — not renewed behind a confirmation they gave a minute ago. One attempt,
// one answer, and the answer is shown to the user either way.
enum AccountDeletion {

    /// Why the deletion did not happen, in the words the row prints. Never a status code: the user
    /// is being told whether their account still exists, and "500" does not answer that.
    enum Failure: LocalizedError, Equatable {
        /// There is no credential to send. The account was not touched.
        case notSignedIn
        /// The server answered, and the answer was not "deleted".
        case refused
        /// The request never got an answer. The account may or may not still exist.
        case unreachable

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "You’re signed out. Sign in again to delete your account."
            case .refused: return "Your account couldn’t be deleted. Nothing was changed."
            case .unreachable: return "Couldn’t reach the server. Your account wasn’t deleted."
            }
        }
    }

    /// Sends the deletion. Returns normally only when the server confirmed the erasure.
    ///
    /// `session` is `URLSession.shared` in the app and injectable so the call is exercisable
    /// without a network; `token` is `AuthManager.currentToken`.
    static func deleteAccount(baseURL: URL = AppConfig.apiBaseURL,
                              session: URLSession = .shared,
                              token: () async -> String?) async throws {
        guard let bearer = await token(), !bearer.isEmpty else { throw Failure.notSignedIn }

        var request = URLRequest(url: baseURL.appendingPathComponent("me"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // No body at all: the route rejects a body it does not recognise, and there is nothing an
        // erasure needs to say beyond who is asking.
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.unreachable }
        switch http.statusCode {
        case 200:
            // The route answers `{ "deleted": true }`. A 200 carrying anything else is a proxy or a
            // captive portal answering for the server, and must not be read as a deletion.
            guard let body = try? JSONDecoder().decode(Response.self, from: data), body.deleted else {
                throw Failure.refused
            }
        case 204:
            break
        case 401, 403:
            throw Failure.notSignedIn
        default:
            throw Failure.refused
        }
    }

    private struct Response: Decodable { let deleted: Bool }
}
