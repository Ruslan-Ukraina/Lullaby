// Creates an Ed25519 key pair for Lullaby's release feed.
//
//     swift release/keygen.swift <private key file>
//
// Writes the base64 private key to the file (mode 0600, never over an existing
// file) and prints the public key: that goes into NPReleasePublicKey of the app's
// Info.plist (make app NP_RELEASE_KEY=…), the private key into a GitHub secret.
// The production key is made once, by the owner, in Phase 6 (docs/RELEASING.md).
// Tests make their own throwaway keys and never use this file.

import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift release/keygen.swift <private key file>\n".utf8))
    exit(2)
}
let path = CommandLine.arguments[1]
guard !FileManager.default.fileExists(atPath: path) else {
    FileHandle.standardError.write(Data("\(path) exists; refusing to overwrite a key\n".utf8))
    exit(1)
}
let key = Curve25519.Signing.PrivateKey()
guard FileManager.default.createFile(
    atPath: path, contents: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8),
    attributes: [.posixPermissions: 0o600])
else {
    FileHandle.standardError.write(Data("\(path): cannot write\n".utf8))
    exit(1)
}
print("private key written to \(path) (keep it out of the repository)")
print("public key  \(key.publicKey.rawRepresentation.base64EncodedString())")
