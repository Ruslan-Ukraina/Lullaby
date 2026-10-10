// Every text of the main window comes from Localizable.xcstrings (en, uk, ru), read
// from this module's bundle: the app is assembled by make, not Xcode, so SwiftUI's
// default (the main bundle) would find no catalog.

import Foundation

func tr(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: .module)
}

