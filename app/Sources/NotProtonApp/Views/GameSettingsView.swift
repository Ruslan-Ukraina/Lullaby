// The "Game Settings" window: edits <prefix>/.sevo/apps/<program>.env, which
// Dormison reads at the next start of the game. See Model/GameSettings.swift.

import SwiftUI

struct GameSettingsView: View {

    let prefix: WinePrefix
    @Environment(\.dismiss) private var dismiss

    @State private var loaded: GameSettingsStore.Loaded?
    @State private var settings = GameSettings()
    @State private var msync = true
    @State private var failure: String?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Settings: \(prefix.title)").font(.headline)
            if let loaded {
                Form {
                    Section("Graphics") {
                        row(
                            "Renderer", info: Self.rendererInfo,
                            picker($settings.renderer, RendererChoice.allCases, label: Self.rendererLabel))
                        row("High resolution (Retina)", info: Self.retinaInfo, flag($settings.retina))
                        row("Metal HUD", info: Self.hudInfo, flag($settings.metalHUD))
                    }
                    Section("Window") {
                        row(
                            "Resizable window", info: Self.windowsInfo,
                            picker($settings.windows, WindowMode.allCases, label: Self.windowLabel))
                    }
                    Section("Picture") {
                        row(
                            "Upscaler", info: Self.upscalerInfo,
                            picker($settings.upscaler, UpscalerChoice.allCases, label: Self.upscalerLabel))
                        row(
                            "Final filter", info: Self.filterInfo,
                            picker($settings.filter, FinalFilter.allCases, label: { $0.rawValue.capitalized }))
                        row("Frame rate counter", info: Self.fpsInfo, flag($settings.fps))
                        row("Frame time graph", info: Self.graphInfo, flag($settings.fpsGraph))
                    }
                    Section("Input") {
                        row("Raw mouse", info: Self.mouseInfo, flag($settings.linearMouse))
                        row("Keep the cursor in the window", info: Self.confineInfo, flag($settings.cursorConfine))
                    }
                    Section("Performance") {
                        row("Processors the game sees", info: Self.cpuInfo, cpuPicker)
                        row("Advertise AVX2 to Rosetta", info: Self.avxInfo, flag($settings.advertiseAVX))
                        row("msync+ (debugging only)", info: Self.msyncInfo, Toggle("", isOn: $msync).labelsHidden())
                    }
                }
                .formStyle(.grouped)
                Text("“From the prefix” takes the value of the prefix-wide profile. Changes apply the next time the game starts.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal)
                .accessibilityIdentifier("game-settings-note-\(loaded.program)")
            } else if didLoad {
                ContentUnavailableView(
                    "Launch the game once",
                    systemImage: "gamecontroller",
                    description: Text(
                        "NotProton learns the game's program name from its first launch."))
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(loaded == nil)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 440)
        .task {
            loaded = GameSettingsStore.load(prefix)
            settings = loaded?.game ?? GameSettings()
            msync = GameSettingsStore.msyncEnabled(prefix)
            didLoad = true
        }
    }

    private func save() {
        guard let loaded else { return }
        do {
            try GameSettingsStore.save(settings, for: prefix, program: loaded.program)
            try GameSettingsStore.setMsync(msync, for: prefix)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func row<Control: View>(_ title: String, info: String, _ control: Control) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                control
                InfoButton(text: info)
            }
        } label: {
            Text(title)
        }
    }

    private func picker<Value: Hashable>(
        _ binding: Binding<Value?>, _ cases: [Value], label: @escaping (Value) -> String
    ) -> some View {
        Picker("", selection: binding) {
            Text("From the prefix").tag(Value?.none)
            ForEach(cases, id: \.self) { Text(label($0)).tag(Value?.some($0)) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func flag(_ binding: Binding<Bool?>) -> some View {
        picker(binding, [true, false], label: { $0 ? "On" : "Off" })
    }

    private var cpuPicker: some View {
        picker($settings.cpuCount, [0, 4, 6, 8, 10, 12, 16], label: { $0 == 0 ? "All" : "\($0)" })
    }

    private static func windowLabel(_ mode: WindowMode) -> String {
        switch mode {
        case .off: "As the game makes it"
        case .fixed: "Fixed-size windows"
        case .window: "Also borderless full screen"
        case .all: "Every window"
        }
    }

    private static func upscalerLabel(_ choice: UpscalerChoice) -> String {
        switch choice {
        case .off: "Off"
        case .lanczos: "Final filter only"
        case .metalfx: "MetalFX Spatial"
        }
    }

    private static func rendererLabel(_ choice: RendererChoice) -> String {
        switch choice {
        case .dxmt: "DXMT (Direct3D 10/11)"
        case .dxvk: "DXVK"
        case .wined3d: "WineD3D"
        }
    }

    static let rendererInfo = "What turns the game's Direct3D into Metal. DXMT is the default for Direct3D 10 and 11. DXVK and WineD3D are fallbacks for games DXMT does not run. Direct3D 12 needs Apple's Game Porting Toolkit, which is not set up yet."
    static let retinaInfo = "Draws at the display's full pixel resolution instead of scaled-up points. Sharper, and slower."
    static let hudInfo = "Shows Apple's Metal performance overlay in the game window."
    static let avxInfo = "Tells the game the CPU supports AVX2. Some games need it, a few crash with it."
    static let windowsInfo = "Lets you resize the game's window while the picture keeps the game's resolution. “Also borderless full screen” turns a borderless full-screen window into an ordinary one you can move."
    static let upscalerInfo = "Draws the game below the screen's resolution and scales it up. MetalFX Spatial suits 3D games."
    static let filterInfo = "How the last scaling step resamples the picture into the window."
    static let fpsInfo = "Shows the frame rate in the game's window."
    static let graphInfo = "Shows a graph of frame times and the 1% low. It includes the counter."
    static let mouseInfo = "Gives the game the mouse movement without macOS pointer acceleration."
    static let confineInfo = "Keeps the cursor inside the window while the game has clipped it."
    static let cpuInfo = "How many processors the game is told the Mac has. Some older games misbehave on many cores."
    static let msyncInfo = "msync+ is Dormison's fast synchronization and stays on. Turn it off only to check whether it causes a problem in this game."
}

struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .help(text)
            .accessibilityLabel("More information")
            .popover(isPresented: $shown) {
                Text(text).padding().frame(width: 280, alignment: .leading)
            }
    }
}
