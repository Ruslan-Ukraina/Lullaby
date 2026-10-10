// Lullaby's recipes: per-game defaults Lullaby knows to work best, between the game's
// own values and "for all games" (DECISIONS A1010-3). A recipe is found by the Steam app id,
// or by an executable the game runs: a non-Steam shortcut has an id of its own on every Mac.
// A recipe never touches the game's files; the player's own choice still wins, and
// "Restore recipe" (the game's reset) goes back to it.

import Foundation

public struct GameRecipe: Sendable, Equatable {
    public let id: String
    public let appIDs: [Int]
    /// Lower-case executable names.
    public let exes: [String]
    public let values: ConfigValues
    /// Why, for the log and the documentation; measured where it says so.
    public let reason: String
}

public enum GameRecipes {
    public static let all: [GameRecipe] = [
        GameRecipe(
            id: "peak", appIDs: [3527290], exes: ["peak.exe"],
            values: { var v = ConfigValues(); v.renderer = .dxmt; return v }(),
            reason: "DXMT 92.9 FPS against D3DMetal 77–78 in the menu (10.10); D3D12 cannot run on D3DMetal (no D3D11On12)"),
        GameRecipe(
            id: "resident-evil-requiem", appIDs: [], exes: ["re9.exe"],
            values: { var v = ConfigValues(); v.renderer = .d3dmetal; return v }(),
            reason: "Direct3D 12 only: D3DMetal (DXMT has no D3D12)"),
    ]

    /// The recipe of a game, by app id first, then by an executable it runs.
    public static func recipe(appID: Int?, exes: [String]?) -> GameRecipe? {
        if let appID, let byID = all.first(where: { $0.appIDs.contains(appID) }) { return byID }
        let names = Set((exes ?? []).map { $0.lowercased() })
        return all.first { !$0.exes.isEmpty && !names.isDisjoint(with: $0.exes) }
    }
}
