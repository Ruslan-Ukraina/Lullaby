// Texts in the three languages NotProton speaks: English (the base), Ukrainian and
// Russian. One field per language makes a missing translation a compile error;
// LocalizationTests checks that none is empty and that each is translated.

import Foundation

public enum Language: String, CaseIterable, Sendable, Codable {
    case en, uk, ru

    /// Steam's name for its interface language (`SteamClient.Settings.GetCurrentLanguage()`
    /// answers "english", "ukrainian", "russian", ...). Anything else is English.
    public init(steam name: String) {
        switch name.lowercased() {
        case "ukrainian": self = .uk
        case "russian": self = .ru
        default: self = .en
        }
    }

    /// The language of a locale identifier such as `uk_UA` or `ru-RU`, English otherwise.
    public init(locale identifier: String) {
        let code = identifier.lowercased().prefix { $0.isLetter }
        self = Language(rawValue: String(code)) ?? .en
    }
}

public struct L10n: Sendable, Equatable, Codable, Hashable {
    public let en: String
    public let uk: String
    public let ru: String

    public init(_ en: String, uk: String, ru: String) {
        self.en = en
        self.uk = uk
        self.ru = ru
    }

    /// A name that reads the same in every language (DXMT, MetalFX, Lanczos).
    public static func same(_ text: String) -> L10n {
        L10n(text, uk: text, ru: text)
    }

    public subscript(language: Language) -> String {
        switch language {
        case .en: en
        case .uk: uk
        case .ru: ru
        }
    }

    public var all: [String] { [en, uk, ru] }

    /// `self` with `%@` replaced by `value` in each language.
    public func formatted(_ value: L10n) -> L10n {
        L10n(
            en.replacingOccurrences(of: "%@", with: value.en),
            uk: uk.replacingOccurrences(of: "%@", with: value.uk),
            ru: ru.replacingOccurrences(of: "%@", with: value.ru))
    }
}
