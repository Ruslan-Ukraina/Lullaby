// `LullabyApp --migrate-scratch <home> [--steam-app <app>]`: the move from NotProton
// (LegacyMigration) on a copy of the data under a scratch home, for checking it before it
// runs on the real one. Refuses the real home. Nothing outside <home> is looked at or
// changed: no processes, no preferences, and Steam's Repair is replaced by a stand-in that
// takes the old dylib out of the copied Steam.app (the real Repair closes Steam by name,
// and would close the real one). Prints the report; exits 0 on success, 1 otherwise.

import Foundation

enum HeadlessMigration {
    static let flag = "--migrate-scratch"

    private final class ExitCode: @unchecked Sendable {
        var value: Int32 = 1
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return }
        let home = URL(filePath: arguments[index + 1]).standardizedFileURL
        guard home.path != SupportPaths.home.standardizedFileURL.path, home.path != "/" else {
            print("migrate: refuses the real home, give a scratch folder")
            exit(1)
        }
        let app = arguments.firstIndex(of: "--steam-app").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            .map { URL(filePath: $0) } ?? home.appending(path: "Applications/Steam.app")
        let layout = LegacyMigration.Layout(home: home, steamApp: app, readsLibraryFolders: false)
        var effects = LegacyMigration.Effects.inert { print("migrate: \($0)") }
        effects.repairSteam = { layout in try standInRepair(layout.steamApp) }

        let code = ExitCode()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                print("migrate: needed \(LegacyMigration.isNeeded(layout))")
                let report = try await LegacyMigration.run(layout, effects: effects)
                print("migrate: report \(report)")
                print("migrate: needed afterwards \(LegacyMigration.isNeeded(layout))")
                code.value = 0
            } catch {
                print("migrate: failed: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
        exit(code.value)
    }

    /// What Repair leaves for the migration's purpose: no insert, no old dylib.
    static func standInRepair(_ app: URL) throws {
        try? FileManager.default.removeItem(at: app.appending(path: "Contents/MacOS/\(LegacyMigration.oldName).dylib"))
        _ = try SteamRepair.clearInsert(at: SupportPaths.Steam.infoPlist(inBundle: app))
    }
}
