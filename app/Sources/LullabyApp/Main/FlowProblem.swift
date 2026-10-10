// A failed step, in words a player understands (Phase 8: a system alert; the same button
// tries again). The model's own errors are English sentences for the log; here they
// are sorted into the few cases a player can act on, each with a translated text, and
// everything else becomes "this step did not work, details are in the log".

import Foundation

struct FlowProblem: Equatable, Sendable {
    enum Cause: Equatable, Sendable {
        case steamDidNotQuit
        case gameRunning
        case offline
        case appManagement
        case otherAccount
        case rosettaMissing
        case steamMissing
        case engineNotSupportedYet
        case noBridgeYet
        case toolkitNotFound
        case failed(FlowStep.ID)
    }

    let cause: Cause
    /// The model's own sentence, for the log and the small print under the message.
    let detail: String

    init(cause: Cause, detail: String) {
        self.cause = cause
        self.detail = detail
    }

    init(_ error: Error, step: FlowStep.ID) {
        let text = error.localizedDescription
        detail = text
        if let known = error as? KnownProblem {
            cause = known.cause
        } else if error is SteamBundle.StillRunning {
            cause = .steamDidNotQuit
        } else if let refused = error as? WriteRefused {
            cause = refused.remedy == .otherAccount ? .otherAccount : .appManagement
        } else if let url = error as? URLError, Self.offlineCodes.contains(url.code) {
            cause = .offline
        } else if text.contains(SteamInstaller.gameRunning) || text.contains(EngineUpdater.gameRunning) {
            cause = .gameRunning
        } else if text.contains(EngineUpdater.offline) {
            cause = .offline
        } else {
            cause = .failed(step)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .timedOut, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
    ]

    /// What the window says. Short, plain, and always says what to do next.
    var message: String {
        switch cause {
        case .steamDidNotQuit:
            tr("Steam didn't close. Quit Steam yourself, then try again.")
        case .gameRunning:
            tr("A game is still running. Quit it, then try again.")
        case .offline:
            tr("No connection to the internet. Check it, then try again.")
        case .appManagement:
            tr("macOS didn't let Lullaby change Steam. Allow Lullaby under App Management in System Settings, then try again.")
        case .otherAccount:
            tr("Steam was installed by another user of this Mac. Only that user can install Lullaby into it.")
        case .rosettaMissing:
            tr("Windows games need Rosetta. Install it when macOS asks, then try again.")
        case .steamMissing:
            tr("Steam isn't in the Applications folder. Install Steam, then try again.")
        case .engineNotSupportedYet:
            tr("A new engine is out, but Lullaby doesn't support it yet. Try again later.")
        case .noBridgeYet:
            tr("The Steam bridge for this engine isn't ready yet. Try again later.")
        case .toolkitNotFound:
            tr("This file isn't Apple's Game Porting Toolkit. Pick the .dmg you downloaded from Apple.")
        case .failed(let step):
            Self.failedText(step)
        }
    }

    /// The alert's title, by what was being done.
    static func title(_ kind: FlowKind) -> String {
        switch kind {
        case .install: tr("Couldn't install Lullaby")
        case .update: tr("Couldn't update Lullaby")
        case .reinstall: tr("Couldn't reinstall Lullaby")
        case .delete: tr("Couldn't delete Lullaby")
        case .addToolkit: tr("Couldn't add the Game Porting Toolkit")
        case .steamUpdates: tr("Couldn't change Steam updates")
        }
    }

    /// Opens the App Management pane: a second button in the alert.
    var settingsPane: URL? {
        cause == .appManagement ? Remedy.appManagement.settingsPane : nil
    }

    static func failedText(_ step: FlowStep.ID) -> String {
        switch step {
        case .waitForGame: tr("A game is still running. Quit it, then try again.")
        case .migrate: tr("Couldn't move NotProton's files to Lullaby. Details are in the log.")
        case .rosetta: tr("Couldn't check Rosetta. Details are in the log.")
        case .engine: tr("Couldn't install the engine. Details are in the log.")
        case .bridge: tr("Couldn't install the Steam bridge. Details are in the log.")
        case .signatures: tr("Couldn't download Steam support files. Details are in the log.")
        case .steam: tr("Couldn't install Lullaby into Steam. Details are in the log.")
        case .app: tr("Couldn't update Lullaby. Details are in the log.")
        case .removeSteam: tr("Couldn't return Steam to how it was. Details are in the log.")
        case .removeFiles: tr("Couldn't delete Lullaby's files. Details are in the log.")
        case .toolkit: tr("Couldn't add the Game Porting Toolkit. Details are in the log.")
        case .steamUpdates: tr("Couldn't change Steam updates. Details are in the log.")
        }
    }
}

/// An error a step throws when it already knows what the player should do.
struct KnownProblem: LocalizedError {
    let cause: FlowProblem.Cause
    let log: String

    init(_ cause: FlowProblem.Cause, log: String) {
        self.cause = cause
        self.log = log
    }

    var errorDescription: String? { log }
}
