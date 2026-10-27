// Turns the settings levels into what Dormison reads at every process start
// (dlls/ntdll/unix/env.c, load_sevo_env): `<prefix>/.sevo/bottle.env`, then
// `<prefix>/.sevo/apps/<exe>.env`, a value in a later file overriding the earlier
// one and the process environment, `KEY=` removing a variable.
//
// The line format and the inheritance rules are Sevoflurane's (Core/ConfigMaterializer.swift,
// MIT, Copyright (c) 2026 kageroumado):
// - bottle.env carries every resolved value of the "for all games" level;
// - a game's file carries only what the game sets itself, and a switch it sets is
//   written as =0 or =1 even where it equals the shared value.
//
// The graphics card is not a setting: every game is told the same NVIDIA card under the Mac's
// chip name (GPUIdentity.current), and DXVK's part of it is a dxvk.conf in the game's prefix.
//
// Lullaby keeps one prefix per game, so a prefix's bottle.env also holds the two
// lines only that file may carry: WINEMSYNC, which the run script sets at every launch
// and this code never changes under a running game, and SEVO_CLI.
//
// Files carry a header; only files with it are removed or rewritten wholesale. Lines
// the run script owns (SEVO_LOADER in a program's file) are kept.

import Foundation

public enum ConfigMaterializer {
    public static let header = "# written by Lullaby; edits are overwritten"
    /// The same header from before the rename (NotProton until 10.10.2026): a file with it
    /// is the catalog's as well, so it is rewritten, never migrated as a player's file.
    static let legacyHeaders = ["# written by NotProton; edits are overwritten"]

    /// The file is one this code wrote, under the current name or an earlier one.
    public static func isOurs(_ text: String) -> Bool {
        ([header] + legacyHeaders).contains { text.hasPrefix($0) }
    }

    /// Keys of a program's file that compat_run.sh writes and this code keeps.
    static let runScriptKeys = ["SEVO_LOADER"]

    // MARK: - Lines

    /// bottle.env: the "for all games" level, resolved.
    /// `d3dmetal` is the directory of the D3DMetal version games get (D3DMetalStore.active),
    /// which compat_run.sh delivers into the engine for a game on the D3DMetal renderer.
    public static func bottleLines(global: ConfigValues, msync: Bool, cli: String?, d3dmetal: String? = nil) -> [String] {
        let stack = ConfigStack(global: global)
        var lines = [
            "# Lullaby settings for every game. A game's own values: .sevo/apps/<program>.env",
            "SEVO_UPSCALER=\(stack[\.upscaler].rawValue)",
            "SEVO_FINAL_FILTER=\(stack[\.filter].rawValue)",
        ]
        lines += fixedLines
        lines += switches.map { "\($0.key)=\(stack[$0.path] ? "1" : "0")" }
        lines += engineCounterOff
        lines += tuningLines(stack)
        lines += gpuLines(stack)
        // A directory's URL path ends in "/"; the run script joins its own parts to it.
        if let d3dmetal {
            let path = d3dmetal.hasSuffix("/") ? String(d3dmetal.dropLast()) : d3dmetal
            lines.append("LULLABY_D3DMETAL=\(path)")
        }
        lines += markers.map { "\($0.key)=\(stack[$0.path] ? "1" : "0")" }
        lines.append("LULLABY_MSYNC=\(msync ? "1" : "0")")
        if let cli { lines.append("SEVO_CLI=\(cli)") }
        return lines
    }

    /// A program's file: only what the game sets itself.
    public static func gameLines(appID: Int, stack: ConfigStack) -> [String] {
        let game = stack.gameWithRecipe
        var lines = ["# app \(appID)" + (game.name.map { " \($0)" } ?? "")]
        if let renderer = game.renderer { lines.append("LULLABY_RENDERER=\(renderer.rawValue)") }
        if let upscaler = game.upscaler { lines.append("SEVO_UPSCALER=\(upscaler.rawValue)") }
        if let filter = game.filter { lines.append("SEVO_FINAL_FILTER=\(filter.rawValue)") }
        lines += switches.compactMap { key, path in game[keyPath: path].map { "\(key)=\($0 ? "1" : "0")" } }
        if game.tuning != nil { lines += tuningLines(stack) }
        lines += markers.compactMap { key, path in game[keyPath: path].map { "\(key)=\($0 ? "1" : "0")" } }
        lines += stack.fixLines
        return lines
    }

    /// Switches that reach a game as one variable each.
    static let switches: [(key: String, path: KeyPath<ConfigValues, Bool?> & Sendable)] = [
        ("MTL_HUD_ENABLED", \.fps),
        ("LULLABY_GAME_MODE", \.gameMode),
        ("SEVO_FORCE_UMA", \.unifiedMemory),
        ("LULLABY_FORCE_VSYNC", \.forceVsync),
        ("LULLABY_GCMOUSE", \.rawMouse),
    ]

    /// What is no setting any more: it is the same for every game and for every level, so
    /// a value an older version stored for it (the fields stay in ConfigValues so old files
    /// decode) changes nothing. No frame limit (the game's and the screen's own pacing), the
    /// engine's pointer curve off (the raw GameController path is the mouse's), its scale automatic
    /// (from the mouse's resolution, 30 % when it reports none), 4 GB for every 32-bit game (the engine applies it to 32-bit programs
    /// only), and NVIDIA Reflex answered by Lullaby for D3DMetal games that use it (LULLABY_LOW_LATENCY=1; since the pacing
    /// holds one frame deeper under V-Sync it costs no frames: RE9's menu 98 a second, 96.5 without Reflex, 84 with the old
    /// rule, 5 runs, 2026-10-23; the launch option LULLABY_LOW_LATENCY=0 turns it off for one run).
    /// Display mode emulation is not here: compat_run.sh turns it on for a 32-bit program.
    ///
    /// Also fixed: AVX advertised to games (Rosetta), DLSS through MetalFX (DXMT's switch and
    /// D3DMetal's; Sevoflurane's Core/BottleGraphics.swift names them, they do nothing under the
    /// other renderers) with no DXMT swapchain upscaler (the final filter has MetalFX Spatial),
    /// and msync+ (a launch option can still turn a variable off for one run: LULLABY_DLSS=0,
    /// WINEMSYNC=0).
    static let fixedLines = [
        "SEVO_RESIZABLE_WINDOWS=fixed",
        "ROSETTA_ADVERTISE_AVX=1",
        "DXMT_ENABLE_NVEXT=1",
        "D3DM_ENABLE_METALFX=1",
        "LULLABY_DLSS=1",
        "DXMT_METALFX_SPATIAL_SWAPCHAIN=0",
        "SEVO_FPS_LIMIT=0",
        "SEVO_LINEAR_MOUSE=0",
        "LULLABY_GCMOUSE_SCALE=auto",
        "SEVO_LARGE_ADDRESS_AWARE=1",
        "LULLABY_LOW_LATENCY=1",
    ]

    /// Dormison's own counter and graph stay off: the panel's counter is the Metal HUD
    /// (Amendment 09.10). The game's View menu can still show them for a session.
    static let engineCounterOff = ["SEVO_FPS=0", "SEVO_FPS_GRAPH=0"]

    /// Switches compat_run.sh reads and acts on at launch: Wine registry values, and
    /// the DLL overrides DLSS needs next to the renderer's.
    static let markers: [(key: String, path: KeyPath<ConfigValues, Bool?> & Sendable)] = [
        ("LULLABY_RETINA", \.retina),
    ]

    static func tuningLines(_ stack: ConfigStack) -> [String] {
        let preset = stack[\.tuning]
        let game = stack.gameWithRecipe
        let custom = game.tuning != nil ? game.tuningParameters : stack.global.tuningParameters
        return preset.parameters(custom: custom).environment.map { "\($0.key)=\($0.value)" }
    }

    /// Every variable the card is named by: the engine's (win32u and wined3d, with the
    /// driver Windows keeps in its registry), DXMT's and DXVK's DXGI, and D3DMetal's.
    public static let gpuKeys = [
        "SEVO_GPU_VENDOR_ID", "SEVO_GPU_DEVICE_ID", "SEVO_GPU_NAME", "SEVO_GPU_MEMORY_MB",
        "SEVO_GPU_DRIVER_VERSION", "SEVO_GPU_DRIVER_DATE", "SEVO_GPU_DRIVER_PROVIDER",
        "DXMT_CONFIG", "DXVK_CONFIG_FILE", "D3DM_VENDOR_ID", "D3DM_DEVICE_ID", "D3DM_DEVICE_DESCRIPTION",
    ]

    /// Where DXVK reads its options, as Windows names it: DXVK-macOS reads DXVK_CONFIG_FILE
    /// through Win32 (Sevoflurane's Core/GPUIdentity.swift, MIT).
    static let dxvkConfigWindowsPath = #"C:\windows\dxvk.conf"#
    static let dxvkConfigPrefixPath = "drive_c/windows/dxvk.conf"

    public static func gpu(_ stack: ConfigStack) -> GPUIdentity { .current }

    /// The card a game is told of, in every layer's own spelling.
    static func gpuLines(_ stack: ConfigStack) -> [String] {
        let card = gpu(stack)
        let vendor = String(format: "0x%04X", card.vendorID)
        let device = String(format: "0x%04X", card.deviceID)
        return [
            "SEVO_GPU_VENDOR_ID=\(vendor)",
            "SEVO_GPU_DEVICE_ID=\(device)",
            "SEVO_GPU_NAME=\(card.name)",
            "SEVO_GPU_MEMORY_MB=\(card.memoryMB)",
            "SEVO_GPU_DRIVER_VERSION=\(card.driverVersion)",
            "SEVO_GPU_DRIVER_DATE=\(card.driverDate)",
            "SEVO_GPU_DRIVER_PROVIDER=\(card.driverProvider)",
            "DXMT_CONFIG=\(dxmtConfig(stack))",
            "DXVK_CONFIG_FILE=\(dxvkConfigWindowsPath)",
            "D3DM_VENDOR_ID=\(vendor)",
            "D3DM_DEVICE_ID=\(device)",
            "D3DM_DEVICE_DESCRIPTION=\(card.name)",
        ]
    }

    /// DXMT's options: the card.
    static func dxmtConfig(_ stack: ConfigStack) -> String { dxgiConfig(gpu(stack)) }

    /// DXGI's options in the shape DXMT and DXVK both parse (`dxgi_options.cpp`): an id as
    /// four bare hex digits, a value with a space quoted. DXMT passes over the memory key.
    public static func dxgiConfig(_ card: GPUIdentity) -> String {
        [
            String(format: "dxgi.customVendorId = %04x", card.vendorID),
            String(format: "dxgi.customDeviceId = %04x", card.deviceID),
            "dxgi.customDeviceDesc = \"\(card.name)\"",
            "dxgi.maxDeviceMemory = \(card.memoryMB)",
        ].joined(separator: "; ")
    }

    /// The same options as dxvk.conf, one per line; the first line is a comment to DXVK.
    static func dxvkConfigFile(_ card: GPUIdentity) -> String {
        """
        # written by Lullaby; edits are overwritten
        dxgi.customVendorId = \(String(format: "%04x", card.vendorID))
        dxgi.customDeviceId = \(String(format: "%04x", card.deviceID))
        dxgi.customDeviceDesc = "\(card.name)"
        dxgi.maxDeviceMemory = \(card.memoryMB)

        """
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
        prefix: URL, appID: Int, stack: ConfigStack, cli: String?, d3dmetal: String? = nil
    ) throws -> Outcome {
        var outcome = Outcome()
        let sevo = prefix.appending(path: ".sevo")
        let apps = sevo.appending(path: "apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)

        let bottle = sevo.appending(path: "bottle.env")
        var bottleText = bottleLines(global: stack.global, msync: true, cli: cli, d3dmetal: d3dmetal)
        // The server and every process of a running game agree on WINEMSYNC; only the
        // run script, before the server starts, changes it.
        let msyncLine = existingLines(bottle, keys: ["WINEMSYNC"])
        bottleText += msyncLine.isEmpty ? ["WINEMSYNC=1"] : msyncLine
        if try writeIfChanged(bottleText, to: bottle) { outcome.written.append("bottle.env") }

        // DXVK's file in the game's own prefix, so the card is the game's (DLSS included).
        // A dxvk.conf someone else wrote is left alone.
        let dxvk = prefix.appending(path: dxvkConfigPrefixPath)
        let existing = try? String(contentsOf: dxvk, encoding: .utf8)
        let dxvkText = dxvkConfigFile(gpu(stack))
        if existing.map({ isOurs($0) && $0 != dxvkText }) ?? true,
            FileManager.default.fileExists(atPath: dxvk.deletingLastPathComponent().path(percentEncoded: false))
        {
            try dxvkText.write(to: dxvk, atomically: true, encoding: .utf8)
            outcome.written.append(dxvkConfigPrefixPath)
        }

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
            guard let text = try? String(contentsOf: entry, encoding: .utf8), isOurs(text) else { continue }
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
