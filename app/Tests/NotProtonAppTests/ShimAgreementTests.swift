import Foundation
import Testing

@testable import NotProtonApp

// The app writes the runner and RUN_SCRIPT reads it back, in two languages nothing at build
// time holds together, so a file the shim never checks goes stale. Both lists are parsed out.
@Suite("Shim agreement")
struct ShimAgreementTests {

    private static func runScript() throws -> String {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
    }

    private static func verifyRunnerBlock() throws -> String {
        let script = try runScript()
        let start = try #require(script.range(of: "verify_runner() {"))
        let rest = script[start.upperBound...]
        let end = try #require(rest.range(of: "\n}\n"))
        return String(rest[..<end.lowerBound])
    }

    // The bridge files a loop in the block names, as relative paths: "for f in a b c; do".
    private static func bridgeLists(in block: String) -> [Set<String>] {
        block.split(separator: "\n").compactMap { line in
            guard let marker = line.range(of: "for f in ") else { return nil }
            let tail = line[marker.upperBound...]
            guard let semicolon = tail.firstIndex(of: ";") else { return nil }
            return Set(tail[..<semicolon].split(separator: " ").map(String.init))
        }
    }

    // The B1 ntdll pair is ntdll-patch/b1 work rather than the app's, and what it leaves in
    // the bridge is the manifest's patched entries. The shim compares the engine against
    // exactly those files, one arch at a time.
    @Test("The shim checks the patched ntdll the manifest lists")
    func ntdllArchesAgree() throws {
        let block = try Self.verifyRunnerBlock()
        let patched = try PayloadManifest.bundled().paths(origin: .patched)
        #expect(Set(patched) == ["wine/x86_64-windows/ntdll.dll", "wine/i386-windows/ntdll.dll"])
        let loop = try #require(
            block.split(separator: "\n").first { $0.contains("for arch in ") }, "no arch loop in verify_runner")
        #expect(block.contains("\"$bridge_src/wine/$arch-windows/ntdll.dll\""))
        #expect(block.contains("$engine_root/wine/lib/wine/$arch-windows/ntdll.dll"))
        for path in patched {
            let arch = path.split(separator: "/")[1].replacingOccurrences(of: "-windows", with: "")
            #expect(loop.split(whereSeparator: { $0 == " " || $0 == ";" }).contains(Substring(arch)),
                    "the shim never checks \(path)")
        }
    }

    // lsteamclient stays in the bridge, which Dormison reaches through WINEDLLPATH, so
    // the shim checks the arch copies the app stages there.
    @Test("The shim checks the lsteamclient files the app stages")
    func builtinsAgree() throws {
        let lists = Self.bridgeLists(in: try Self.verifyRunnerBlock())
        #expect(lists.count == 1)
        let staged = Set(BridgePayload.entries.flatMap(\.bridgePaths).filter {
            $0.contains("/") && $0.hasSuffix("lsteamclient.dll") || $0.hasSuffix("/lsteamclient.so")
        })
        #expect(lists.first == staged)
    }

    // A runner write left in the shim is the layout problem coming back: writing into the
    // runner at launch is what failed silently when it needed a permission Steam lacks.
    @Test("The shim no longer writes into the runner")
    func shimOnlyReadsTheRunner() throws {
        let script = try Self.runScript()
        for line in script.split(separator: "\n") {
            let writes = line.contains("cp -f") || line.contains("codesign ")
            let runner = ["$CX_ROOT", "$engine_root", "$wine_unix"].contains { line.contains($0) }
            guard writes, runner else { continue }
            Issue.record("RUN_SCRIPT writes into the runner: \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
}
