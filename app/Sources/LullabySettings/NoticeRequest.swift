// The one notice the API scout shows (patches/inject/lby-spitfire-apiscout): a game did not
// start on the renderer chosen for it. `lullaby-settings notice game-not-started --game NAME
// --renderer R --api A [--center-on Steam] [--timeout SECONDS]`. The request and its texts are
// plain data so that they can be tested; the window itself is in Sources/lullaby-settings.

import Foundation

public struct NoticeRequest: Equatable, Sendable {
    public var title: String
    public var message: String
    /// The name of the application whose window the alert is centred on, if any.
    public var centerOn: String?
    public var timeout: Int
    /// A bundle (the game's launcher app) whose icon the alert shows; none: the alert shows text only.
    public var iconOf: String?

    public static let gameNotStartedTitle = L10n(
        "The game did not start",
        uk: "Гра не запустилася",
        ru: "Игра не запустилась")

    public static func gameNotStartedMessage(game: String, renderer: String, api: String) -> L10n {
        L10n(
            "\(game) did not start with the \(renderer) renderer (\(api)). In Steam open the game's Properties, Compatibility, and choose another renderer for this game.",
            uk: "\(game) не запустилася з рендерером \(renderer) (\(api)). У Steam відкрийте Властивості гри, Сумісність, і виберіть для цієї гри інший рендерер.",
            ru: "\(game) не запустилась с рендерером \(renderer) (\(api)). В Steam откройте Свойства игры, Совместимость, и выберите для этой игры другой рендерер.")
    }

    public enum Failure: Error, Equatable { case usage(String) }

    public static func parse(_ arguments: [String], language: Language) throws -> NoticeRequest {
        guard arguments.first == "game-not-started" else {
            throw Failure.usage("notice game-not-started --game NAME --renderer R --api A [--center-on APP] [--timeout SECONDS] [--icon-of BUNDLE]")
        }
        var values: [String: String] = [:]
        var rest = Array(arguments.dropFirst())
        while !rest.isEmpty {
            let key = rest.removeFirst()
            guard key.hasPrefix("--"), !rest.isEmpty else { throw Failure.usage("bad argument \(key)") }
            values[key] = rest.removeFirst()
        }
        guard let game = values["--game"], !game.isEmpty else { throw Failure.usage("--game is required") }
        let timeout = values["--timeout"].flatMap(Int.init) ?? 120
        return NoticeRequest(
            title: gameNotStartedTitle[language],
            message: gameNotStartedMessage(
                game: game, renderer: values["--renderer"] ?? "?", api: values["--api"] ?? "?")[language],
            centerOn: values["--center-on"],
            timeout: max(5, min(timeout, 600)),
            iconOf: values["--icon-of"])
    }
}
