// NotProton's own release feed (Phase 5): the signed bridge-manifest.json and
// signatures-manifest.json in the releases of the fork, and the Ed25519 key that
// signs them. Both come from Info.plist, as Sparkle's SUFeedURL and SUPublicEDKey
// do: NPReleaseFeedURL and NPReleasePublicKey. The release key is created in
// Phase 6 (docs/RELEASING.md); until then the key is empty, the feed is off, and
// the app uses what it carries (bundled bridge and signatures).
//
// A document is trusted only after its signature checks out over the exact bytes.
// Its `serial` must not go down: an older signed manifest replayed by a mirror is
// refused. The last accepted copy is kept with its .sig in notproton/manifests and
// verified again every time it is read.

import CryptoKit
import Foundation

struct ReleaseFeed: Sendable {
    static let urlKey = "NPReleaseFeedURL"
    static let keyKey = "NPReleasePublicKey"
    static let step = "Check NotProton's releases"

    /// Ends with "/". Assets are <base><tag>/<file>, as GitHub serves release downloads.
    let base: URL
    let key: Curve25519.Signing.PublicKey

    enum Setup: Sendable {
        case ready(ReleaseFeed)
        /// Why there is no feed, in words for Status.
        case off(String)
    }

    static let noKey =
        "This build of NotProton has no release key, so it uses the bridge and signatures it carries."

    /// From the app's Info.plist (Bundle.main): what a release build carries.
    static var configured: Setup {
        setup(url: Bundle.main.object(forInfoDictionaryKey: urlKey) as? String,
              key: Bundle.main.object(forInfoDictionaryKey: keyKey) as? String,
              kind: .current)
    }

    /// A release build takes neither a TEST key (BuildKind.swift) nor a feed other than https.
    static func setup(url: String?, key: String?, kind: BuildKind = .dev) -> Setup {
        let keyText = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyText.isEmpty else { return .off(noKey) }
        guard let raw = Data(base64Encoded: keyText), raw.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return .off("The release key in this build is not a valid Ed25519 public key.") }
        if kind == .release, TestKeys.isTestKey(keyText) {
            AppLog.note("release feed: off, this release build carries a TEST release key")
            return .off(TestKeys.refused)
        }
        guard var text = url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .off("This build of NotProton names no release feed.")
        }
        if !text.hasSuffix("/") { text += "/" }
        let schemes = kind == .release ? ["https"] : ["https", "file"]
        guard let base = URL(string: text), schemes.contains(base.scheme?.lowercased() ?? ""),
              base.user == nil, base.password == nil, base.query == nil
        else { return .off("The release feed address in this build is not usable.") }
        return .ready(ReleaseFeed(base: base, key: publicKey))
    }

    func asset(_ tag: String, _ file: String) -> URL {
        base.appending(path: "\(tag)/\(file)")
    }

    var bridgeManifestURL: URL { asset("manifest", "bridge-manifest.json") }
    var signaturesManifestURL: URL { asset("manifest", "signatures-manifest.json") }

    /// Only files under the feed: same scheme and host, path below the base, no "..".
    func allows(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return url.scheme?.lowercased() == base.scheme?.lowercased()
            && url.host()?.lowercased() == base.host()?.lowercased()
            && url.user == nil && url.password == nil && url.query == nil
            && path.hasPrefix(base.path(percentEncoded: false))
            && !path.split(separator: "/").contains("..")
    }
}

/// A JSON document signed with the release key, as fetched or as cached.
struct SignedDocument: Sendable {
    let data: Data
    let signature: Data
    let serial: Int

    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Signature first, then JSON with an integer `serial` and the expected `schema`.
    static func verify(
        _ data: Data, signature: Data, key: Curve25519.Signing.PublicKey, name: String, schema: Int
    ) throws -> SignedDocument {
        guard EngineSignature.isValid(data, signatureFile: signature, key: key) else {
            throw StepFailure(
                step: ReleaseFeed.step,
                detail: "\(name) does not carry NotProton's release signature, so NotProton refused it.")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["schema"] as? Int == schema, let serial = json["serial"] as? Int, serial > 0
        else {
            throw StepFailure(step: ReleaseFeed.step, detail: "\(name) is signed but unusable (schema or serial).")
        }
        return SignedDocument(data: data, signature: signature, serial: serial)
    }

    /// The cached copy, if it is still there and still verifies with `key`.
    static func cached(
        _ name: String, in directory: URL, key: Curve25519.Signing.PublicKey, schema: Int
    ) -> SignedDocument? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)),
              let signature = try? Data(contentsOf: directory.appending(path: name + ".sig"))
        else { return nil }
        return try? verify(data, signature: signature, key: key, name: name, schema: schema)
    }

    /// Fetches `url` and its .sig, verifies, refuses a serial lower than the cached
    /// copy's, and caches what passed. Network trouble throws `offline`.
    static func fetch(
        _ url: URL, feed: ReleaseFeed, transport: any EngineTransport, cache directory: URL, schema: Int
    ) async throws -> SignedDocument {
        let name = url.lastPathComponent
        let body: Data, signature: Data
        do {
            body = try await transport.fetch(url, limit: 4 << 20)
            signature = try await transport.fetch(EngineSignature.signatureURL(for: url), limit: 1024)
        } catch {
            AppLog.note("release feed: \(name) fetch failed: \(error.localizedDescription)")
            throw StepFailure(step: ReleaseFeed.step, detail: EngineUpdater.offline)
        }
        let document: SignedDocument
        do {
            document = try verify(body, signature: signature, key: feed.key, name: name, schema: schema)
        } catch {
            AppLog.note("release feed: \(name) refused: \(error.localizedDescription)")
            throw error
        }
        if let known = cached(name, in: directory, key: feed.key, schema: schema), document.serial < known.serial {
            AppLog.note("release feed: \(name) serial \(document.serial) is older than the cached \(known.serial)")
            throw StepFailure(
                step: ReleaseFeed.step,
                detail: "\(name) is older than the one NotProton already has (serial \(document.serial) < \(known.serial)), so NotProton refused it.")
        }
        try atomicReplace(directory.appending(path: name), with: body, step: ReleaseFeed.step)
        try atomicReplace(directory.appending(path: name + ".sig"), with: signature, step: ReleaseFeed.step)
        AppLog.note("release feed: \(name) verified, serial \(document.serial)")
        return document
    }
}
