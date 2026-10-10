// NotProton's one window (Phase 8, ROADMAP §9): see Main/MainView.swift.

import SwiftUI

@main
struct NotProtonApp: App {

    @State private var main: MainModel

    init() {
        AppLog.start()
        DormisonEngine().ensureEnvironmentFile()
        HeadlessInstall.runIfRequested()
        HeadlessEngine.runIfRequested()
        HeadlessRelease.runIfRequested()
        _main = State(initialValue: MainModel())
    }

    var body: some Scene {
        Window("NotProton", id: "main") {
            MainView()
                .environment(main)
                .task { await main.opened() }
        }
        .windowResizability(.contentSize)
        .defaultSize(MainView.size)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
