// Signs release files with NotProton's Ed25519 release key (Phase 5/6).
//
//     swift release/sign.swift <private key file> <file>...
//
// Writes <file>.sig next to each file: the base64 of the raw 64-byte signature over
// the file's bytes, the format Dormison uses and the app checks (EngineSignature).
// The key file holds the base64 of the 32-byte private key (release/keygen.swift).
// In CI it comes from a GitHub secret and never touches the repository.

import CryptoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2, let keyPath = arguments.first else {
    FileHandle.standardError.write(Data("usage: swift release/sign.swift <private key file> <file>...\n".utf8))
    exit(2)
}
guard let text = try? String(contentsOfFile: keyPath, encoding: .utf8),
      let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else {
    FileHandle.standardError.write(Data("\(keyPath): not a base64 Ed25519 private key\n".utf8))
    exit(1)
}
print("public key \(key.publicKey.rawRepresentation.base64EncodedString())")
for path in arguments.dropFirst() {
    guard let data = FileManager.default.contents(atPath: path) else {
        FileHandle.standardError.write(Data("\(path): cannot read\n".utf8))
        exit(1)
    }
    let signature = try key.signature(for: data)
    guard key.publicKey.isValidSignature(signature, for: data) else { exit(1) }
    try Data((signature.base64EncodedString() + "\n").utf8).write(to: URL(filePath: path + ".sig"))
    print("signed \(path)")
}
