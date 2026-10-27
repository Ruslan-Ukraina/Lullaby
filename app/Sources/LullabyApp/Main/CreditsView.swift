// Credits (ROADMAP §9.1): every part Lullaby is made of or downloads, its authors and
// its license, as NOTICE lists them. GPL-3.0 asks the interface to show them; the test
// CreditsTests keeps this list and NOTICE in step.

import SwiftUI

struct Credit: Identifiable, Sendable {
    let name: String
    let authors: String
    let license: String
    /// What it does in Lullaby, translated.
    let role: String
    let link: String?
    /// A word NOTICE uses for this part.
    let noticeMarker: String

    var id: String { name }
}

enum Credits {
    static var all: [Credit] {
        [
            Credit(name: "NotProton", authors: "NotProtonNot, Logan (LaganYT)",
                   license: "GPL-3.0", role: tr("The original project this app is a fork of."),
                   link: "https://github.com/NotProtonNot/NotProton", noticeMarker: "NotProtonNot"),
            Credit(name: "Lullaby (Dormison)", authors: "Ruslan_Ukraina",
                   license: "GPL-3.0", role: tr("This fork: the Dormison engine, settings in Steam, this window."),
                   link: nil, noticeMarker: "GPLV3"),
            Credit(name: "Dormison", authors: "kageroumado",
                   license: "LGPL-2.1-or-later", role: tr("The engine: Wine for macOS with msync and native windows."),
                   link: "https://github.com/kageroumado/dormison", noticeMarker: "Dormison"),
            Credit(name: "Wine, wine-staging", authors: tr("The Wine and Wine Staging authors"),
                   license: "LGPL-2.1-or-later", role: tr("Runs Windows programs. Dormison is built on it."),
                   link: "https://www.winehq.org", noticeMarker: "wine-staging"),
            Credit(name: "DXMT", authors: "Feifan He (3Shain) for CodeWeavers",
                   license: "LGPL-2.1-or-later", role: tr("Direct3D 10 and 11 on Metal. Comes with Dormison."),
                   link: "https://github.com/3Shain/dxmt", noticeMarker: "DXMT"),
            Credit(name: "DXVK", authors: "Philip Rebohle",
                   license: "zlib", role: tr("Direct3D 9–11 on Vulkan. Comes with Dormison."),
                   link: "https://github.com/doitsujin/dxvk", noticeMarker: "DXVK"),
            Credit(name: "MoltenVK", authors: "The Brenwill Workshop, The Khronos Group",
                   license: "Apache-2.0", role: tr("Vulkan on Metal. Comes with Dormison."),
                   link: "https://github.com/KhronosGroup/MoltenVK", noticeMarker: "MoltenVK"),
            Credit(name: "lsteamclient", authors: "Valve Corporation",
                   license: "Steamworks SDK License", role: tr("Connects Windows games to the Mac Steam."),
                   link: "https://github.com/ValveSoftware/Proton", noticeMarker: "lsteamclient"),
            Credit(name: "steam-shim", authors: "Valve Corporation (Proton's steam_helper), NotProtonNot",
                   license: "BSD-3-Clause", role: tr("Starts games the way Steam on Windows does."),
                   link: nil, noticeMarker: "steam-shim"),
            Credit(name: "Sevoflurane", authors: "kageroumado",
                   license: "MIT", role: tr("The game settings and the graphics card list follow it."),
                   link: "https://github.com/kageroumado/sevoflurane", noticeMarker: "Sevoflurane"),
            Credit(name: "GCMouse (WineForge)", authors: "Elvin Hayatov",
                   license: "LGPL-2.1-or-later", role: tr("Raw mouse input through GameController, an option in the game settings."),
                   link: "https://github.com/Alien4042x/WineForge", noticeMarker: "Hayatov"),
            Credit(name: "Highball", authors: "gauthierpiarrette",
                   license: "LGPL-2.1-or-later", role: tr("Two engine fixes: memory use and Retina resolution."),
                   link: "https://github.com/gauthierpiarrette/highball-engine", noticeMarker: "Highball"),
            Credit(name: "Sparkle", authors: "Sparkle Project",
                   license: "MIT", role: tr("Updates Lullaby itself."),
                   link: "https://sparkle-project.org", noticeMarker: "Sparkle"),
            Credit(name: "Dobby", authors: "Jmpews",
                   license: "Apache-2.0", role: tr("Hooks functions inside Steam, so Steam shows Steam Play."),
                   link: "https://github.com/jmpews/Dobby", noticeMarker: "Dobby"),
            Credit(name: "cJSON", authors: "Dave Gamble and contributors",
                   license: "MIT", role: tr("Reads JSON inside Steam."),
                   link: nil, noticeMarker: "cJSON"),
            Credit(name: "NVAPI", authors: "NVIDIA",
                   license: "MIT", role: tr("The names and structures behind the NVIDIA Reflex answer for D3DMetal games."),
                   link: "https://github.com/NVIDIA/nvapi", noticeMarker: "nvapi"),
            Credit(name: "mtld3d", authors: "athei",
                   license: "zlib", role: tr("Direct3D 9 on Metal, for games that use it. Downloaded from its author the first time a game needs it."),
                   link: "https://github.com/athei/mtld3d", noticeMarker: "mtld3d"),
            Credit(name: "WineMetalGL", authors: "MetalSharp",
                   license: "LGPL-3.0-or-later", role: tr("OpenGL on Metal, for games that use it. Downloaded from its author the first time a game needs it."),
                   link: "https://github.com/metalsharp/WineMetalGL", noticeMarker: "WineMetalGL"),
            Credit(name: "D3DMetal", authors: "Apple",
                   license: tr("Apple's license"), role: tr("Direct3D 12 on Metal. You add it yourself from Apple's Game Porting Toolkit. Lullaby doesn't distribute it."),
                   link: "https://developer.apple.com/games/game-porting-toolkit/", noticeMarker: "D3DMetal"),
        ]
    }
}

struct CreditsView: View {
    static let windowID = "credits"
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text(verbatim: "Lullaby")
                    .font(.headline)
                Text(tr("Made by Ruslan_Ukraina on the work of these people."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            .padding(.bottom, 12)
            .padding(.horizontal, 20)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Credits.all) { credit in
                        CreditRow(credit: credit)
                    }
                }
                .padding(16)
            }

            Divider()

            Text(tr("Full license texts are in the NOTICE file."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(12)
        }
        .frame(width: 320, height: 420)
        .background(CreditsWindowSetup())
        .onExitCommand { dismissWindow(id: Self.windowID) }
    }
}

/// The credits window keeps only its close button and opens beside the main window.
private struct CreditsWindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowHook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            DispatchQueue.main.async { Self.placeBesideMain(window) }
        }

        static func placeBesideMain(_ window: NSWindow) {
            guard let main = NSApp.windows.first(where: { $0 !== window && $0.identifier?.rawValue.hasPrefix("main") == true }),
                  let screen = main.screen ?? NSScreen.main
            else { return }
            let gap: CGFloat = 12
            let area = screen.visibleFrame
            var x = main.frame.maxX + gap
            if x + window.frame.width > area.maxX { x = main.frame.minX - gap - window.frame.width }
            x = min(max(x, area.minX), area.maxX - window.frame.width)
            let top = min(main.frame.maxY, area.maxY)
            window.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        }
    }
}

private struct CreditRow: View {
    let credit: Credit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                if let link = credit.link, let url = URL(string: link) {
                    Link(credit.name, destination: url)
                        .font(.callout.weight(.semibold))
                } else {
                    Text(credit.name).font(.callout.weight(.semibold))
                }
                Spacer()
                Text(credit.license)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(credit.authors)
                .font(.caption)
            Text(credit.role)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
