// notproton-settings: the settings CLI the Steam panel, Dormison's View menu
// (SEVO_CLI) and compat_run.sh call. See NotProtonSettings/SettingsCLI.swift.

import Foundation
import NotProtonSettings

let (cli, arguments) = SettingsCLI.configured(Array(CommandLine.arguments.dropFirst()))
let result = cli.run(arguments)
if !result.output.isEmpty { print(result.output) }
if !result.error.isEmpty { FileHandle.standardError.write(Data((result.error + "\n").utf8)) }
exit(result.status)
