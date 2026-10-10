// Credits (ROADMAP §9.1): every part NotProton is made of or downloads, its authors and
// its license, as NOTICE lists them. GPL-3.0 asks the interface to show them; the test
// CreditsTests keeps this list and NOTICE in step.

import SwiftUI

struct Credit: Identifiable, Sendable {
    let name: String
    let authors: String
    let license: String
    /// What it does in NotProton, translated.
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
            Credit(name: "NotProton (Dormison)", authors: "Ruslan_Ukraina",
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
            Credit(name: "OpenVR", authors: "Valve Corporation",
                   license: "BSD-3-Clause", role: tr("Headers used to build steam-shim."),
                   link: "https://github.com/ValveSoftware/openvr", noticeMarker: "OpenVR"),
            Credit(name: "Sevoflurane", authors: "kageroumado",
                   license: "MIT", role: tr("The game settings and the graphics card list follow it."),
                   link: "https://github.com/kageroumado/sevoflurane", noticeMarker: "Sevoflurane"),
            Credit(name: "Highball", authors: "gauthierpiarrette",
                   license: "LGPL-2.1-or-later", role: tr("Two engine fixes: memory use and Retina resolution."),
                   link: "https://github.com/gauthierpiarrette/highball-engine", noticeMarker: "Highball"),
            Credit(name: "Mullion", authors: "dttdrv",
                   license: "LGPL-2.1-or-later", role: tr("Experimental Direct3D 10–12 renderer. Downloaded only if you pick it."),
                   link: "https://github.com/dttdrv/mullion", noticeMarker: "Mullion"),
            Credit(name: "Sparkle", authors: "Sparkle Project",
                   license: "MIT", role: tr("Updates NotProton itself."),
                   link: "https://sparkle-project.org", noticeMarker: "Sparkle"),
            Credit(name: "JsonCpp", authors: "Baptiste Lepilleur and contributors",
                   license: "Public domain / MIT", role: tr("Reads JSON in steam-shim."),
                   link: nil, noticeMarker: "JsonCpp"),
            Credit(name: "cJSON", authors: "Dave Gamble and contributors",
                   license: "MIT", role: tr("Reads JSON inside Steam."),
                   link: nil, noticeMarker: "cJSON"),
            Credit(name: "D3DMetal", authors: "Apple",
                   license: tr("Apple's license"), role: tr("Direct3D 12 on Metal. You add it yourself from Apple's Game Porting Toolkit. NotProton doesn't distribute it."),
                   link: "https://developer.apple.com/games/game-porting-toolkit/", noticeMarker: "D3DMetal"),
        ]
    }
}

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text(verbatim: "NotProton")
                    .font(.headline)
                Text(tr("Made by Ruslan_Ukraina on the work of these people."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18)
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

            HStack {
                Text(tr("Full license texts are in the NOTICE file."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 320, height: 400)
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
