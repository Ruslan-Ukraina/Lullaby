// Dormison's release manifest (engine.json, schema 2) and the Ed25519 key that
// signs it. Nothing in it is read before the signature checks out, and a release
// is only taken from Dormison's own release assets. Modelled on Sevoflurane's
// Core/Setup/EngineManifest.swift and EngineSignature.swift (MIT).

import CryptoKit
import Foundation

enum EngineChannel: String, CaseIterable, Sendable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }
    var label: String { self == .stable ? "Stable" : "Beta" }

    static let defaultsKey = "engineChannel"

    /// Beta until Dormison has a stable release: the manifest carries a beta alone.
    static var preferred: EngineChannel {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(EngineChannel.init) ?? .beta
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

enum EngineSignature {
    /// Pinned in Sevoflurane's Core/Setup/EngineSignature.swift; the private half
    /// signs every Dormison release (build-macos/publish-engine.sh).
    static let dormisonKeyBase64 = "7uDuIZdCZyobjZcPL12zL+UNOCpHSvLXvVRFHA7bzzA="

    static var dormisonKey: Curve25519.Signing.PublicKey {
        // A constant that decodes: checked by EngineUpdaterTests.
        try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: dormisonKeyBase64)!)
    }

    static let assetPathPrefix = "/kageroumado/dormison/releases/download/"

    static func signatureURL(for asset: URL) -> URL {
        URL(string: asset.absoluteString + ".sig") ?? asset.appendingPathExtension("sig")
    }

    /// https://github.com/kageroumado/dormison/releases/download/… and nothing else.
    static func isDormisonAsset(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host()?.lowercased() == "github.com"
            && url.user == nil && url.password == nil
            && url.path(percentEncoded: false).hasPrefix(assetPathPrefix)
            && !url.path(percentEncoded: false).contains("/../")
    }

    /// `.sig` files are the base64 of a raw 64-byte Ed25519 signature.
    static func isValid(
        _ message: some DataProtocol, signatureFile: Data, key: Curve25519.Signing.PublicKey
    ) -> Bool {
        let text = String(decoding: signatureFile, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: text), signature.count == 64 else { return false }
        return key.isValidSignature(signature, for: message)
    }
}

struct EngineRelease: Sendable, Equatable {
    let channel: EngineChannel
    let version: String
    let url: URL
    let sha256: String
    let sizeBytes: Int64
    let notes: String?
    /// Sevoflurane's app version this release asks for. NotProton's own gate is
    /// the support table (EngineSupport), so this is only logged.
    let minAppVersion: String?

    var displayName: String { EngineStore.displayName(version) }
}

struct EngineManifest: Sendable, Equatable {
    static let url = URL(string: "https://github.com/kageroumado/dormison/releases/download/manifest/engine.json")!
    static let step = "Check for engine updates"

    let releases: [EngineChannel: EngineRelease]

    /// What a Mac on `channel` takes. Stable takes the stable release alone;
    /// beta takes the newer of beta and stable, so a beta the release has
    /// overtaken is passed over (Sevoflurane's rule).
    func release(for channel: EngineChannel) -> EngineRelease? {
        switch channel {
        case .stable:
            return releases[.stable]
        case .beta:
            guard let beta = releases[.beta] else { return releases[.stable] }
            guard let stable = releases[.stable] else { return beta }
            return Self.isOlder(beta.version, than: stable.version) ? stable : beta
        }
    }

    /// Checks the signature over the exact bytes, then decodes. Every release
    /// must point at a Dormison release asset and carry a well-formed digest.
    static func verified(
        _ data: Data, signatureFile: Data, key: Curve25519.Signing.PublicKey = EngineSignature.dormisonKey
    ) throws -> EngineManifest {
        guard EngineSignature.isValid(data, signatureFile: signatureFile, key: key) else {
            throw StepFailure(
                step: step,
                detail: "The engine list does not carry Dormison's signature, so NotProton refused it.")
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> EngineManifest {
        let bad = { (why: String) in StepFailure(step: step, detail: "The engine list is unusable: \(why).") }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw bad("it is not JSON")
        }
        guard let schema = root["schema"] as? Int, (1...2).contains(schema) else {
            throw bad("schema \(String(describing: root["schema"])) is not 1 or 2")
        }
        let channels = root["channels"] as? [String: Any] ?? [:]
        var releases: [EngineChannel: EngineRelease] = [:]
        for (name, value) in channels {
            guard let channel = EngineChannel(rawValue: name) else { continue }
            guard let entry = value as? [String: Any],
                  let version = entry["version"] as? String,
                  let urlText = entry["url"] as? String, let url = URL(string: urlText),
                  let sha = entry["sha256"] as? String,
                  let size = (entry["sizeBytes"] as? NSNumber)?.int64Value
            else { throw bad("channel \(name) is incomplete") }
            guard isVersionName(version) else { throw bad("\(version) is not a Dormison version name") }
            guard EngineSignature.isDormisonAsset(url), url.lastPathComponent.contains(version) else {
                throw bad("\(urlText) is not a Dormison release asset")
            }
            guard isSHA256(sha) else { throw bad("channel \(name) has no valid sha256") }
            guard size > 0 else { throw bad("channel \(name) has no size") }
            releases[channel] = EngineRelease(
                channel: channel, version: version, url: url, sha256: sha.lowercased(), sizeBytes: size,
                notes: entry["notes"] as? String, minAppVersion: entry["minAppVersion"] as? String)
        }
        return EngineManifest(releases: releases)
    }

    /// `dormison-b1`, `dormison-r2`, `dormison-11.0`: one directory name, no path tricks.
    static func isVersionName(_ text: String) -> Bool {
        text.wholeMatch(of: /dormison-[A-Za-z0-9.]+/) != nil && !text.contains("..")
    }

    static func isSHA256(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy(\.isHexDigit)
    }

    /// Digit-aware, with a beta before its release: `dormison-b11` orders as
    /// 11.0 and `dormison-r11` as 11.1 (Sevoflurane's Engine.isOlderVersion).
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        orderingKey(lhs).localizedStandardCompare(orderingKey(rhs)) == .orderedAscending
    }

    private static func orderingKey(_ version: String) -> String {
        guard let match = version.prefixMatch(of: /dormison-([rb])(\d+)/) else { return version }
        let stage = match.1 == "r" ? 1 : 0
        return "dormison-\(match.2).\(stage)" + version[match.range.upperBound...]
    }
}
