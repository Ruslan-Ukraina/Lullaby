// ⚙︎ (Phase 8, owner's edits of 10.10), top to bottom: Reinstall; Install GPTK; Turn Off
// Steam Updates; Access Token… only while releases are private (Phase 6); Steam's and Dormison's versions at the very bottom (read only; a Steam
// build Lullaby has no signatures for is orange, "not checked"). The first time it opens after Install, the Steam
// updates row is highlighted and a short tip explains it (§9.4).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GearPanel: View {
    @Environment(MainModel.self) private var model
    let close: () -> Void
    @State private var showsTip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            action(tr("Reinstall"), systemImage: "arrow.clockwise",
                   detail: tr("Puts every part back in place."),
                   enabled: model.install != .steamMissing) {
                Task { await model.pressReinstall() }
            }
            Divider()
            action(tr("Install GPTK…"), systemImage: "plus",
                   detail: toolkitDetail, enabled: true) {
                chooseToolkit()
            }
            Divider()
            steamUpdatesRow
            if model.privateReleaseRepository != nil {
                Divider()
                action(tr("Access Token…"), systemImage: "key",
                       detail: model.hasReleaseToken
                           ? tr("Saved in the Keychain.")
                           : tr("Needed for updates while Lullaby's releases are private."),
                       enabled: true) {
                    model.tokenPromptShown = true
                }
            }
            Divider()
            versions
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { showsTip = model.highlightSteamUpdates }
    }

    // MARK: Versions

    private var versions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let steam = model.steamVersion {
                versionRow("Steam", steam.build, note: steam.checked ? nil : tr("not checked"))
            } else {
                versionRow("Steam", "—", note: nil)
            }
            versionRow("Dormison", model.engineVersion.map { $0.replacingOccurrences(of: "Dormison ", with: "") } ?? "—",
                       note: nil)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func versionRow(_ name: String, _ value: String, note: String?) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: name)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(verbatim: value)
                .monospacedDigit()
                .textSelection(.enabled)
            if let note {
                Text(note).font(.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(note == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
    }

    // MARK: Steam updates

    private var steamUpdatesRow: some View {
        Toggle(isOn: Binding(
            get: { model.steamUpdatesOff },
            set: { off in close(); Task { await model.setSteamUpdatesOff(off) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Turn Off Steam Updates"))
                Text(model.steamUpdatesOff
                     ? tr("Steam doesn't update at all.")
                     : tr("Lullaby lets Steam update only to versions it supports."))
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
            Text(tr("Steam updates can break Lullaby. Lullaby already holds back Steam versions it doesn't support yet. Turn this on to stop Steam updates completely."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240)
                .padding(12)
        }
    }

    // MARK: GPTK

    private var toolkitDetail: String {
        let toolkits = model.toolkits
        let list = toolkits.installed.joined(separator: ", ")
        var lines = [list.isEmpty
            ? tr("For DirectX 12 games. Download it from Apple first.")
            : tr("Installed: \(list)")]
        for version in toolkits.unusable { lines.append(tr("D3DMetal \(version) needs macOS 27.")) }
        return lines.joined(separator: "\n")
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
                            .fixedSize(horizontal: false, vertical: true)
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
        panel.message = tr("Pick the .dmg you downloaded from Apple. Lullaby copies D3DMetal from it.")
        panel.allowedContentTypes = [UTType(filenameExtension: "dmg") ?? .diskImage]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addToolkit(url) }
    }
}
