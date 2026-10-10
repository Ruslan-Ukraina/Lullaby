import Testing
@testable import NotProtonSettings

@Suite("Game recipes")
struct GameRecipesTests {
    @Test("A recipe is found by the Steam app id, or by an executable for a shortcut")
    func lookup() {
        #expect(GameRecipes.recipe(appID: 3527290, exes: nil)?.id == "peak")
        #expect(GameRecipes.recipe(appID: 4022369388, exes: ["RE9.exe"])?.id == "resident-evil-requiem")
        #expect(GameRecipes.recipe(appID: 227300, exes: ["eurotrucks2.exe"]) == nil)
    }

    @Test("Own value over the recipe, the recipe over for-all-games")
    func order() {
        var global = ConfigValues(); global.retina = false
        var recipe = ConfigValues(); recipe.renderer = .dxmt; recipe.retina = true
        var own = ConfigValues()
        #expect(ConfigStack(global: global, recipe: recipe, game: own).value(\.renderer) == (.dxmt, .recipe))
        #expect(ConfigStack(global: global, recipe: recipe, game: own).value(\.retina) == (true, .recipe))
        own.renderer = .d3dmetal
        #expect(ConfigStack(global: global, recipe: recipe, game: own).value(\.renderer) == (.d3dmetal, .game))
    }

    @Test("A program's file carries the recipe's values the game does not set itself")
    func gameLines() {
        var recipe = ConfigValues(); recipe.renderer = .dxmt
        let lines = ConfigMaterializer.gameLines(appID: 3527290, stack: ConfigStack(global: .empty, recipe: recipe))
        #expect(lines.contains("NOTPROTON_RENDERER=dxmt"))
        var own = ConfigValues(); own.renderer = .dxvk
        let mine = ConfigMaterializer.gameLines(appID: 3527290, stack: ConfigStack(global: .empty, recipe: recipe, game: own))
        #expect(mine.contains("NOTPROTON_RENDERER=dxvk") && !mine.contains("NOTPROTON_RENDERER=dxmt"))
    }

    @Test("A game's own value equal to its recipe is stored as inherit")
    func ownEqualToRecipe() {
        var recipe = ConfigValues(); recipe.renderer = .dxmt
        var own = ConfigValues(); own.renderer = .dxmt
        #expect(SettingCatalog.withoutInherited(own, level: .game, global: .empty, recipe: recipe).renderer == nil)
        own.renderer = .d3dmetal
        #expect(SettingCatalog.withoutInherited(own, level: .game, global: .empty, recipe: recipe).renderer == .d3dmetal)
    }
}
