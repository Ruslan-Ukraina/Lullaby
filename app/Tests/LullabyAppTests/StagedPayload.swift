import Foundation
import Testing

@testable import LullabyApp

/// Whether `make app-payload` staged the payload these tests read: the dylib, the
/// helpers and the bridge. The light CI checks (app.yml) build no bridge and skip
/// them; `make app-tests` after `make app`, and release.yml, run them. With
/// NP_REQUIRE_PAYLOAD=1 (release.yml) they run regardless, so a missing payload
/// fails loudly instead of skipping.
enum StagedPayload {
    static var present: Bool {
        ProcessInfo.processInfo.environment["NP_REQUIRE_PAYLOAD"] == "1"
            || (try? InstallPayload.locate()) != nil
    }

    static let reason: Comment = "make app-payload has not staged the payload (bridge, helpers)"
}
