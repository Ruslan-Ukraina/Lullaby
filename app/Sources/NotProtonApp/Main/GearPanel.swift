// ⚙︎ (ROADMAP §9.1): Steam updates off, roll back the engine or the bridge, Reinstall,
// add the Game Porting Toolkit, open the logs. The first time it opens after Install,
// the Steam updates row is highlighted and a short tip explains it (§9.4).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GearPanel: View {
    @Environment(MainModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let close: () -> Void
    @State private var showsTip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            steamUpdatesRow
            Divider()
            action(tr("Roll Back Engine"), systemImage: "arrow.uturn.backward",
                   detail: model.engineRollback.map { tr("Back to \(EngineStore.displayName($0))") },
                   enabled: model.engineRollback != nil) {
                Task { await model.pressRollbackEngine() }
            }
            action(tr("Roll Back Steam Bridge"), systemImage: "arrow.uturn.backward",
                   detail: model.bridgeRollback.map { tr("Back to \($0.id)") },
                   enabled: model.bridgeRollback != nil) {
                Task { await model.pressRollbackBridge() }
            }
            action(tr("Reinstall"), systemImage: "arrow.clockwise",
                   detail: tr("Puts every part back in place."),
                   enabled: model.install != .steamMissing) {
                Task { await model.pressReinstall() }
            }
            action(tr("Add Game Porting Toolkit…"), systemImage: "plus",
                   detail: tr("For DirectX 12 games. Download it from Apple first."), enabled: true) {
                chooseToolkit()
            }
            Divider()
            action(tr("Open Logs"), systemImage: "doc.text.magnifyingglass",
                   detail: tr("Attach them when you report a problem."), enabled: true) {
                model.revealLogs()
            }
            action(tr("More Settings…"), systemImage: "slider.horizontal.3",
                   detail: tr("Prefixes, backups and the full status, as before."), enabled: true) {
                openWindow(id: "classic")
            }
            if !model.versionsLine.isEmpty {
                Text(model.versionsLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { showsTip = model.highlightSteamUpdates }
    }

    private var steamUpdatesRow: some View {
        Toggle(isOn: Binding(
            get: { model.steamUpdatesOff },
            set: { off in close(); Task { await model.setSteamUpdatesOff(off) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Turn Off Steam Updates"))
                Text(model.steamUpdatesOff
                     ? tr("Steam doesn't update at all.")
                     : tr("NotProton lets Steam update only to versions it supports."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .disabled(model.status.snapshot == nil)
        .padding(6)
        .background(model.highlightSteamUpdates ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 8))
        .popover(isPresented: $showsTip, arrowEdge: .trailing) {
            Text(tr("Steam updates can break NotProton. NotProton already holds back Steam versions it doesn't support yet. Turn this on to stop Steam updates completely."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240)
                .padding(12)
        }
    }

    private func action(
        _ title: String, systemImage: String, detail: String?, enabled: Bool, perform: @escaping () -> Void
    ) -> some View {
        Button {
            close()
            perform()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(detail ?? "")
    }

    /// The toolkit's disk image from Apple (Game Porting Toolkit … .dmg), or the inner one.
    private func chooseToolkit() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose the Game Porting Toolkit")
        panel.message = tr("Pick the .dmg you downloaded from Apple. NotProton copies D3DMetal from it.")
        panel.allowedContentTypes = [UTType(filenameExtension: "dmg") ?? .diskImage]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addToolkit(url) }
    }
}
