// Turns the settings levels into what Dormison reads at every process start
// (dlls/ntdll/unix/env.c, load_sevo_env): `<prefix>/.sevo/bottle.env`, then
// `<prefix>/.sevo/apps/<exe>.env`, a value in a later file overriding the earlier
// one and the process environment, `KEY=` removing a variable.
//
// The line format and the inheritance rules are Sevoflurane's (Core/ConfigMaterializer.swift,
// MIT, Copyright (c) 2026 kageroumado):
// - bottle.env carries every resolved value of the "for all games" level;
// - a game's file carries only what the game sets itself, and a switch it sets is
//   written as =0 or =1 even where it equals the shared value;
// - SEVO_CPU_COUNT=0 is "every processor", written by a game that sets it.
//
// NotProton keeps one prefix per game, so a prefix's bottle.env also holds the two
// lines only that file may carry: WINEMSYNC, which the run script sets at every launch
// and this code never changes under a running game, and SEVO_CLI.
//
// Files carry a header; only files with it are removed or rewritten wholesale. Lines
// the run script owns (SEVO_LOADER in a program's file) are kept.

import Foundation

public enum ConfigMaterializer {
    public static let header = "# written by NotProton; edits are overwritten"

    /// Keys of a program's file that compat_run.sh writes and this code keeps.
    static let runScriptKeys = ["SEVO_LOADER"]

    // MARK: - Lines

    /// bottle.env: the "for all games" level, resolved.
    public static func bottleLines(global: ConfigValues, msync: Bool, cli: String?) -> [String] {
        let stack = ConfigStack(global: global)
        var lines = [
            "# NotProton settings for every game. A game's own values: .sevo/apps/<program>.env",
            "SEVO_RESIZABLE_WINDOWS=\(stack[\.windows].rawValue)",
            "SEVO_UPSCALER=\(stack[\.upscaler].rawValue)",
            "SEVO_FINAL_FILTER=\(stack[\.filter].rawValue)",
            "SEVO_LINEAR_MOUSE=\(stack[\.mouse] == .linear ? "1" : "0")",
        ]
        if stack[\.processors] > 0 { lines.append("SEVO_CPU_COUNT=\(stack[\.processors])") }
        lines += switches.map { "\($0.key)=\(stack[$0.path] ? "1" : "0")" }
        lines += tuningLines(stack)
        lines += gpuLines(stack, explicitAsIs: false)
        if stack[\.fpsLimit] > 0 { lines.append("DXVK_FRAME_RATE=\(stack[\.fpsLimit])") }
        let dxmt = dxmtConfig(stack)
        if !dxmt.isEmpty { lines.append("DXMT_CONFIG=\(dxmt)") }
        if stack[\.dlss] { lines.append("DXMT_ENABLE_NVEXT=1") }
        lines += markers.map { "\($0.key)=\(stack[$0.path] ? "1" : "0")" }
        let dlls = dllOverrides(stack)
        if !dlls.isEmpty { lines.append("NOTPROTON_DLL_OVERRIDES=\(dlls)") }
        lines += global.environment ?? []
        lines.append("NOTPROTON_MSYNC=\(msync ? "1" : "0")")
        if let cli { lines.append("SEVO_CLI=\(cli)") }
        return lines
    }

    /// A program's file: only what the game sets itself.
    public static func gameLines(appID: Int, stack: ConfigStack) -> [String] {
        let game = stack.game
        var lines = ["# app \(appID)" + (game.name.map { " \($0)" } ?? "")]
        if let renderer = game.renderer { lines.append("NOTPROTON_RENDERER=\(renderer.rawValue)") }
        if let windows = game.windows { lines.append("SEVO_RESIZABLE_WINDOWS=\(windows.rawValue)") }
        if let upscaler = game.upscaler { lines.append("SEVO_UPSCALER=\(upscaler.rawValue)") }
        if let filter = game.filter { lines.append("SEVO_FINAL_FILTER=\(filter.rawValue)") }
        // The system curve over a linear shared value needs the key written: bottle.env
        // is read first and an absent key leaves its value standing.
        if let mouse = game.mouse { lines.append("SEVO_LINEAR_MOUSE=\(mouse == .linear ? "1" : "0")") }
        if let processors = game.processors { lines.append("SEVO_CPU_COUNT=\(processors)") }
        lines += switches.compactMap { key, path in game[keyPath: path].map { "\(key)=\($0 ? "1" : "0")" } }
        if game.tuning != nil { lines += tuningLines(stack) }
        if game.gpu != nil { lines += gpuLines(stack, explicitAsIs: true) }
        if let limit = game.fpsLimit { lines.append(limit > 0 ? "DXVK_FRAME_RATE=\(limit)" : "DXVK_FRAME_RATE=") }
        // One variable carries several settings: a game that sets any of them writes
        // the whole value, resolved, and an empty one removes the shared value.
        if game.fpsLimit != nil || game.gpu != nil { lines.append("DXMT_CONFIG=\(dxmtConfig(stack))") }
        if let dlss = game.dlss { lines.append(dlss ? "DXMT_ENABLE_NVEXT=1" : "DXMT_ENABLE_NVEXT=") }
        lines += markers.compactMap { key, path in game[keyPath: path].map { "\(key)=\($0 ? "1" : "0")" } }
        if game.dllOverrides != nil { lines.append("NOTPROTON_DLL_OVERRIDES=\(dllOverrides(stack))") }
        lines += game.environment ?? []
        return lines
    }

    /// Switches that reach a game as one variable each.
    static let switches: [(key: String, path: KeyPath<ConfigValues, Bool?> & Sendable)] = [
        ("MTL_HUD_ENABLED", \.hud),
        ("SEVO_FPS", \.fps),
        ("SEVO_FPS_GRAPH", \.fpsGraph),
        ("SEVO_LARGE_ADDRESS_AWARE", \.largeAddressAware),
        ("ROSETTA_ADVERTISE_AVX", \.avx),
        ("SEVO_CURSOR_CONFINE", \.cursorConfine),
        ("SEVO_FORCE_UMA", \.unifiedMemory),
    ]

    /// Switches compat_run.sh reads and acts on at launch: Wine registry values, and
    /// the DLL overrides DLSS needs next to the renderer's.
    static let markers: [(key: String, path: KeyPath<ConfigValues, Bool?> & Sendable)] = [
        ("NOTPROTON_RETINA", \.retina),
        ("NOTPROTON_EMULATE_MODESET", \.emulateModeset),
        ("NOTPROTON_COMMAND_IS_CTRL", \.commandIsControl),
        ("NOTPROTON_OPTION_IS_ALT", \.optionIsAlt),
        ("NOTPROTON_DLSS", \.dlss),
    ]

    static func tuningLines(_ stack: ConfigStack) -> [String] {
        let preset = stack[\.tuning]
        let custom = stack.game.tuning != nil ? stack.game.tuningParameters : stack.global.tuningParameters
        return preset.parameters(custom: custom).environment.map { "\($0.key)=\($0.value)" }
    }

    static func gpuIdentity(_ stack: ConfigStack) -> GPUIdentity? {
        let preset = stack[\.gpu]
        if preset == .custom {
            return stack.game.gpu != nil ? stack.game.gpuCustom : stack.global.gpuCustom
        }
        return preset.identity
    }

    static let gpuKeys = ["SEVO_GPU_VENDOR_ID", "SEVO_GPU_DEVICE_ID", "SEVO_GPU_NAME", "SEVO_GPU_MEMORY_MB"]

    /// The card a game is told of. A game going back to the engine's own answer over a
    /// shared preset removes the variables (`KEY=`).
    static func gpuLines(_ stack: ConfigStack, explicitAsIs: Bool) -> [String] {
        guard let identity = gpuIdentity(stack) else {
            return explicitAsIs ? gpuKeys.map { "\($0)=" } : []
        }
        var lines = [
            String(format: "SEVO_GPU_VENDOR_ID=0x%04x", identity.vendorID),
            String(format: "SEVO_GPU_DEVICE_ID=0x%04x", identity.deviceID),
        ]
        lines.append(identity.name.isEmpty ? "SEVO_GPU_NAME=" : "SEVO_GPU_NAME=\(identity.name)")
        lines.append(identity.memoryMB.map { "SEVO_GPU_MEMORY_MB=\($0)" } ?? "SEVO_GPU_MEMORY_MB=")
        return lines
    }

    /// DXMT's own options (dxmt.conf syntax, `;`-separated): the frame-rate limit and
    /// the card DXMT's DXGI reports.
    public static func dxmtConfig(_ stack: ConfigStack) -> String {
        var parts: [String] = []
        if stack[\.fpsLimit] > 0 { parts.append("d3d11.preferredMaxFrameRate=\(stack[\.fpsLimit])") }
        if let identity = gpuIdentity(stack) {
            parts.append(String(format: "dxgi.customVendorId=%04x", identity.vendorID))
            parts.append(String(format: "dxgi.customDeviceId=%04x", identity.deviceID))
        }
        return parts.map { $0 + ";" }.joined()
    }

    /// `dll=mode;dll=mode`, the shared overrides with the game's on top, sorted.
    static func dllOverrides(_ stack: ConfigStack) -> String {
        let merged = (stack.global.dllOverrides ?? [:]).merging(stack.game.dllOverrides ?? [:]) { $1 }
        return merged.keys.sorted().map { "\($0)=\(merged[$0]!)" }.joined(separator: ";")
    }

    // MARK: - Files

    public struct Outcome: Equatable, Sendable {
        public var written: [String] = []
        public var removed: [String] = []
    }

    /// Writes one game's prefix: bottle.env and the file of every executable the game has
    /// on record. `cli` is what SEVO_CLI names.
    @discardableResult
    public static func write(
        prefix: URL, appID: Int, stack: ConfigStack, cli: String?
    ) throws -> Outcome {
        var outcome = Outcome()
        let sevo = prefix.appending(path: ".sevo")
        let apps = sevo.appending(path: "apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)

        let bottle = sevo.appending(path: "bottle.env")
        var bottleText = bottleLines(global: stack.global, msync: stack[\.msync], cli: cli)
        // The server and every process of a running game agree on WINEMSYNC; only the
        // run script, before the server starts, changes it.
        let msyncLine = existingLines(bottle, keys: ["WINEMSYNC"])
        bottleText += msyncLine.isEmpty ? ["WINEMSYNC=\(stack[\.msync] ? "1" : "0")"] : msyncLine
        if try writeIfChanged(bottleText, to: bottle) { outcome.written.append("bottle.env") }

        let exes = stack.game.exes ?? []
        let lines = gameLines(appID: appID, stack: stack)
        for exe in exes {
            let file = apps.appending(path: "\(exe).env")
            let kept = existingLines(file, keys: runScriptKeys)
            if try writeIfChanged(lines + kept, to: file) { outcome.written.append("apps/\(exe).env") }
        }
        // A file of ours for an executable the game no longer lists.
        let wanted = Set(exes.map { "\($0).env" })
        for entry in (try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
        where !wanted.contains(entry.lastPathComponent) && entry.pathExtension == "env" {
            guard let text = try? String(contentsOf: entry, encoding: .utf8), text.hasPrefix(header) else { continue }
            let kept = existingLines(entry, keys: runScriptKeys)
            if kept.isEmpty {
                try? FileManager.default.removeItem(at: entry)
            } else {
                _ = try writeIfChanged(["# app \(appID): no settings for this program"] + kept, to: entry)
            }
            outcome.removed.append("apps/\(entry.lastPathComponent)")
        }
        return outcome
    }

    /// Lines of an existing file that set one of `keys`, as they stand.
    static func existingLines(_ url: URL, keys: [String]) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { line in keys.contains { line.hasPrefix($0 + "=") } }
    }

    /// Whole-file rewrite through a temporary file; nothing is written when nothing changed.
    static func writeIfChanged(_ lines: [String], to url: URL) throws -> Bool {
        let text = ([header] + lines).joined(separator: "\n") + "\n"
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == text { return false }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    /// Parses a Dormison env file the way load_sevo_env does: KEY=VALUE, `#` comments,
    /// blanks around the key; a later line wins.
    public static func parse(_ text: String) -> [(key: String, value: String)] {
        var pairs: [(String, String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            pairs.append((key, value))
        }
        return pairs
    }

    /// What the engine ends up with after both files: the process environment as
    /// load_sevo_env leaves it, for tests and the panel's readout.
    public static func effectiveEnvironment(bottle: [String], program: [String]) -> [String: String] {
        var env: [String: String] = [:]
        for (key, value) in parse(bottle.joined(separator: "\n")) {
            env[key] = value.isEmpty ? nil : value
        }
        for (key, value) in parse(program.joined(separator: "\n")) {
            // The engine refuses server-wide keys in a program's file.
            guard !["WINEMSYNC", "WINEESYNC", "WINEFSYNC", "WINEPREFIX", "WINESERVER", "WINEARCH"].contains(key)
            else { continue }
            env[key] = value.isEmpty ? nil : value
        }
        return env
    }
}
