import Foundation
import Testing
@testable import LullabySettings

@Suite("The API scout's notice")
struct NoticeRequestTests {
    @Test("A request names the game, the renderer and the API, in the player's language")
    func texts() throws {
        let args = ["game-not-started", "--game", "PEAK", "--renderer", "d3dmetal", "--api", "dx12", "--center-on", "Steam"]
        let en = try NoticeRequest.parse(args, language: .en)
        #expect(en.title == "The game did not start")
        #expect(en.message.contains("PEAK") && en.message.contains("d3dmetal") && en.message.contains("(dx12)"))
        #expect(en.message.contains("Properties, Compatibility"))
        #expect(en.centerOn == "Steam")
        let uk = try NoticeRequest.parse(args, language: .uk)
        #expect(uk.title == "Гра не запустилася" && uk.message.contains("Сумісність"))
        let ru = try NoticeRequest.parse(args, language: .ru)
        #expect(ru.title == "Игра не запустилась" && ru.message.contains("Совместимость"))
    }

    @Test("The timeout is kept between 5 seconds and 10 minutes, 2 minutes by default")
    func timeout() throws {
        let base = ["game-not-started", "--game", "G"]
        #expect(try NoticeRequest.parse(base, language: .en).timeout == 120)
        #expect(try NoticeRequest.parse(base + ["--timeout", "1"], language: .en).timeout == 5)
        #expect(try NoticeRequest.parse(base + ["--timeout", "99999"], language: .en).timeout == 600)
    }

    @Test("A request without a game or with a stray argument is refused")
    func refused() {
        #expect(throws: NoticeRequest.Failure.self) { try NoticeRequest.parse(["game-not-started"], language: .en) }
        #expect(throws: NoticeRequest.Failure.self) { try NoticeRequest.parse(["other"], language: .en) }
        #expect(throws: NoticeRequest.Failure.self) { try NoticeRequest.parse(["game-not-started", "--game"], language: .en) }
        #expect(throws: NoticeRequest.Failure.self) { try NoticeRequest.parse(["game-not-started", "stray"], language: .en) }
    }

    @Test("A picture of one's own can be named for the alert")
    func icon() throws {
        let base = ["game-not-started", "--game", "G"]
        #expect(try NoticeRequest.parse(base, language: .en).icon == nil)
        #expect(try NoticeRequest.parse(base + ["--icon", "/tmp/x.png"], language: .en).icon == "/tmp/x.png")
    }
}
