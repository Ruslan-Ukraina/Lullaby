// Path construction for the NotProton support directory and Steam

import Foundation

enum SupportPaths {

    static let supportDirName = "lullaby"
    static let dylibName = "lullaby.dylib"

    static var home: URL {
        URL(filePath: NSHomeDirectory())
    }

    static var applicationSupport: URL {
        home.appending(path: "Library/Application Support")
    }

    // ~/Library/Application Support/lullaby
    static var support: URL {
        applicationSupport.appending(path: supportDirName)
    }

    static var bridge: URL { support.appending(path: "bridge") }
    /// Downloaded Steam bridge builds, one folder each, and state.json naming the
    /// active one and the one Roll Back returns to (BridgeStore).
    static var bridges: URL { support.appending(path: "bridges") }
    /// Verified copies of NotProton's signed release manifests, with their .sig files.
    static var manifests: URL { support.appending(path: "manifests") }
    /// `auto` or `manual`: who keeps Steam's update block (SteamUpdateGate). The dylib
    /// reads it inside Steam, so the name is shared with dylib/feats/updategate.c.
    static var steamUpdateGate: URL { support.appending(path: "steam-update-gate") }
    static var runners: URL { support.appending(path: "runners") }
    static var backups: URL { support.appending(path: "backups") }
    static var launchers: URL { support.appending(path: "launchers") }

    static var signatures: URL {
        support.appending(path: "signatures/macos.arm64")
    }

    static var overlayShim: URL { support.appending(path: "overlay-shim.dylib") }
    static var iconmaker: URL { support.appending(path: "iconmaker") }
    static var appinfo: URL { support.appending(path: "appinfo") }
    static let settingsCLIName = "lullaby-settings"
    /// The settings CLI (LullabySettings): the Steam panel's writer, and what the stand-in
    /// below hands Dormison's View menu calls to.
    static var settingsCLI: URL { support.appending(path: settingsCLIName) }
    // The stand-in Dormison's View menu calls instead of Sevoflurane's CLI, written by
    // compat_run.sh (docs/DECISIONS.md S1).
    static var sevoCLI: URL { support.appending(path: "lullaby-sevo") }

    static var packageDownloads: URL {
        home.appending(path: "Library/Caches/\(supportDirName)/valve-packages")
    }

    /// Engine tarballs while they download (a .part file survives an interruption).
    static var engineDownloads: URL {
        home.appending(path: "Library/Caches/\(supportDirName)/engine")
    }

    /// Steam bridge artifacts while they download.
    static var bridgeDownloads: URL {
        home.appending(path: "Library/Caches/\(supportDirName)/bridge")
    }

    static var deployedVersion: URL { support.appending(path: "dylib.version") }

    static var currentRunner: URL { runners.appending(path: "current") }

    enum Steam {
        static var app: URL { URL(filePath: "/Applications/Steam.app") }
        static var infoPlist: URL { infoPlist(inBundle: app) }
        static var executable: URL { app.appending(path: "Contents/MacOS/steam_osx") }
        static var deployedDylib: URL { deployedDylib(inBundle: app) }

        static func infoPlist(inBundle bundle: URL) -> URL {
            bundle.appending(path: "Contents/Info.plist")
        }

        static func deployedDylib(inBundle bundle: URL) -> URL {
            bundle.appending(path: "Contents/MacOS/\(dylibName)")
        }

        static var userData: URL {
            SupportPaths.applicationSupport.appending(path: "Steam")
        }

        static var configFile: URL { userData.appending(path: "steam.cfg") }

        static var innerApp: URL { userData.appending(path: "Steam.AppBundle/Steam") }
        static var innerInfoPlist: URL { innerApp.appending(path: "Contents/Info.plist") }

        static var innerClient: URL { innerApp.appending(path: "Contents/MacOS") }

        static var innerConfigFile: URL { innerClient.appending(path: "steam.cfg") }
        /// Valve's package manifests (steam_client*_osx.manifest) and `beta`.
        static var package: URL { innerClient.appending(path: "package") }
        static var legacyCompat: URL { innerClient.appending(path: "legacycompat") }

        static var compatTool: URL {
            userData.appending(path: "compatibilitytools.d/lullaby")
        }

        static var libraryFoldersVDF: URL { userData.appending(path: "steamapps/libraryfolders.vdf") }
    }
}
