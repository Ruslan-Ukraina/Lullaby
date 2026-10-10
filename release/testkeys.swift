// Lullaby's TEST keys, for dry runs of the release workflows (Phase 6).
//
//     swift release/testkeys.swift <release|sparkle> [<private key file>]
//
// Each key is derived from a fixed, public phrase, so anyone can rebuild it: it
// proves nothing and is meant to prove nothing. A release build refuses both
// public keys (release/test-public-keys.txt, TestKeys.swift and `make app
// NP_BUILD_KIND=release`), so a dry run can never be mistaken for a release.
//
// With a file argument the private key goes there (mode 0600, never over an
// existing file), as base64 of the 32-byte seed: the format release/sign.swift and
// Sparkle's sign_update/generate_appcast (--ed-key-file) both read. The public key
// is printed either way.

import CryptoKit
import Foundation

let names = ["release", "sparkle"]
let arguments = Array(CommandLine.arguments.dropFirst())
guard (1...2).contains(arguments.count), names.contains(arguments[0]) else {
    FileHandle.standardError.write(Data("usage: swift release/testkeys.swift <release|sparkle> [<private key file>]\n".utf8))
    exit(2)
}
// The phrase keeps the project's old name: the keys derived from it sign the bridge
// the app carries (R74), and a new phrase would be new keys.
let phrase = "NotProton TEST \(arguments[0]) key. Public on purpose; release builds refuse it."
let seed = Data(SHA256.hash(data: Data(phrase.utf8)))
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
if arguments.count == 2 {
    let path = arguments[1]
    guard !FileManager.default.fileExists(atPath: path) else {
        FileHandle.standardError.write(Data("\(path) exists; refusing to overwrite a key\n".utf8))
        exit(1)
    }
    guard FileManager.default.createFile(
        atPath: path, contents: Data((seed.base64EncodedString() + "\n").utf8),
        attributes: [.posixPermissions: 0o600])
    else {
        FileHandle.standardError.write(Data("\(path): cannot write\n".utf8))
        exit(1)
    }
}
print(key.publicKey.rawRepresentation.base64EncodedString())
