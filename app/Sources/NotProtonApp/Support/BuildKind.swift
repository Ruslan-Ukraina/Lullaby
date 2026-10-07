// What kind of build this is and which keys it may never trust (Phase 6).
//
// NPBuildKind in Info.plist comes from `make app NP_BUILD_KIND=…`:
//   release  the release workflow, from a v* tag, with the owner's keys
//   test     a dry run of the release workflows, with the TEST keys
//   dev      anything else, a local `make app` included (the default)
// A release build refuses the TEST keys outright, both NotProton's release key
// and Sparkle's: their private halves are derived from a public phrase
// (release/testkeys.swift), so anyone can sign with them.

import Foundation

enum BuildKind: String, Sendable, CaseIterable {
    case release, test, dev

    static let infoKey = "NPBuildKind"

    static var current: BuildKind {
        BuildKind(rawValue: (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String) ?? "") ?? .dev
    }
}

enum TestKeys {
    /// The public halves of every TEST key, as in release/test-public-keys.txt
    /// (TestKeysTests keeps the two the same).
    static let publicKeys: Set<String> = [
        // release/testkeys.swift release
        "SmS/CorkBY2r0YPdJpEC1SU8XqyicnnnWEw5VKnnMyo=",
        // release/testkeys.swift sparkle
        "FG7qphnldCCsd2Be1KkWe+W8jLocglLjcfpTl6bc0lE=",
        // the Phase 5 test feed on the owner's Mac (scratch/testfeed, DECISIONS P5-7)
        "dXwoMYHG7v/BEEHtb/ifHpQrAz397JPWlea0Np7rVWk=",
    ]

    static func isTestKey(_ base64: String) -> Bool {
        publicKeys.contains(base64.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static let refused =
        "This release build carries a TEST key, so NotProton refuses it and works with what it carries."
}
