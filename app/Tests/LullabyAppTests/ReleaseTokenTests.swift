import Foundation
import Testing

@testable import LullabyApp

// Phase 6, step 6: ⚙︎ → Access Token… while releases are private. The token is checked
// with GitHub before it is kept, goes only to api.github.com, and the row is not there
// at all for public releases. No network and no Keychain: both are stand-ins.

private final class Recorder: @unchecked Sendable {
    var requests: [URLRequest] = []
}

@Suite("Release token")
struct ReleaseTokenTests {
    @Test("GitHub's answer decides what the token is", arguments: [
        (200, ReleaseToken.Check.works), (401, .rejected), (403, .noAccess), (404, .noAccess), (500, .unreachable),
    ])
    func answers(code: Int, expected: ReleaseToken.Check) async {
        let got = await ReleaseToken.check("github_pat_x", repository: "owner/repo", status: { _ in code })
        #expect(got == expected)
    }

    @Test("No answer at all is unreachable, not rejected")
    func offline() async {
        let got = await ReleaseToken.check("github_pat_x", repository: "owner/repo", status: { _ in
            throw URLError(.notConnectedToInternet)
        })
        #expect(got == .unreachable)
    }

    @Test("A refused token is named as such, not as a lost connection", arguments: [401, 403])
    func refusedIsNotOffline(status: Int) {
        let error = TransportFailure(detail: "x", status: status)
        #expect(ReleaseAccess.failure(error) == ReleaseAccess.tokenRejected)
        let problem = FlowProblem(StepFailure(step: "x", detail: ReleaseAccess.failure(error)), step: .bridge)
        #expect(problem.cause == .tokenRejected)
    }

    @Test("A file GitHub does not have (404) is said as such, not as a lost connection")
    func notFoundIsNotOffline() {
        #expect(ReleaseAccess.failure(TransportFailure(detail: "x", status: 404)) == ReleaseAccess.notFound)
    }

    @Test("Other failures stay offline")
    func otherFailures() {
        #expect(ReleaseAccess.failure(TransportFailure(detail: "x", status: 500)) == EngineUpdater.offline)
        #expect(ReleaseAccess.failure(URLError(.notConnectedToInternet)) == EngineUpdater.offline)
    }

    @Test("The check lists the repository's releases on api.github.com with the token")
    func request() async {
        let seen = Recorder()
        _ = await ReleaseToken.check("github_pat_secret", repository: "Ruslan-Ukraina/Lullaby", status: {
            seen.requests.append($0)
            return 200
        })
        let request = try! #require(seen.requests.first)
        #expect(request.url?.host() == "api.github.com")
        #expect(request.url?.path() == "/repos/Ruslan-Ukraina/Lullaby/releases")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer github_pat_secret")
    }
}

@MainActor
@Suite("Access token in ⚙︎")
struct AccessTokenRowTests {
    final class Store {
        var saved: [String: String] = [:]
        var restarts = 0
    }

    func model(access: String, check: ReleaseToken.Check = .works) -> (MainModel, Store) {
        let name = "lullaby-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let model = MainModel(badge: BadgeStore(defaults: defaults, dock: { _ in }))
        let store = Store()
        model.findUpdates = { _ in UpdatePlan() }
        model.releaseInfo = { (access, "Ruslan-Ukraina/Lullaby") }
        model.tokenKeychain = .init(
            read: { store.saved[$0] },
            save: { store.saved[$1] = $0; return true },
            remove: { store.saved[$0] = nil })
        model.checkToken = { _, _ in check }
        model.restartUpdates = { store.restarts += 1 }
        return (model, store)
    }

    @Test("Public releases: no token row")
    func publicHasNoRow() {
        let (model, _) = model(access: "public")
        #expect(model.privateReleaseRepository == nil)
    }

    @Test("Private releases: the row, and a working token is kept and used")
    func works() async {
        let (model, store) = model(access: "private")
        #expect(model.privateReleaseRepository == "Ruslan-Ukraina/Lullaby")
        model.readTokenState()
        #expect(!model.hasReleaseToken)
        await model.saveReleaseToken("  github_pat_good\n")
        #expect(store.saved["Ruslan-Ukraina/Lullaby"] == "github_pat_good")
        #expect(model.hasReleaseToken)
        #expect(store.restarts == 1)
        #expect(model.tokenResult == tr("The token works. Lullaby checks for updates now."))
    }

    @Test("A token GitHub refuses is not kept", arguments: [ReleaseToken.Check.rejected, .noAccess])
    func refused(check: ReleaseToken.Check) async {
        let (model, store) = model(access: "private", check: check)
        await model.saveReleaseToken("github_pat_bad")
        #expect(store.saved.isEmpty)
        #expect(store.restarts == 0)
        #expect(!model.hasReleaseToken)
        #expect(model.tokenResult != nil)
    }

    @Test("Offline: the token is kept and tried next time")
    func offline() async {
        let (model, store) = model(access: "private", check: .unreachable)
        await model.saveReleaseToken("github_pat_later")
        #expect(store.saved["Ruslan-Ukraina/Lullaby"] == "github_pat_later")
        #expect(model.tokenResult == tr("GitHub can't be reached. The token is saved; Lullaby tries it next time."))
    }

    @Test("Remove takes it out of the Keychain and the updater")
    func remove() async {
        let (model, store) = model(access: "private")
        await model.saveReleaseToken("github_pat_good")
        model.removeReleaseToken()
        #expect(store.saved.isEmpty)
        #expect(!model.hasReleaseToken)
        #expect(store.restarts == 2)
    }

    @Test("An empty field does nothing")
    func empty() async {
        let (model, store) = model(access: "private")
        await model.saveReleaseToken("   ")
        #expect(store.saved.isEmpty)
        #expect(model.tokenResult == nil)
    }
}
