import Foundation
import Testing

@testable import LullabyApp

// ROADMAP §2, §9.7: no text of the window without English, Ukrainian and Russian. This
// fails on a key the code uses that the catalog lacks, on a missing or empty
// translation, and on a translation whose %@ count differs from the English.

@Suite("Localization")
struct WindowLocalizationTests {
    static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/LullabyApp")
    static let languages = ["en", "uk", "ru"]

    static func catalog() throws -> [String: [String: String]] {
        let url = sources.appending(path: "Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
        var out: [String: [String: String]] = [:]
        for (key, entry) in strings {
            let locs = entry["localizations"] as? [String: [String: Any]] ?? [:]
            var values: [String: String] = [:]
            for (lang, loc) in locs {
                guard let unit = loc["stringUnit"] as? [String: Any],
                      unit["state"] as? String == "translated",
                      let value = unit["value"] as? String else { continue }
                values[lang] = value
            }
            out[key] = values
        }
        return out
    }

    /// Every tr("…") in the window's code, its interpolations written as %@.
    static func usedKeys() throws -> Set<String> {
        let folder = sources.appending(path: "Main")
        var keys = Set<String>()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        let call = try Regex(#"\btr\("((?:[^"\\]|\\.)*)"\)"#)
        let interpolation = try Regex(#"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: call) {
                guard let literal = match.output[1].substring else { continue }
                keys.insert(String(literal).replacing(interpolation, with: "%@"))
            }
        }
        let app = try String(contentsOf: sources.appending(path: "App.swift"), encoding: .utf8)
        let localized = try Regex(#"String\(localized: "([^"]*)", bundle: \.module\)"#)
        for match in app.matches(of: localized) {
            if let literal = match.output[1].substring { keys.insert(String(literal)) }
        }
        return keys
    }

    @Test("Every text the window uses is in the catalog")
    func everyKeyIsInTheCatalog() throws {
        let used = try Self.usedKeys()
        let catalog = try Self.catalog()
        #expect(used.count > 100)
        let missing = used.subtracting(catalog.keys).sorted()
        #expect(missing.isEmpty, "not in Localizable.xcstrings: \(missing)")
    }

    @Test("Every key has English, Ukrainian and Russian")
    func everyKeyIsTranslated() throws {
        for (key, values) in try Self.catalog() {
            for language in Self.languages {
                let value = values[language]?.trimmingCharacters(in: .whitespaces) ?? ""
                #expect(!value.isEmpty, "\(language) missing for \"\(key)\"")
            }
            let count = key.components(separatedBy: "%@").count
            for language in Self.languages {
                #expect(values[language]?.components(separatedBy: "%@").count == count,
                        "\(language) has another number of %@ in \"\(key)\"")
            }
        }
    }

    @Test("No key is left in the catalog that the code no longer uses")
    func noStaleKeys() throws {
        let stale = Set(try Self.catalog().keys).subtracting(try Self.usedKeys()).sorted()
        #expect(stale.isEmpty, "unused: \(stale)")
    }

    @Test("The built bundle carries the three languages")
    func bundleHasLanguages() throws {
        for language in Self.languages {
            let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"),
                                    "\(language).lproj not in the bundle")
            let bundle = try #require(Bundle(path: path))
            let text = bundle.localizedString(forKey: "Install", value: "<none>", table: "Localizable")
            #expect(text == ["en": "Install", "uk": "Встановити", "ru": "Установить"][language])
        }
    }

    @Test("§9.4 tip is the agreed text in each language")
    func tipText() throws {
        let key = "Steam updates can break NotProton. NotProton already holds back Steam versions it doesn't support yet. Turn this on to stop Steam updates completely."
        let values = try #require(try WindowLocalizationTests.catalog()[key])
        #expect(values["uk"] == "Оновлення Steam можуть зламати NotProton. NotProton уже сам не пропускає версії Steam, які ще не підтримує. Увімкніть, щоб повністю зупинити оновлення Steam.")
        #expect(values["ru"] == "Обновления Steam могут сломать NotProton. NotProton уже сам не пускает версии Steam, которые ещё не поддерживает. Включите, чтобы полностью остановить обновления Steam.")
    }
}

// ROADMAP §9.1: the credits name every part NOTICE names, with its license.
@Suite("Credits")
struct CreditsTests {
    static let notice = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "NOTICE")

    @Test("Every credit is in NOTICE, and every part NOTICE names has a credit")
    func matchesNotice() throws {
        let text = try String(contentsOf: Self.notice, encoding: .utf8)
        let credits = Credits.all
        for credit in credits {
            #expect(text.contains(credit.noticeMarker), "\(credit.name): \"\(credit.noticeMarker)\" not in NOTICE")
            #expect(!credit.license.isEmpty && !credit.authors.isEmpty && !credit.role.isEmpty)
        }
        let parts = ["lsteamclient", "steam-shim", "Sparkle", "JsonCpp", "cJSON", "OpenVR", "Sevoflurane",
                     "NotProtonNot", "Dormison", "Highball", "D3DMetal", "DXMT", "DXVK", "MoltenVK",
                     "Dobby"]
        for part in parts where text.contains(part) {
            #expect(credits.contains { $0.noticeMarker == part || $0.name.contains(part) }, "no credit for \(part)")
        }
    }

    @Test("Every library in vendor/ (vendor/README.md) has a credit and a NOTICE line")
    func vendoredLibraries() throws {
        let repo = Self.notice.deletingLastPathComponent()
        let readme = try String(contentsOf: repo.appending(path: "vendor/README.md"), encoding: .utf8)
        let notice = try String(contentsOf: Self.notice, encoding: .utf8)
        let names = readme.split(separator: "\n").filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
        #expect(!names.isEmpty)
        for name in names {
            #expect(Credits.all.contains { $0.name == name }, "no credit for \(name)")
            #expect(notice.contains(name), "\(name) is not in NOTICE")
        }
    }

    @Test("D3DMetal: Apple's, added by the player, not distributed")
    func d3dmetal() throws {
        let credit = try #require(Credits.all.first { $0.name == "D3DMetal" })
        #expect(credit.authors == "Apple")
        #expect(credit.link == nil || credit.link?.contains("developer.apple.com") == true)
        #expect(credit.role.contains("NotProton doesn't distribute it"))
    }
}
