import Foundation

enum TextNormalizer {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ product: String, aliases: [String]) -> Bool {
        let normalizedProduct = normalize(product)
        return aliases.contains { alias in
            let normalizedAlias = normalize(alias)
            return normalizedProduct.contains(normalizedAlias) || normalizedAlias.contains(normalizedProduct)
        }
    }
}

enum UnitConverter {
    static func convert(_ value: Double, from: InventoryUnit, to: InventoryUnit) -> Double? {
        if from == to { return value }

        switch (from, to) {
        case (.kilogram, .gram): return value * 1_000
        case (.gram, .kilogram): return value / 1_000
        case (.liter, .milliliter): return value * 1_000
        case (.centiliter, .milliliter): return value * 10
        case (.milliliter, .liter): return value / 1_000
        case (.milliliter, .centiliter): return value / 10
        case (.liter, .centiliter): return value * 100
        case (.centiliter, .liter): return value / 100
        default: return nil
        }
    }
}

struct RecipeCostEstimate: Hashable {
    let knownCost: Double
    let pricedIngredientCount: Int
    let ingredientCount: Int

    var estimatedTotal: Double? { pricedIngredientCount > 0 ? knownCost : nil }
    var isComplete: Bool { ingredientCount > 0 && pricedIngredientCount == ingredientCount }
    var coverage: Double {
        ingredientCount > 0 ? Double(pricedIngredientCount) / Double(ingredientCount) : 0
    }
}

enum LocalRecipeEngine {
    static func matches(for stock: [StockItem], recipes: [Recipe] = RecipeCatalog.all) -> [RecipeMatch] {
        recipes.map { recipe in
            let missing = recipe.ingredients.compactMap { ingredient -> String? in
                let hasEnough = stock.contains { item in
                    guard TextNormalizer.matches(item.name, aliases: ingredient.aliases),
                          let available = UnitConverter.convert(item.quantity, from: item.unit, to: ingredient.unit) else {
                        return false
                    }
                    return available >= ingredient.quantity * 0.8
                }
                return hasEnough ? nil : ingredient.name
            }
            let coverage = recipe.ingredients.isEmpty
                ? 0
                : Double(recipe.ingredients.count - missing.count) / Double(recipe.ingredients.count)
            return RecipeMatch(
                recipe: recipe,
                coverage: coverage,
                missingIngredients: missing,
                costEstimate: costEstimate(for: recipe, stock: stock)
            )
        }
        .sorted {
            if $0.canCook != $1.canCook { return $0.canCook }
            if $0.coverage != $1.coverage { return $0.coverage > $1.coverage }
            return $0.recipe.durationMinutes < $1.recipe.durationMinutes
        }
    }

    static func costEstimate(for recipe: Recipe, stock: [StockItem]) -> RecipeCostEstimate {
        var cost = 0.0
        var pricedCount = 0

        for ingredient in recipe.ingredients {
            guard let item = stock.first(where: {
                TextNormalizer.matches($0.name, aliases: ingredient.aliases) && $0.unitPrice != nil
            }), let unitPrice = item.unitPrice,
                  let requiredInStockUnit = UnitConverter.convert(
                    ingredient.quantity,
                    from: ingredient.unit,
                    to: item.unit
                  ) else { continue }
            cost += max(0, requiredInStockUnit) * max(0, unitPrice)
            pricedCount += 1
        }

        return RecipeCostEstimate(
            knownCost: cost,
            pricedIngredientCount: pricedCount,
            ingredientCount: recipe.ingredients.count
        )
    }
}

enum RecipeCatalog {
    static let all: [Recipe] = [
        Recipe(
            id: "omelette-tomates", name: "Omelette aux tomates", subtitle: "Moelleuse, simple et lumineuse",
            symbol: "sun.max.fill", tintName: "yellow", durationMinutes: 15, baseServings: 1,
            ingredients: [
                RecipeIngredient("Œufs", aliases: ["oeuf"], quantity: 2, unit: .piece),
                RecipeIngredient("Tomates", aliases: ["tomate"], quantity: 150, unit: .gram)
            ],
            steps: ["Coupez les tomates en dés.", "Battez les œufs et assaisonnez.", "Cuisez doucement avec les tomates."]
        ),
        Recipe(
            id: "pates-tomates", name: "Pâtes à la tomate", subtitle: "Le classique qui utilise les essentiels",
            symbol: "fork.knife", tintName: "red", durationMinutes: 25, baseServings: 1,
            ingredients: [
                RecipeIngredient("Pâtes", aliases: ["pate", "spaghetti", "penne", "coquillettes"], quantity: 100, unit: .gram),
                RecipeIngredient("Tomates", aliases: ["tomate", "sauce tomate", "coulis"], quantity: 175, unit: .gram),
                RecipeIngredient("Oignon", aliases: ["oignons"], quantity: 0.5, unit: .piece)
            ],
            steps: ["Faites cuire les pâtes.", "Faites revenir l’oignon et les tomates.", "Mélangez et servez immédiatement."]
        ),
        Recipe(
            id: "riz-legumes", name: "Riz sauté aux légumes", subtitle: "Rapide et parfait pour les restes",
            symbol: "leaf.fill", tintName: "green", durationMinutes: 22, baseServings: 1,
            ingredients: [
                RecipeIngredient("Riz", quantity: 90, unit: .gram),
                RecipeIngredient("Carottes", aliases: ["carotte"], quantity: 100, unit: .gram),
                RecipeIngredient("Œufs", aliases: ["oeuf"], quantity: 1, unit: .piece)
            ],
            steps: ["Cuisez le riz puis laissez-le tiédir.", "Faites sauter les carottes.", "Ajoutez le riz et les œufs battus."]
        ),
        Recipe(
            id: "salade-composee", name: "Salade composée", subtitle: "Fraîche, croquante et modulable",
            symbol: "carrot.fill", tintName: "green", durationMinutes: 12, baseServings: 1,
            ingredients: [
                RecipeIngredient("Salade", aliases: ["laitue", "mâche", "roquette"], quantity: 0.5, unit: .piece),
                RecipeIngredient("Tomates", aliases: ["tomate"], quantity: 125, unit: .gram),
                RecipeIngredient("Concombre", aliases: ["concombres"], quantity: 0.5, unit: .piece)
            ],
            steps: ["Lavez et essorez les légumes.", "Coupez-les en morceaux.", "Assaisonnez juste avant de servir."]
        ),
        Recipe(
            id: "gratin-courgettes", name: "Gratin de courgettes", subtitle: "Doux, doré et réconfortant",
            symbol: "flame.fill", tintName: "orange", durationMinutes: 45, baseServings: 1,
            ingredients: [
                RecipeIngredient("Courgettes", aliases: ["courgette"], quantity: 300, unit: .gram),
                RecipeIngredient("Crème", aliases: ["creme"], quantity: 100, unit: .milliliter),
                RecipeIngredient("Fromage râpé", aliases: ["emmental", "gruyere", "gruyère"], quantity: 50, unit: .gram)
            ],
            steps: ["Préchauffez le four à 190 °C.", "Émincez et précuisez les courgettes.", "Ajoutez la crème, le fromage et gratinez."]
        ),
        Recipe(
            id: "soupe-carottes", name: "Velouté de carottes", subtitle: "Une soupe douce sans complication",
            symbol: "cup.and.saucer.fill", tintName: "orange", durationMinutes: 35, baseServings: 1,
            ingredients: [
                RecipeIngredient("Carottes", aliases: ["carotte"], quantity: 250, unit: .gram),
                RecipeIngredient("Pommes de terre", aliases: ["pomme de terre", "pdt"], quantity: 125, unit: .gram),
                RecipeIngredient("Oignon", aliases: ["oignons"], quantity: 0.5, unit: .piece)
            ],
            steps: ["Épluchez et coupez les légumes.", "Couvrez d’eau et cuisez 25 minutes.", "Mixez jusqu’à obtenir une texture veloutée."]
        ),
        Recipe(
            id: "poulet-riz", name: "Poulet et riz doré", subtitle: "Un plat complet en une poêle",
            symbol: "frying.pan.fill", tintName: "yellow", durationMinutes: 32, baseServings: 1,
            ingredients: [
                RecipeIngredient("Poulet", aliases: ["filet poulet", "escalope poulet"], quantity: 150, unit: .gram),
                RecipeIngredient("Riz", quantity: 90, unit: .gram),
                RecipeIngredient("Oignon", aliases: ["oignons"], quantity: 0.5, unit: .piece)
            ],
            steps: ["Dorez le poulet en morceaux.", "Ajoutez l’oignon puis le riz.", "Mouillez, couvrez et laissez cuire doucement."]
        ),
        Recipe(
            id: "yaourt-fruits", name: "Bol yaourt et fruits", subtitle: "Un dessert frais en trois minutes",
            symbol: "takeoutbag.and.cup.and.straw.fill", tintName: "purple", durationMinutes: 3, baseServings: 1,
            ingredients: [
                RecipeIngredient("Yaourts", aliases: ["yaourt", "fromage blanc"], quantity: 1, unit: .piece),
                RecipeIngredient("Pommes", aliases: ["pomme", "banane", "poire", "fraises"], quantity: 1, unit: .piece)
            ],
            steps: ["Répartissez les yaourts dans deux bols.", "Ajoutez les fruits coupés.", "Servez bien frais."]
        )
    ]

    static func recipe(id: String) -> Recipe? {
        all.first { $0.id == id }
    }
}
