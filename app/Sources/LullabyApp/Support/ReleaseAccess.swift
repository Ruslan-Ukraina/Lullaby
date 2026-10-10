// How Lullaby downloads its own releases (ROADMAP §3, DECISIONS P6-12).
//
//   public   plain https from github.com/<repo>/releases/download/<tag>/<file>,
//            the addresses the manifests carry
//   private  the same addresses, resolved through GitHub's API with a read-only
//            token: GET /repos/<repo>/releases/tags/<tag> names the asset, and
//            GET /repos/<repo>/releases/assets/<id> with Accept: application/octet-stream
//            serves it. A private repository's download links need a signed-in
//            browser, so the token cannot go to them directly.
// The token lives in the login Keychain, never in a file, a log or Info.plist.
// What the manifests say and how their signatures are checked does not change.

import Foundation
import Security

enum ReleaseAccess: Equatable, Sendable {
    case `public`
    case `private`(repository: String, token: String)

    static let infoKey = "LBReleaseAccess"
    static let repositoryKey = "LBReleaseRepository"
    static let manifestTagKey = "LBReleaseManifestTag"

    var isPrivate: Bool { if case .private = self { true } else { false } }

    static let needsToken =
        "Lullaby's releases are private and this Mac has no access token for them. Add it in ⚙︎ → Access Token…"
}

/// The read-only token for a private release repository, in the login Keychain.
enum ReleaseToken {
    static let service = "com.ruslanukraina.Lullaby.release-token"

    static func read(repository: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: repository,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    @discardableResult
    static func save(_ token: String, repository: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        remove(repository: repository)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: repository,
            kSecAttrLabel as String: "Lullaby release access (\(repository))",
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let saved = SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        AppLog.note("release access: token for \(repository) \(saved ? "saved" : "not saved") in the Keychain")
        return saved
    }

    /// What GitHub says about a token before it is kept: it must list the releases of
    /// `repository`, which takes Contents: Read (a fine-grained token's Metadata alone
    /// would pass a plain repository query). The token goes to api.github.com only.
    enum Check: String, Equatable, Sendable {
        case works, rejected, noAccess, unreachable
    }

    typealias StatusOf = @Sendable (URLRequest) async throws -> Int

    static func check(_ token: String, repository: String, status: StatusOf = liveStatus) async -> Check {
        let path = "repos/\(repository)/releases"
        var request = URLRequest(url: GitHubAssetTransport.api.appending(path: path)
            .appending(queryItems: [URLQueryItem(name: "per_page", value: "1")]))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        do {
            switch try await status(request) {
            case 200: return .works
            case 401: return .rejected
            case 403, 404: return .noAccess
            default: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }

    static let liveStatus: StatusOf = { request in
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    static func remove(repository: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: repository,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Requests with headers, the part of a transport the private mode needs.
protocol RequestTransport: Sendable {
    func fetch(_ request: URLRequest, limit: Int) async throws -> Data
    func download(_ request: URLRequest, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// A release asset of a private repository, through GitHub's API. URLs outside the
/// feed (Dormison, Valve) go out as they are.
struct GitHubAssetTransport: EngineTransport {
    static let api = URL(string: "https://api.github.com/")!

    let base: URL
    let repository: String
    let token: String
    var client: any RequestTransport = URLSessionEngineTransport()
    private let assets = AssetIndex()

    init(base: URL, repository: String, token: String, client: any RequestTransport = URLSessionEngineTransport()) {
        self.base = base
        self.repository = repository
        self.token = token
        self.client = client
    }

    /// <base><tag>/<file> -> (tag, file); nil for anything else.
    func asset(of url: URL) -> (tag: String, file: String)? {
        let prefix = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        let text = url.absoluteString
        guard text.hasPrefix(prefix) else { return nil }
        let parts = text.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty, parts[0] != "..", parts[1] != ".." else {
            return nil
        }
        return (String(parts[0]).removingPercentEncoding ?? String(parts[0]),
                String(parts[1]).removingPercentEncoding ?? String(parts[1]))
    }

    func apiRequest(_ path: String, accept: String) -> URLRequest {
        apiRequest(url: Self.api.appending(path: path), accept: accept)
    }

    func apiRequest(url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// The API address of a release asset, what Sparkle and the downloads use.
    func assetURL(tag: String, file: String) async throws -> URL {
        if let id = await assets.id(tag: tag, file: file) {
            return Self.api.appending(path: "repos/\(repository)/releases/assets/\(id)")
        }
        let tagPath = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let data = try await client.fetch(
            apiRequest("repos/\(repository)/releases/tags/\(tagPath)", accept: "application/vnd.github+json"),
            limit: 4 << 20)
        guard let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = release["assets"] as? [[String: Any]]
        else { throw TransportFailure(detail: "GitHub's answer for the release \(tag) is not a release.") }
        var found: [String: Int] = [:]
        for item in list {
            if let name = item["name"] as? String, let id = (item["id"] as? NSNumber)?.intValue { found[name] = id }
        }
        await assets.store(tag: tag, found)
        guard let id = found[file] else {
            throw TransportFailure(detail: "\(file) is not in the release \(tag).")
        }
        return Self.api.appending(path: "repos/\(repository)/releases/assets/\(id)")
    }

    private func request(for url: URL) async throws -> URLRequest {
        guard let (tag, file) = asset(of: url) else { return URLRequest(url: url) }
        var request = apiRequest(url: try await assetURL(tag: tag, file: file), accept: "application/octet-stream")
        request.timeoutInterval = 60
        return request
    }

    func fetch(_ url: URL, limit: Int) async throws -> Data {
        try await client.fetch(try await request(for: url), limit: limit)
    }

    func download(_ url: URL, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await client.download(try await request(for: url), to: part, progress: progress)
    }

    /// Asset ids per tag, for one operation: a re-upload gets a new id.
    private actor AssetIndex {
        var byTag: [String: [String: Int]] = [:]
        func id(tag: String, file: String) -> Int? { byTag[tag]?[file] }
        func store(tag: String, _ found: [String: Int]) { byTag[tag] = found }
    }
}

/// A redirect to another host (GitHub hands asset downloads to its storage) loses the
/// Authorization header: the token is for GitHub, and the storage rejects a second
/// credential next to its signed URL.
enum RedirectPolicy {
    static func follow(_ redirect: URLRequest, from original: URLRequest?) -> URLRequest {
        var next = redirect
        let from = original?.url?.host()?.lowercased()
        let to = redirect.url?.host()?.lowercased()
        if from != to { next.setValue(nil, forHTTPHeaderField: "Authorization") }
        return next
    }
}
