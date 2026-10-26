// lullaby-settings: the settings CLI the Steam panel, Dormison's View menu
// (SEVO_CLI) and compat_run.sh call. See LullabySettings/SettingsCLI.swift.

import Foundation
import LullabySettings

// `notice` is the one command that shows a window (Notice.swift); the rest print.
if CommandLine.arguments.dropFirst().first == "notice" {
    exit(Notice.run(Array(CommandLine.arguments.dropFirst(2))))
}

let (cli, arguments) = SettingsCLI.configured(Array(CommandLine.arguments.dropFirst()))
let result = cli.run(arguments)
if !result.output.isEmpty { print(result.output) }
if !result.error.isEmpty { FileHandle.standardError.write(Data((result.error + "\n").utf8)) }
exit(result.status)
