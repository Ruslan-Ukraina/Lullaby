import Foundation
import Sparkle

// Sparkle with no window of its own (owner, 11.10): the main window's Update downloads
// and checks the new Lullaby.app, its progress shows in the window, and one system alert
// then asks to restart (MainModel). Sparkle still verifies the EdDSA signature of the
// appcast and the archive; only its UI is replaced.
@MainActor
final class QuietUserDriver: NSObject, SPUUserDriver {
    /// The window's Update is waiting: true once the update is ready to install, false
    /// when there was none.
    private var waiter: CheckedContinuation<Bool, Error>?
    private var progress: (@MainActor (Int64, Int64?) -> Void)?
    private var expected: Int64?
    private var received: Int64 = 0
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?

    var isReadyToRelaunch: Bool { readyReply != nil }

    func begin(progress: @escaping @MainActor (Int64, Int64?) -> Void, waiter: CheckedContinuation<Bool, Error>) {
        self.waiter?.resume(returning: false)
        self.waiter = waiter
        self.progress = progress
        expected = nil
        received = 0
    }

    /// The answer to the restart alert: install now (Sparkle quits and relaunches the app)
    /// or later.
    func finish(_ choice: SPUUserUpdateChoice) {
        let reply = readyReply
        readyReply = nil
        reply?(choice)
    }

    private func end(_ result: Result<Bool, Error>) {
        let waiting = waiter
        waiter = nil
        progress = nil
        waiting?.resume(with: result)
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Only the window's Update installs; anything else Sparkle starts is left for it.
        reply(waiter == nil ? .dismiss : .install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        end(.success(false))
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        AppLog.note("app updates: \(error.localizedDescription)")
        end(.failure(StepFailure(step: "Update Lullaby", detail: error.localizedDescription)))
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expected = Int64(expectedContentLength)
        progress?(received, expected)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += Int64(length)
        progress?(received, expected)
    }

    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        end(.success(true))
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        // The session ended without a ready update (cancelled, or nothing to do).
        end(.success(false))
    }
}
