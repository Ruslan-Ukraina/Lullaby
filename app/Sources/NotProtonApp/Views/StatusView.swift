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

    private static let updateBlockPrompt =
        "Steam client updates may break NotProton. If you don't want to wait for "
            + "NotProton to be updated to be compatible with future Steam versions at the "
            + "cost of not getting updates to the Steam client, you can stop the Steam "
            + "client from updating itself."

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
                updateBlockRow(snapshot.updateBlocked)
                steamWindowsRow(snapshot.nativeSteamWindows)
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

            componentsSection(snapshot.payload)

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
                        ? "The Steam client will not update itself."
                        : "A Steam client update may break NotProton."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.leading, StatusMetrics.textInset)
        }
        .disabled(!status.isIdle)
        .help("Steam client updates may break NotProton.")
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

    private var blockUpdates: Binding<Bool> {
        Binding(
            get: { status.snapshot?.updateBlocked ?? false },
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
            StatusRow(
                title: EngineStore.displayName(engine.tag),
                value: isActive ? "Active engine." : engineSize(engine.tag),
                tone: isActive ? .ok : .neutral,
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
