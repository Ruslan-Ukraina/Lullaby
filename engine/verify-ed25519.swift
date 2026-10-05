// Checks a detached Ed25519 signature the way Dormison publishes them: the
// .sig file is base64 of the raw 64-byte signature over the exact bytes of
// the file it sits beside. Same rule as Sevoflurane's EngineSignature.swift
// (MIT, Copyright (c) 2026 kageroumado).
//
//   swift engine/verify-ed25519.swift <public key, base64> <file> <file.sig>
//
// Exits 0 on a valid signature, 1 on an invalid one, 2 on bad input.

import CryptoKit
import Foundation

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fail("usage: verify-ed25519.swift <public key base64> <file> <file.sig>", 2)
}

guard let raw = Data(base64Encoded: args[1]), raw.count == 32,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
else { fail("the public key is not 32 bytes of base64", 2) }

guard let sigData = FileManager.default.contents(atPath: args[3]) else {
    fail("cannot read \(args[3])", 2)
}
let sigText = String(decoding: sigData, as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let signature = Data(base64Encoded: sigText), signature.count == 64 else {
    fail("\(args[3]) is not base64 of a 64-byte signature", 2)
}

// The tarball is hundreds of MB, so it is mapped rather than read.
guard let message = try? Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe) else {
    fail("cannot read \(args[2])", 2)
}

if key.isValidSignature(signature, for: message) {
    print("signature valid: \((args[2] as NSString).lastPathComponent)")
    exit(0)
}
fail("SIGNATURE INVALID: \((args[2] as NSString).lastPathComponent)", 1)
