// NotProton's one window (Phase 8, ROADMAP §9): see Main/MainView.swift.

import SwiftUI

@main
struct LullabyApp: App {

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
        // The title bar is part of the window's background, traffic lights over it (owner, 10.10).
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)
        .defaultSize(MainView.size)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Credits: a window of its own beside the main one, only the close button (owner, 10.10).
        Window(Text(verbatim: "NotProton"), id: CreditsView.windowID) {
            CreditsView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}
