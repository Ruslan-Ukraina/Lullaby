// 'Status' view, see SystemStatus for actual logic

import SwiftUI

enum StatusTone: Sendable {
    case ok, info, warning, bad, neutral

    var symbol: String {
        switch self {
        case .ok: "circle.fill"
        case .info: "circle"
        case .warning: "circle.fill"
        case .bad: "circle.fill"
        case .neutral: "circle"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .info: .secondary
        case .warning: .orange
        case .bad: .red
        case .neutral: .secondary
        }
    }
}

struct StatusAction {
    let label: String
    var isProminent = false
    var role: ButtonRole?
    var help: String?
    var isEnabled = true
    let perform: () -> Void
}

enum StatusMetrics {
    static let symbolWidth: CGFloat = 10
    static let symbolSpacing: CGFloat = 8
    static var textInset: CGFloat { symbolWidth + symbolSpacing }
}

struct StatusRow: View {

    @Environment(\.colorSchemeContrast) private var contrast

    let title: String
    var value: String?

    var tone: StatusTone?
    var detail: String?
    var secondaryAction: StatusAction?
    var action: StatusAction?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: StatusMetrics.symbolSpacing) {
                if let tone {
                    Image(systemName: tone.symbol)
                        .font(.system(size: 8))
                        .foregroundStyle(tone.color)
                        .frame(width: StatusMetrics.symbolWidth)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: StatusMetrics.symbolWidth, height: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let value {
                        Text(value)
                            .foregroundStyle(.secondary)
                    }
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(contrast == .increased ? .secondary : .tertiary)
                            .textSelection(.enabled)
                    }
                }
            }

            if secondaryAction != nil || action != nil {
                Spacer(minLength: 12)
            }
            if let secondaryAction {
                button(secondaryAction)
                    .disabled(!secondaryAction.isEnabled)
                    .help(secondaryAction.help ?? "")
                    .accessibilityLabel("\(secondaryAction.label), \(title)")
                    .padding(.trailing, 8)
            }
            if let action {
                button(action)
                    .disabled(!action.isEnabled)
                    .help(action.help ?? "")
                    .accessibilityLabel("\(action.label), \(title)")
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func button(_ action: StatusAction) -> some View {
        if action.isProminent {
            Button(action.label, role: action.role, action: action.perform)
                .buttonStyle(.borderedProminent)
        } else {
            Button(action.label, role: action.role, action: action.perform)
                .buttonStyle(.bordered)
        }
    }
}

struct StatusView: View {
    @Environment(SystemStatus.self) private var status
    @AppStorage(AppUpdater.prereleaseDefault) private var prereleaseUpdates = false
    @State private var showingTokenSheet = false
    @State private var tokenDraft = ""
    @State private var tokenRevision = 0

    private static let updateBlockPrompt =
        "NotProton already lets Steam update only to builds it has signatures for. "
            + "Blocking keeps Steam on its current build even when NotProton supports a newer one, "
            + "so Steam gets no updates until you turn this off."

    var body: some View {
        Group {
            if let snapshot = status.snapshot {
                statusForm(snapshot)
            } else {
                ProgressView("Checking")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Status")
        .toolbar {
            if #available(macOS 26.1, *) {
                ToolbarItem(placement: .primaryAction) { refreshButton }
                    .visibilityPriority(.high)
            } else {
                ToolbarItem(placement: .primaryAction) { refreshButton }
            }
        }
        .confirmationDialog(
            "Block Steam client updates?",
            isPresented: asking(.blockUpdates),
            titleVisibility: .visible
        ) {
            Button("Block Updates", role: .destructive) {
                Task { await status.setUpdateBlock(true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.updateBlockPrompt)
        }
        .confirmationDialog(
            "Close Steam to install?",
            isPresented: asking(.stopSteamToInstall),
            titleVisibility: .visible
        ) {
            Button("Close Steam and Install") {
                Task { await status.confirmPendingInstall() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Steam is running. NotProton closes it to replace the patch inside Steam, "
                    + "then offers to open it again. Downloads in progress are paused."
            )
        }
        .confirmationDialog(
            status.pendingEngine == .rollback ? "Close Steam to roll back the engine?" : "Close Steam to switch engines?",
            isPresented: asking(.stopSteamForEngine),
            titleVisibility: .visible
        ) {
            Button(status.pendingEngine == .rollback ? "Close Steam and Roll Back" : "Close Steam and Switch") {
                Task { await status.confirmPendingEngine() }
            }
            Button("Cancel", role: .cancel) { status.cancelPendingEngine() }
        } message: {
            Text(
                status.pendingEngine == .rollback
                    ? "Steam is running. NotProton closes it now to switch engines, then offers to open it again."
                    : "\(status.preparedEngine?.release.displayName ?? "The engine") is downloaded and tested. "
                        + "NotProton closes Steam now to switch to it, then offers to open it again."
            )
        }
        .confirmationDialog(
            "Replace Steam with Valve's bundle?",
            isPresented: asking(.replaceSteam),
            titleVisibility: .visible
        ) {
            Button("Replace Steam", role: .destructive) {
                Task { await status.repairSteam() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will restore Steam itself to its original state but does not remove "
                    + "the support components used by NotProton."
            )
        }
        .confirmationDialog(
            "Are you sure?",
            isPresented: asking(.removeEngine),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await status.removePendingEngine() }
            }
            Button("Cancel", role: .cancel) { status.cancelEngineRemoval() }
        } message: {
            if let tag = status.pendingRemoval {
                Text("Are you sure you want to remove \(EngineStore.displayName(tag))?")
            }
        }
        .confirmationDialog(
            "Remove everything NotProton has created?",
            isPresented: asking(.removeEverything),
            titleVisibility: .visible
        ) {
            Button("Remove Everything", role: .destructive) {
                Task { await status.removeEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Steam is restored to its unmodified state and NotProton is removed, including "
                    + "the compatibility tool that lives inside the Steam folder. Windows games "
                    + "and Steam Play prefixes are not removed."
            )
        }
        .task {
            if status.snapshot == nil { await status.refresh() }
            if status.engineCheck == nil { await status.checkEngineUpdates(quiet: true) }
            status.startReleaseChecks()
            await status.runEngineUITestIfRequested()
        }
    }

    private func asking(_ confirmation: SystemStatus.Confirmation) -> Binding<Bool> {
        Binding(
            get: { status.pendingConfirmation == confirmation },
            set: { shown in
                if !shown, status.pendingConfirmation == confirmation {
                    status.pendingConfirmation = nil
                }
            }
        )
    }

    private func statusForm(_ snapshot: StatusSnapshot) -> some View {
        Form {
            if let failure = status.failure {
                StatusRow(
                    title: "Failed",
                    value: failure,
                    tone: .bad,
                    action: status.retryInstallForce != nil
                        ? StatusAction(label: "Retry", isProminent: true, isEnabled: status.isIdle) {
                            Task { await status.retryInstall() }
                        }
                        : status.retryEngine != nil
                        ? StatusAction(label: "Retry", isProminent: true, isEnabled: status.isIdle) {
                            Task { await status.retryEngineAction() }
                        }
                        : status.retryRestart
                        ? StatusAction(label: "Retry", isProminent: true, isEnabled: status.isIdle) {
                            Task { await status.restartSteam() }
                        }
                        : status.failureRemedy?.settingsPane.map { pane in
                            StatusAction(label: Remedy.settingsButton) {
                                Remedy.openSettings(pane)
                            }
                        }
                )
            } else if let outcome = status.outcome {
                StatusRow(
                    title: "Done",
                    value: outcome,
                    tone: .ok,
                    action: status.offerSteamLaunch
                        ? StatusAction(label: "Open Steam", isProminent: true, isEnabled: status.isIdle) {
                            status.openSteam()
                        }
                        : status.offerSteamRestart
                        ? StatusAction(label: "Restart Steam", isProminent: true, isEnabled: status.isIdle) {
                            Task { await status.restartSteam() }
                        }
                        : nil
                )
            }

            if let activity = status.activity {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(activity)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Steam") {
                steamRow(snapshot.steam, payload: snapshot.payload, patch: snapshot.patch)
                if snapshot.steamRunning {
                    StatusRow(
                        title: "Steam is running",
                        value: "Install, Update and Reinstall close it first and ask before they do.",
                        tone: .info
                    )
                }
                gateRow(snapshot.updates)
                updateBlockRow(snapshot.updates.gateMode == .manual)
                signaturesRow(snapshot.updates)
                // Shelved (DECISIONS W19): a release build shows the switch only
                // while it is on, so that it can be turned off.
                if BuildKind.current != .release || snapshot.nativeSteamWindows {
                    steamWindowsRow(snapshot.nativeSteamWindows)
                }
                if snapshot.nativeSteamWindows {
                    steamAsAppRow(snapshot.steamAsRegularApp)
                }
                reinstallRow(snapshot.steam)
            }

            Section("Engine") {
                runnerRow(snapshot.runner, capabilities: snapshot.engineCapabilities)
                engineUpdateRow(snapshot.runner)
                if let target = snapshot.rollbackTarget {
                    rollbackRow(target)
                }
                channelRow
                if snapshot.installedEngines.count > 1 {
                    engineRows(snapshot)
                }
            }

            if snapshot.runner != .none {
                Section("Steam Bridge") {
                    bridgeRow(snapshot.updates)
                    bridgeUpdateRow(snapshot.updates)
                    if let target = snapshot.updates.bridgeRollback {
                        bridgeRollbackRow(target)
                    }
                }
            }

            componentsSection(snapshot.payload)

            appSection

            dangerSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    private var dangerSection: some View {
        Section {
            StatusRow(
                title: "Repair Steam",
                value: "Restore Steam to its original state.",
                action: StatusAction(
                    label: "Repair",
                    role: .destructive,
                    isEnabled: status.isIdle
                ) { status.pendingConfirmation = .replaceSteam }
            )
            StatusRow(
                title: "Remove Everything",
                value: "Remove NotProton and restore Steam to its original state.",
                action: StatusAction(
                    label: "Remove",
                    role: .destructive,
                    isEnabled: status.isIdle
                ) { status.pendingConfirmation = .removeEverything }
            )
        }
    }

    private var refreshButton: some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await status.refresh() }
        }
        .disabled(!status.isIdle)
    }

    private func installAction(prominent: Bool, label: String = "Install") -> StatusAction {
        StatusAction(
            label: label,
            isProminent: prominent,
            help: "Install NotProton into Steam.",
            isEnabled: status.isIdle
        ) {
            Task { await status.requestInstall() }
        }
    }

    private static let installedFormat: Date.FormatStyle = .dateTime
        .day().month(.abbreviated).year().hour().minute()

    /// "Build 47B89F80, installed 6 Oct 2026 at 15:30" for what sits in Steam.app.
    static func patchDetail(_ patch: InstalledPatch?) -> String? {
        guard let patch, let build = patch.build else { return nil }
        var text = "Build \(build)"
        if let date = patch.installedAt { text += ", installed \(date.formatted(installedFormat))" }
        return text + "."
    }

    static func staleDetail(_ stale: [PatchPart], patch: InstalledPatch?) -> String? {
        var lines: [String] = []
        if !stale.isEmpty {
            let parts = stale.map(\.label).joined(separator: ", ")
            lines.append("Out of date: \(parts).")
        }
        if let patch, let shipped = patch.shippedBuild {
            lines.append("Steam has build \(patch.build ?? "none"), this app carries build \(shipped).")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private func reinstallRow(_ deployment: SteamDeployment) -> some View {
        StatusRow(
            title: "Reinstall NotProton",
            value: "Put every part back in place, even if it looks current.",
            action: StatusAction(
                label: "Reinstall",
                help: "Install NotProton into Steam again. Steam is closed first.",
                isEnabled: status.isIdle && deployment != .steamMissing
            ) {
                Task { await status.requestInstall(force: true) }
            }
        )
    }

    private func steamRow(
        _ deployment: SteamDeployment, payload: PayloadState, patch: InstalledPatch?
    ) -> some View {
        switch deployment {
        case .steamMissing:
            StatusRow(title: "NotProton", value: "Steam not found.", tone: .bad)
        case .notInstalled:
            StatusRow(
                title: "NotProton",
                value: "Not installed.",
                tone: .neutral,
                action: installAction(prominent: true)
            )
        case .installed(let version):
            if payload.isComplete {
                StatusRow(
                    title: "NotProton",
                    value: "Installed" + (version.map { " (\($0))" } ?? ""),
                    tone: .ok,
                    detail: Self.patchDetail(patch)
                )
            } else {
                StatusRow(
                    title: "NotProton",
                    value: "Installed, but not for this account.",
                    tone: .warning,
                    detail: "Steam is set up for NotProton, but this account is missing its "
                        + "components. Install to add them.",
                    action: installAction(prominent: true)
                )
            }
        case .outdated(let deployed, let bundled, let stale):
            StatusRow(
                title: "NotProton",
                value: deployed.map { $0 == bundled ? "Update available." : "Update available (\($0) → \(bundled))." }
                    ?? "Update available.",
                tone: .warning,
                detail: Self.staleDetail(stale, patch: patch),
                action: installAction(prominent: true, label: "Update")
            )
        case .foreign:
            StatusRow(
                title: "NotProton",
                value: "Another dylib is present.",
                tone: .warning,
                detail: "Repair your Steam install before installing NotProton."
            )
        }
    }

    private func updateBlockRow(_ blocked: Bool) -> some View {
        Toggle(isOn: blockUpdates) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Block Steam client updates")
                    .font(.headline)
                Text(
                    blocked
                        ? "Steam does not update, even to builds NotProton supports."
                        : "NotProton lets Steam update only to builds it has signatures for."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.leading, StatusMetrics.textInset)
        }
        .disabled(!status.isIdle)
        .help("On: Steam never updates. Off: NotProton holds Steam's updates until a new Steam build "
            + "has signatures, then lets it update.")
    }

    private func steamWindowsRow(_ enabled: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { status.snapshot?.nativeSteamWindows ?? false },
            set: { wanted in Task { await status.setNativeSteamWindows(wanted) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Native Steam windows")
                    .font(.headline)
                Text(
                    enabled
                        ? "Steam's windows have the macOS title bar and traffic lights."
                        : "Steam draws its own window buttons, as Valve ships it."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.leading, StatusMetrics.textInset)
        }
        .disabled(!status.isIdle)
        .help("macOS window frame for Steam: traffic lights, rounded corners, full screen, "
            + "Stage Manager and tiling. Applies when Steam starts.")
    }

    private func steamAsAppRow(_ enabled: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { status.snapshot?.steamAsRegularApp ?? false },
            set: { wanted in Task { await status.setNativeSteamWindows(true, regularApp: wanted) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Steam as a regular app (experimental)")
                    .font(.headline)
                Text(
                    enabled
                        ? "Spaces and Stage Manager treat Steam's windows as an app's. While one is open, Steam has a second Dock icon."
                        : "Steam's windows belong to a background helper, as Valve ships it."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.leading, StatusMetrics.textInset)
        }
        .disabled(!status.isIdle)
        .help("Runs Steam Helper, which owns Steam's windows, as a regular app with Steam's icon while a "
            + "Steam window is open. Its Dock icon opens the library; Quit on it quits Steam. "
            + "Applies when Steam starts.")
    }

    private var blockUpdates: Binding<Bool> {
        Binding(
            get: { status.snapshot?.updates.gateMode == .manual },
            set: { wanted in
                if wanted {
                    status.pendingConfirmation = .blockUpdates
                } else {
                    Task { await status.setUpdateBlock(false) }
                }
            }
        )
    }

    @ViewBuilder
    private func engineRows(_ snapshot: StatusSnapshot) -> some View {
        let active = EngineStore.currentTag()
        ForEach(snapshot.installedEngines) { engine in
            let isActive = engine.tag == active
            let bridgeless = snapshot.updates.enginesWithoutBridge.contains(engine.tag)
            StatusRow(
                title: EngineStore.displayName(engine.tag),
                value: isActive ? "Active engine." : engineSize(engine.tag),
                tone: bridgeless ? .warning : isActive ? .ok : .neutral,
                detail: bridgeless ? "No Steam bridge fits it: Steam features in its games will not work." : nil,
                secondaryAction: isActive ? nil : removeAction(engine.tag),
                action: isActive ? nil : useAction(engine.tag)
            )
        }
    }

    private func engineSize(_ tag: String) -> String? {
        status.runnerSizes[tag].map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
    }

    private func useAction(_ tag: String) -> StatusAction {
        StatusAction(
            label: "Use",
            help: "Launch games with this engine.",
            isEnabled: status.isIdle
        ) {
            Task { await status.switchEngine(to: tag) }
        }
    }

    private func removeAction(_ tag: String) -> StatusAction {
        StatusAction(
            label: "Remove",
            role: .destructive,
            help: "Delete this engine from disk.",
            isEnabled: status.isIdle
        ) {
            status.requestEngineRemoval(tag)
        }
    }

    private func runnerRow(_ state: EngineState, capabilities: EngineCapabilities) -> some View {
        switch state {
        case .none:
            return StatusRow(
                title: "Engine",
                value: "Not installed.",
                tone: .neutral,
                detail: "Check for Updates finds the Dormison engine and installs it."
            )
        case .broken(let detail):
            return StatusRow(
                title: "Engine",
                value: "Unusable.",
                tone: .bad,
                detail: detail
            )
        case .engine(let version):
            return StatusRow(
                title: "Engine",
                value: EngineStore.displayName(version),
                tone: .ok,
                detail: Self.engineDetail(capabilities)
            )
        }
    }

    /// "Wine 11.16 + wine-staging 11.16, commit 52c2a4b918d6."
    static func engineDetail(_ capabilities: EngineCapabilities) -> String? {
        var parts: [String] = []
        if let wine = capabilities.wine { parts.append("Wine \(wine)") }
        if let commit = capabilities.commit { parts.append("commit \(commit.prefix(12))") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
    }

    private var checkAction: StatusAction {
        StatusAction(
            label: "Check for Updates",
            help: "Read Dormison's signed release list.",
            isEnabled: status.isIdle
        ) { Task { await status.checkEngineUpdates() } }
    }

    private func engineInstallAction(_ release: EngineRelease, label: String, prominent: Bool) -> StatusAction {
        StatusAction(
            label: label,
            isProminent: prominent,
            help: "Download, verify and test \(release.displayName), then switch to it.",
            isEnabled: status.isIdle
        ) { Task { await status.requestEngine(.install(release)) } }
    }

    private var checkedDetail: String? {
        status.engineCheckedAt.map { "Checked \($0.formatted(date: .omitted, time: .shortened))." }
    }

    @ViewBuilder
    private func engineUpdateRow(_ state: EngineState) -> some View {
        if let prepared = status.preparedEngine, status.pendingConfirmation != .stopSteamForEngine {
            StatusRow(
                title: "Updates",
                value: "\(prepared.release.displayName) is ready to switch to.",
                tone: .warning,
                detail: "Downloaded and tested. Switching closes Steam if it is running.",
                action: StatusAction(
                    label: status.snapshot?.steamRunning == true ? "Close Steam and Switch" : "Switch",
                    isProminent: true,
                    isEnabled: status.isIdle
                ) { Task { await status.requestEngine(.finish) } }
            )
        } else {
            engineCheckRow(state)
        }
    }

    @ViewBuilder
    private func engineCheckRow(_ state: EngineState) -> some View {
        switch status.engineCheck {
        case nil:
            StatusRow(
                title: "Updates",
                value: "Not checked yet.",
                tone: .neutral,
                action: checkAction
            )
        case .available(let release):
            StatusRow(
                title: "Updates",
                value: state == .none ? "\(release.displayName) is ready to install."
                    : "\(release.displayName) is available.",
                tone: .warning,
                detail: release.notes,
                secondaryAction: checkAction,
                action: engineInstallAction(
                    release, label: state == .none ? "Install" : "Update", prominent: true)
            )
        case .upToDate(let release, let supported):
            StatusRow(
                title: "Updates",
                value: "Up to date.",
                tone: .ok,
                detail: supported ? checkedDetail : "This NotProton cannot reinstall it.",
                secondaryAction: checkAction,
                action: supported ? engineInstallAction(release, label: "Reinstall", prominent: false) : nil
            )
        case .waiting(let release, let reason):
            StatusRow(
                title: "Updates",
                value: "\(release.displayName) is out. Waiting for NotProton support.",
                tone: .warning,
                detail: reason + " The current engine keeps working.",
                action: checkAction
            )
        case .newerInstalled(let release):
            StatusRow(
                title: "Updates",
                value: "Newer than the \(release.channel.label.lowercased()) channel (\(release.displayName)).",
                tone: .ok,
                detail: checkedDetail,
                action: checkAction
            )
        case .nothingOnChannel(let channel):
            StatusRow(
                title: "Updates",
                value: channel == .stable
                    ? "No stable Dormison release yet. Switch the channel to Beta to get one."
                    : "Dormison names no release.",
                tone: .neutral,
                action: checkAction
            )
        }
    }

    private func rollbackRow(_ target: String) -> some View {
        let sameVersion = target == EngineStore.currentTag()
        return StatusRow(
            title: "Previous engine",
            value: sameVersion
                ? "\(EngineStore.displayName(target)), the other copy from the last reinstall."
                : EngineStore.displayName(target),
            tone: .neutral,
            action: StatusAction(
                label: "Roll Back",
                help: "Switch games back to the previous engine.",
                isEnabled: status.isIdle
            ) { Task { await status.requestEngine(.rollback) } }
        )
    }

    private var channelRow: some View {
        Picker(selection: Binding(
            get: { status.engineChannel },
            set: { channel in Task { await status.setEngineChannel(channel) } }
        )) {
            ForEach(EngineChannel.allCases) { Text($0.label).tag($0) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Update channel")
                    .font(.headline)
                Text("Beta gets Dormison's test builds; Stable only its releases.")
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, StatusMetrics.textInset)
        }
        .disabled(!status.isIdle)
    }

    // MARK: NotProton.app updates (Phase 6)

    private var appSection: some View {
        let updater = AppUpdater.shared
        return Section("NotProton") {
            StatusRow(
                title: "NotProton \(updater.version)",
                value: {
                    if case .off(let reason) = updater.setup { return reason }
                    return "Updates itself from NotProton's releases on GitHub."
                }(),
                tone: updater.isAvailable ? .ok : .info,
                action: updater.isAvailable
                    ? StatusAction(
                        label: "Check for Updates…",
                        help: "Look for a newer NotProton now. It checks once a day by itself."
                    ) { updater.check() }
                    : nil
            )
            if updater.isPrivate {
                tokenRow(updater)
            }
            if updater.isAvailable {
                Toggle(isOn: Binding(
                    get: { prereleaseUpdates },
                    set: { wanted in
                        prereleaseUpdates = wanted
                        updater.setPrereleases(wanted)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pre-release versions")
                            .font(.headline)
                        Text("Also offer NotProton's test releases before they are final.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, StatusMetrics.textInset)
                }
            }
        }
    }

    /// Private releases only (ROADMAP §3): the read-only token, kept in the Keychain.
    private func tokenRow(_ updater: AppUpdater) -> some View {
        let present = ReleaseToken.read(repository: updater.repository) != nil
        return StatusRow(
            title: "Access token",
            value: present
                ? "Saved in the Keychain. NotProton reads its private releases with it."
                : "NotProton's releases are private. Add the read-only token you were given.",
            tone: present ? .ok : .warning,
            secondaryAction: present
                ? StatusAction(label: "Remove", role: .destructive) {
                    ReleaseToken.remove(repository: updater.repository)
                    AppLog.note("release access: token removed")
                    updater.start()
                    tokenRevision += 1
                }
                : nil,
            action: StatusAction(label: present ? "Replace…" : "Add Token…", isProminent: !present) {
                tokenDraft = ""
                showingTokenSheet = true
            }
        )
        .id(tokenRevision)
        .sheet(isPresented: $showingTokenSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Access token for \(updater.repository)")
                    .font(.headline)
                Text("A read-only token for the releases. It is stored in your Keychain and sent only to GitHub.")
                    .foregroundStyle(.secondary)
                SecureField("Token", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { showingTokenSheet = false }
                    Button("Save") {
                        ReleaseToken.save(tokenDraft, repository: updater.repository)
                        tokenDraft = ""
                        showingTokenSheet = false
                        updater.start()
                        tokenRevision += 1
                        Task { await status.checkReleases() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
    }

    // MARK: Phase 5 rows

    private var releasesCheckAction: StatusAction {
        StatusAction(
            label: "Check Now",
            help: "Read NotProton's signed release lists and Valve's latest Steam version.",
            isEnabled: status.isIdle
        ) { Task { await status.checkReleases() } }
    }

    private var releasesCheckedDetail: String? {
        status.releasesCheckedAt.map { "Checked \($0.formatted(date: .omitted, time: .shortened))." }
    }

    private func gateRow(_ updates: UpdatesSnapshot) -> some View {
        let installed = SystemStatus.build(updates.installedSteam)
        guard let decision = status.gateDecision else {
            return StatusRow(
                title: "Steam updates",
                value: updates.gateMode == .manual
                    ? "Blocked by you. Steam stays on build \(installed)."
                    : "Managed by NotProton. Steam build \(installed).",
                tone: .neutral,
                detail: "Not checked yet.",
                action: releasesCheckAction)
        }
        let tone: StatusTone
        var detail: [String] = []
        switch decision.state {
        case .manual:
            tone = .neutral
        case .current(_, let supported):
            tone = supported ? .ok : .warning
            detail.append(supported
                ? "When Valve releases a new Steam, NotProton lets it update once signatures for it arrive."
                : "Steam Play may not work until signatures for this build arrive. NotProton checks on its own.")
        case .updateAllowed:
            tone = .ok
        case .waiting(_, let current):
            tone = .warning
            detail.append("Steam keeps build \(SystemStatus.build(current)) until signatures for the new build "
                + "arrive. Then the block lifts on its own.")
        case .unknown(_, let reason):
            tone = .warning
            detail.append(reason + ".")
        }
        if let checked = releasesCheckedDetail { detail.append(checked) }
        return StatusRow(
            title: "Steam updates",
            value: SystemStatus.gateSentence(decision.state),
            tone: tone,
            detail: detail.joined(separator: " "),
            action: releasesCheckAction)
    }

    private func signaturesRow(_ updates: UpdatesSnapshot) -> some View {
        let builds = updates.supportedBuilds.sorted(by: >)
        let listed = builds.prefix(3).map(String.init).joined(separator: ", ")
            + (builds.count > 3 ? " and \(builds.count - 3) more" : "")
        var detail: [String] = []
        if let newest = updates.newestDatabase { detail.append("Newest database: \(newest).") }
        detail.append(updates.feedOff ?? "New databases come from NotProton's signed releases, no app update needed.")
        if let problem = status.releaseProblem { detail.append("Last check: \(problem)") }
        return StatusRow(
            title: "Steam signatures",
            value: builds.isEmpty ? "No Steam build is listed as supported." : "Supported Steam builds: \(listed).",
            tone: builds.isEmpty ? .bad : updates.installedSteam.map { builds.contains($0) } == false ? .warning : .ok,
            detail: detail.joined(separator: " "))
    }

    private func bridgeRow(_ updates: UpdatesSnapshot) -> some View {
        guard let bridge = updates.activeBridge else {
            return StatusRow(
                title: "Steam bridge",
                value: "No Steam bridge fits the active engine.",
                tone: .bad,
                detail: "Games start, but Steam features (achievements, overlay, cloud) do not work. "
                    + "Check for Updates looks for one.")
        }
        return StatusRow(
            title: "Steam bridge",
            value: bridge.label.prefix(1).uppercased() + bridge.label.dropFirst()
                + (bridge.isBundled ? " (built in)." : " (downloaded)."),
            tone: .ok,
            detail: "lsteamclient, steam.exe and the Steam loader patch, built against commit "
                + "\(bridge.engineCommit.prefix(12)).")
    }

    @ViewBuilder
    private func bridgeUpdateRow(_ updates: UpdatesSnapshot) -> some View {
        switch status.bridgeCheck {
        case .available(let release, _)?:
            StatusRow(
                title: "Updates",
                value: "Steam bridge \(release.label) is available.",
                tone: .warning,
                detail: "Installing it needs no Steam restart; games started afterwards use it.",
                secondaryAction: releasesCheckAction,
                action: StatusAction(
                    label: release.root == nil ? "Update" : "Use",
                    isProminent: true,
                    help: "Download if needed, verify and switch to \(release.id).",
                    isEnabled: status.isIdle
                ) { Task { await status.installBridge(release) } })
        case .upToDate?:
            StatusRow(
                title: "Updates",
                value: "Up to date.",
                tone: .ok,
                detail: [releasesCheckedDetail, updates.feedOff].compactMap { $0 }.joined(separator: " "),
                action: releasesCheckAction)
        case .noBridge(let engine)?:
            StatusRow(
                title: "Updates",
                value: "No Steam bridge for \(EngineStore.displayName(engine)) yet.",
                tone: .warning,
                detail: updates.feedOff,
                action: releasesCheckAction)
        case .noEngine?, nil:
            StatusRow(
                title: "Updates",
                value: "Not checked yet.",
                tone: .neutral,
                detail: updates.feedOff,
                action: releasesCheckAction)
        }
    }

    private func bridgeRollbackRow(_ target: BridgeRelease) -> some View {
        StatusRow(
            title: "Previous Steam bridge",
            value: target.label.prefix(1).uppercased() + target.label.dropFirst() + ".",
            tone: .neutral,
            action: StatusAction(
                label: "Roll Back",
                help: "Switch games back to the previous Steam bridge.",
                isEnabled: status.isIdle
            ) { Task { await status.rollbackBridge() } })
    }

    private func fetchAction() -> StatusAction {
        StatusAction(
            label: "Fetch Valve Binaries",
            isProminent: true,
            help: "Download missing Valve binaries.",
            isEnabled: status.isIdle
        ) { Task { await status.fetchValveBinaries() } }
    }

    @ViewBuilder
    private func componentsSection(_ payload: PayloadState) -> some View {
        if let problem = payload.manifestProblem {
            Section("NotProton Components") {
                StatusRow(title: "Components", value: "Component list unreadable.", tone: .bad, detail: problem)
            }
        } else if payload.isComplete {
            Section("NotProton Components") {
                StatusRow(title: "Components", value: "Ready.", tone: .ok)
            }
        } else if payload.isEmpty {
            Section("NotProton Components") {
                StatusRow(title: "Components", value: "Not yet deployed.", tone: .neutral)
            }
        } else {
            Section("NotProton Components") {
                if !payload.missing.isEmpty {
                    let names = payload.missing.map {
                        URL(filePath: $0.path).lastPathComponent
                    }.joined(separator: ", ")
                    StatusRow(
                        title: "Missing",
                        value: names,
                        tone: .bad,
                        action: payload.missing.contains(where: { $0.origin.isFetchable })
                            ? fetchAction() : nil
                    )
                }
                if !payload.overlayShimPresent {
                    StatusRow(title: "Overlay shim", value: "Missing.", tone: .bad)
                }
                if payload.signatureDatabase == nil {
                    StatusRow(title: "Signature database", value: "Missing.", tone: .bad)
                }
            }
        }
    }
}
