import Combine
import Foundation

enum InventoryUnit: String, Codable, CaseIterable, Identifiable {
    case piece = "pièce"
    case gram = "g"
    case kilogram = "kg"
    case milliliter = "ml"
    case centiliter = "cl"
    case liter = "l"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .piece: "pce"
        default: rawValue
        }
    }
}

enum StorageLocation: String, Codable, CaseIterable, Identifiable, Hashable {
    case refrigerator
    case roomTemperature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .refrigerator: "Au frigo"
        case .roomTemperature: "À l’air libre"
        }
    }

    var symbol: String {
        switch self {
        case .refrigerator: "refrigerator"
        case .roomTemperature: "cabinet"
        }
    }
}

enum FoodCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case meatAndFish
    case fruitsAndVegetables
    case dairy
    case snacksAndPantry

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meatAndFish: "Viandes & poissons"
        case .fruitsAndVegetables: "Fruits & légumes"
        case .dairy: "Laitages"
        case .snacksAndPantry: "Snacks & épicerie"
        }
    }

    var symbol: String {
        switch self {
        case .meatAndFish: "fish.fill"
        case .fruitsAndVegetables: "carrot.fill"
        case .dairy: "waterbottle.fill"
        case .snacksAndPantry: "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var emoji: String {
        switch self {
        case .meatAndFish: "🍗"
        case .fruitsAndVegetables: "🥕"
        case .dairy: "🥛"
        case .snacksAndPantry: "🛒"
        }
    }
}

struct StockItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var quantity: Double
    var unitRawValue: String
    var storageRawValue: String?
    var categoryRawValue: String?
    var emoji: String?
    var unitPrice: Double?
    var expirationDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double,
        unit: InventoryUnit,
        storage: StorageLocation = .refrigerator,
        category: FoodCategory = .snacksAndPantry,
        emoji: String? = nil,
        unitPrice: Double? = nil,
        expirationDate: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitRawValue = unit.rawValue
        self.storageRawValue = storage.rawValue
        self.categoryRawValue = category.rawValue
        self.emoji = emoji
        self.unitPrice = unitPrice
        self.expirationDate = expirationDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var unit: InventoryUnit {
        get { InventoryUnit(rawValue: unitRawValue) ?? .piece }
        set { unitRawValue = newValue.rawValue }
    }

    var storage: StorageLocation {
        get { StorageLocation(rawValue: storageRawValue ?? "") ?? .refrigerator }
        set { storageRawValue = newValue.rawValue }
    }

    var category: FoodCategory {
        get { FoodCategory(rawValue: categoryRawValue ?? "") ?? .snacksAndPantry }
        set { categoryRawValue = newValue.rawValue }
    }

    var displayEmoji: String {
        let cleaned = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? category.emoji : cleaned
    }

    var formattedQuantity: String {
        let value = quantity.formatted(.number.precision(.fractionLength(0...2)))
        return "\(value) \(unit.shortLabel)"
    }

    var currentStockValue: Double? {
        guard let unitPrice, unitPrice >= 0 else { return nil }
        return quantity * unitPrice
    }

    var isNearlyEmpty: Bool {
        switch unit {
        case .piece: quantity <= 2
        case .gram, .milliliter: quantity <= 150
        case .kilogram, .liter: quantity <= 0.2
        case .centiliter: quantity <= 15
        }
    }
}

struct StockMovement: Identifiable, Codable, Hashable {
    var id: UUID
    var stockItemID: UUID
    var itemName: String
    var delta: Double
    var unitRawValue: String
    var reason: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        stockItemID: UUID,
        itemName: String,
        delta: Double,
        unit: InventoryUnit,
        reason: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.stockItemID = stockItemID
        self.itemName = itemName
        self.delta = delta
        self.unitRawValue = unit.rawValue
        self.reason = reason
        self.createdAt = createdAt
    }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable, Hashable {
    case lunch = "Déjeuner"
    case dinner = "Dîner"

    var id: String { rawValue }
    var symbol: String { self == .lunch ? "sun.max.fill" : "moon.stars.fill" }
}

struct CalendarPreferences: Codable, Hashable {
    var isEnabled = false
    var selectedCalendarIdentifier: String?
    var lunchHour = 12
    var lunchMinute = 30
    var dinnerHour = 19
    var dinnerMinute = 30
    var eventDurationMinutes = 60

    func date(on day: Date, for slot: MealSlot) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = slot == .lunch ? lunchHour : dinnerHour
        components.minute = slot == .lunch ? lunchMinute : dinnerMinute
        components.second = 0
        return Calendar.current.date(from: components) ?? day
    }

    func timeLabel(for slot: MealSlot) -> String {
        date(on: Date(timeIntervalSince1970: 0), for: slot)
            .formatted(date: .omitted, time: .shortened)
    }

    mutating func setTime(_ date: Date, for slot: MealSlot) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        if slot == .lunch {
            lunchHour = components.hour ?? 12
            lunchMinute = components.minute ?? 30
        } else {
            dinnerHour = components.hour ?? 19
            dinnerMinute = components.minute ?? 30
        }
    }
}

struct PlannedMeal: Identifiable, Codable, Hashable {
    var id: UUID
    var recipeID: String
    var recipeName: String
    var scheduledDate: Date
    var slotRawValue: String
    var servings: Int
    var isConsumed: Bool
    var consumedAt: Date?
    var calendarEventIdentifier: String?

    init(
        id: UUID = UUID(),
        recipeID: String,
        recipeName: String,
        scheduledDate: Date,
        slot: MealSlot,
        servings: Int = 2,
        isConsumed: Bool = false,
        calendarEventIdentifier: String? = nil
    ) {
        self.id = id
        self.recipeID = recipeID
        self.recipeName = recipeName
        self.scheduledDate = scheduledDate
        self.slotRawValue = slot.rawValue
        self.servings = servings
        self.isConsumed = isConsumed
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRawValue) ?? .dinner }
        set { slotRawValue = newValue.rawValue }
    }
}

struct ReceiptLineDraft: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Double
    var unit: InventoryUnit
    var isIncluded = true
    var confidence: Double
    var expirationDate: Date? = nil
    var storage: StorageLocation = .refrigerator
    var category: FoodCategory = .snacksAndPantry
    var emoji: String = "🛒"
    var lineTotalPrice: Double? = nil
}

enum KitchenAppliance: String, Codable, CaseIterable, Identifiable, Hashable {
    case oven = "Four"
    case fryingPan = "Poêle"
    case airFryer = "Airfryer"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .oven: "oven"
        case .fryingPan: "frying.pan"
        case .airFryer: "air.purifier"
        }
    }
}

enum DietaryStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case omnivore
    case flexitarian
    case vegetarian
    case pescatarian
    case vegan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .omnivore: "Omnivore"
        case .flexitarian: "Flexitarien"
        case .vegetarian: "Végétarien"
        case .pescatarian: "Pescétarien"
        case .vegan: "Végétalien"
        }
    }
}

enum FoodGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case balanced
    case highProtein
    case quick
    case budget
    case varied

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: "Équilibré"
        case .highProtein: "Riche en protéines"
        case .quick: "Rapide"
        case .budget: "Petit budget"
        case .varied: "Varié"
        }
    }
}

enum StarchPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case rice
    case pasta
    case potatoes
    case couscous
    case quinoa
    case bread
    case lentils
    case chickpeas
    case redBeans

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rice: "Riz"
        case .pasta: "Pâtes"
        case .potatoes: "Pommes de terre"
        case .couscous: "Semoule / couscous"
        case .quinoa: "Quinoa"
        case .bread: "Pain"
        case .lentils: "Lentilles"
        case .chickpeas: "Pois chiches"
        case .redBeans: "Haricots rouges"
        }
    }

    var emoji: String {
        switch self {
        case .rice: "🍚"
        case .pasta: "🍝"
        case .potatoes: "🥔"
        case .couscous: "🥣"
        case .quinoa: "🌾"
        case .bread: "🍞"
        case .lentils: "🫘"
        case .chickpeas: "🫛"
        case .redBeans: "🫘"
        }
    }
}

enum SpiceLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case mild
    case medium
    case hot

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mild: "Doux"
        case .medium: "Relevé"
        case .hot: "Très épicé"
        }
    }
}

struct FoodProfile: Codable, Hashable {
    var firstName = ""
    var dietaryStyle: DietaryStyle = .omnivore
    var goals: Set<FoodGoal> = [.balanced]
    var allergies = ""
    var dislikedFoods = ""
    var favoriteFoods = ""
    var favoriteCuisines = ""
    var additionalInstructions = ""
    var minimumCalories = 500
    var maximumCalories = 700
    var requiresStarch = true
    var allowedStarches: Set<StarchPreference> = Set(StarchPreference.allCases)
    var maximumPrepMinutes = 45
    var spiceLevel: SpiceLevel = .medium
    var hasCompletedOnboarding = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case firstName, dietaryStyle, goals, allergies, dislikedFoods, favoriteFoods
        case favoriteCuisines, additionalInstructions, minimumCalories, maximumCalories
        case requiresStarch, allowedStarches, maximumPrepMinutes, spiceLevel, hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        dietaryStyle = try container.decodeIfPresent(DietaryStyle.self, forKey: .dietaryStyle) ?? .omnivore
        goals = try container.decodeIfPresent(Set<FoodGoal>.self, forKey: .goals) ?? [.balanced]
        allergies = try container.decodeIfPresent(String.self, forKey: .allergies) ?? ""
        dislikedFoods = try container.decodeIfPresent(String.self, forKey: .dislikedFoods) ?? ""
        favoriteFoods = try container.decodeIfPresent(String.self, forKey: .favoriteFoods) ?? ""
        favoriteCuisines = try container.decodeIfPresent(String.self, forKey: .favoriteCuisines) ?? ""
        additionalInstructions = try container.decodeIfPresent(String.self, forKey: .additionalInstructions) ?? ""
        minimumCalories = try container.decodeIfPresent(Int.self, forKey: .minimumCalories) ?? 500
        maximumCalories = try container.decodeIfPresent(Int.self, forKey: .maximumCalories) ?? 700
        requiresStarch = try container.decodeIfPresent(Bool.self, forKey: .requiresStarch) ?? true
        allowedStarches = try container.decodeIfPresent(Set<StarchPreference>.self, forKey: .allowedStarches) ?? Set(StarchPreference.allCases)
        maximumPrepMinutes = try container.decodeIfPresent(Int.self, forKey: .maximumPrepMinutes) ?? 45
        spiceLevel = try container.decodeIfPresent(SpiceLevel.self, forKey: .spiceLevel) ?? .medium
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    var signature: String {
        [
            firstName,
            dietaryStyle.rawValue,
            goals.map(\.rawValue).sorted().joined(separator: ","),
            allergies,
            dislikedFoods,
            favoriteFoods,
            favoriteCuisines,
            additionalInstructions,
            String(minimumCalories),
            String(maximumCalories),
            requiresStarch ? "starch-required" : "starch-optional",
            allowedStarches.map(\.rawValue).sorted().joined(separator: ","),
            String(maximumPrepMinutes),
            spiceLevel.rawValue,
            hasCompletedOnboarding ? "1" : "0"
        ]
        .map(TextNormalizer.normalize)
        .joined(separator: "|")
    }

    var geminiPrompt: String {
        let goalList = goals.isEmpty ? "aucun objectif particulier" : goals.map(\.label).sorted().joined(separator: ", ")
        return """
        Prénom : \(firstName.isEmpty ? "non renseigné" : firstName)
        Régime alimentaire : \(dietaryStyle.label)
        Objectifs culinaires : \(goalList)
        Allergies ou intolérances à exclure absolument : \(allergies.isEmpty ? "aucune renseignée" : allergies)
        Aliments refusés : \(dislikedFoods.isEmpty ? "aucun renseigné" : dislikedFoods)
        Aliments appréciés : \(favoriteFoods.isEmpty ? "aucun renseigné" : favoriteFoods)
        Cuisines appréciées : \(favoriteCuisines.isEmpty ? "aucune renseignée" : favoriteCuisines)
        Calories souhaitées par repas : entre \(minimumCalories) et \(maximumCalories) kcal
        Féculent : \(requiresStarch ? "obligatoire" : "facultatif")
        Féculents autorisés : \(allowedStarches.isEmpty ? "aucun" : allowedStarches.map(\.label).sorted().joined(separator: ", "))
        Temps maximal souhaité : \(maximumPrepMinutes) minutes
        Niveau d'épices : \(spiceLevel.label)
        Consignes personnelles : \(additionalInstructions.isEmpty ? "aucune" : additionalInstructions)
        """
    }
}

struct RecipeIngredient: Hashable, Codable {
    let name: String
    let aliases: [String]
    let quantity: Double
    let unit: InventoryUnit

    init(_ name: String, aliases: [String] = [], quantity: Double, unit: InventoryUnit) {
        self.name = name
        self.aliases = [name] + aliases
        self.quantity = quantity
        self.unit = unit
    }
}

struct Recipe: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let tintName: String
    let durationMinutes: Int
    let baseServings: Int
    let estimatedCalories: Int?
    let starchIngredient: String?
    let ingredients: [RecipeIngredient]
    let steps: [String]

    init(
        id: String,
        name: String,
        subtitle: String,
        symbol: String,
        tintName: String,
        durationMinutes: Int,
        baseServings: Int,
        estimatedCalories: Int? = nil,
        starchIngredient: String? = nil,
        ingredients: [RecipeIngredient],
        steps: [String]
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.symbol = symbol
        self.tintName = tintName
        self.durationMinutes = durationMinutes
        self.baseServings = baseServings
        self.estimatedCalories = estimatedCalories
        self.starchIngredient = starchIngredient
        self.ingredients = ingredients
        self.steps = steps
    }
}

struct RecipeMatch: Identifiable {
    let recipe: Recipe
    let coverage: Double
    let missingIngredients: [String]
    let costEstimate: RecipeCostEstimate

    var id: String { recipe.id }
    var canCook: Bool { missingIngredients.isEmpty }
    var estimatedCost: Double? { costEstimate.estimatedTotal }
}

extension Calendar {
    func startOfWeek(containing date: Date) -> Date {
        var calendar = self
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? startOfDay(for: date)
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var stockItems: [StockItem] = []
    @Published private(set) var movements: [StockMovement] = []
    @Published private(set) var plannedMeals: [PlannedMeal] = []
    @Published private(set) var generatedRecipes: [Recipe] = []
    @Published private(set) var generatedRecipeInventorySignature: String?
    @Published private(set) var kitchenAppliances: Set<KitchenAppliance> = [.oven, .fryingPan]
    @Published private(set) var foodProfile = FoodProfile()
    @Published private(set) var desiredRecipeCount = 5
    @Published private(set) var calendarPreferences = CalendarPreferences()

    private let storageKey = "frigo-pdf.snapshot.v1"

    init() {
        load()
    }

    var allRecipes: [Recipe] {
        generatedRecipes
    }

    var needsGeminiStockClassification: Bool {
        stockItems.contains {
            $0.storageRawValue == nil || $0.categoryRawValue == nil || ($0.emoji?.isEmpty ?? true)
        }
    }

    var inventorySignature: String {
        let itemsSignature = stockItems
            .sorted { TextNormalizer.normalize($0.name) < TextNormalizer.normalize($1.name) }
            .map {
                let expiration = $0.expirationDate?.timeIntervalSince1970.rounded() ?? 0
                return "\(TextNormalizer.normalize($0.name))|\($0.quantity)|\($0.unit.rawValue)|\($0.storage.rawValue)|\($0.category.rawValue)|\($0.unitPrice ?? -1)|\(expiration)"
            }
            .joined(separator: ";")
        let applianceSignature = kitchenAppliances.map(\.rawValue).sorted().joined(separator: ",")
        return "\(itemsSignature)#\(applianceSignature)#\(foodProfile.signature)#\(desiredRecipeCount)#personalized-meals-v4"
    }

    func recipe(id: String) -> Recipe? {
        allRecipes.first { $0.id == id }
    }

    func saveGeneratedRecipes(_ recipes: [Recipe]) {
        generatedRecipes = Array(recipes.prefix(14))
        generatedRecipeInventorySignature = inventorySignature
        persist()
    }

    func saveFoodProfile(_ profile: FoodProfile) {
        foodProfile = profile
        generatedRecipeInventorySignature = nil
        persist()
    }

    func setDesiredRecipeCount(_ count: Int) {
        desiredRecipeCount = min(14, max(1, count))
        generatedRecipeInventorySignature = nil
        persist()
    }

    func saveCalendarPreferences(_ preferences: CalendarPreferences) {
        calendarPreferences = preferences
        persist()
    }

    func applyGeminiClassifications(_ classifications: [StockClassification]) {
        for classification in classifications {
            guard let id = UUID(uuidString: classification.id),
                  let index = stockItems.firstIndex(where: { $0.id == id }) else { continue }
            stockItems[index].storage = classification.storage
            stockItems[index].category = classification.category
            stockItems[index].emoji = classification.emoji
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .first
                .map(String.init)
            if classification.consumeWithinHours > 0,
               stockItems[index].expirationDate == nil {
                stockItems[index].expirationDate = Calendar.current.date(
                    byAdding: .hour,
                    value: min(48, classification.consumeWithinHours),
                    to: .now
                )
            }
            stockItems[index].updatedAt = .now
        }
        persist()
    }

    func setAppliance(_ appliance: KitchenAppliance, enabled: Bool) {
        if enabled {
            kitchenAppliances.insert(appliance)
        } else {
            kitchenAppliances.remove(appliance)
        }
        generatedRecipeInventorySignature = nil
        persist()
    }

    func importLines(_ lines: [ReceiptLineDraft]) {
        for line in lines where line.isIncluded && line.quantity > 0 {
            let normalizedName = TextNormalizer.normalize(line.name)
            if let index = stockItems.firstIndex(where: {
                TextNormalizer.normalize($0.name) == normalizedName && $0.unit == line.unit
            }) {
                let previousQuantity = stockItems[index].quantity
                let previousValue = stockItems[index].unitPrice.map { $0 * previousQuantity }
                stockItems[index].quantity += line.quantity
                stockItems[index].updatedAt = .now
                stockItems[index].storage = line.storage
                stockItems[index].category = line.category
                stockItems[index].emoji = line.emoji
                if let lineTotalPrice = line.lineTotalPrice, lineTotalPrice >= 0 {
                    let combinedValue = (previousValue ?? 0) + lineTotalPrice
                    let pricedQuantity = previousValue == nil ? line.quantity : stockItems[index].quantity
                    if pricedQuantity > 0 {
                        stockItems[index].unitPrice = combinedValue / pricedQuantity
                    }
                }
                if let newExpiration = line.expirationDate {
                    if let currentExpiration = stockItems[index].expirationDate {
                        stockItems[index].expirationDate = min(currentExpiration, newExpiration)
                    } else {
                        stockItems[index].expirationDate = newExpiration
                    }
                }
                movements.insert(StockMovement(
                    stockItemID: stockItems[index].id,
                    itemName: stockItems[index].name,
                    delta: line.quantity,
                    unit: line.unit,
                    reason: "Ticket PDF"
                ), at: 0)
            } else {
                let item = StockItem(
                    name: line.name,
                    quantity: line.quantity,
                    unit: line.unit,
                    storage: line.storage,
                    category: line.category,
                    emoji: line.emoji,
                    unitPrice: line.lineTotalPrice.flatMap { line.quantity > 0 ? $0 / line.quantity : nil },
                    expirationDate: line.expirationDate
                )
                stockItems.append(item)
                movements.insert(StockMovement(
                    stockItemID: item.id,
                    itemName: item.name,
                    delta: line.quantity,
                    unit: line.unit,
                    reason: "Ticket PDF"
                ), at: 0)
            }
        }
        persist()
    }

    func saveStockItem(_ item: StockItem, previousQuantity: Double? = nil) {
        if let index = stockItems.firstIndex(where: { $0.id == item.id }) {
            let oldQuantity = previousQuantity ?? stockItems[index].quantity
            stockItems[index] = item
            let delta = item.quantity - oldQuantity
            if abs(delta) > 0.001 {
                movements.insert(StockMovement(
                    stockItemID: item.id,
                    itemName: item.name,
                    delta: delta,
                    unit: item.unit,
                    reason: "Correction manuelle"
                ), at: 0)
            }
        } else {
            stockItems.append(item)
            movements.insert(StockMovement(
                stockItemID: item.id,
                itemName: item.name,
                delta: item.quantity,
                unit: item.unit,
                reason: "Ajout manuel"
            ), at: 0)
        }
        persist()
    }

    func deleteStockItem(id: UUID) {
        stockItems.removeAll { $0.id == id }
        persist()
    }

    func clearInventory() {
        stockItems.removeAll()
        movements.removeAll()
        persist()
    }

    func addMeal(_ meal: PlannedMeal) {
        plannedMeals.append(meal)
        persist()
    }

    func moveMeal(id: UUID, to date: Date) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == id }) else { return }
        plannedMeals[index].scheduledDate = date
        persist()
    }

    func deleteMeal(id: UUID) {
        plannedMeals.removeAll { $0.id == id }
        persist()
    }

    func consumeMeal(id: UUID) throws {
        guard let mealIndex = plannedMeals.firstIndex(where: { $0.id == id }),
              !plannedMeals[mealIndex].isConsumed,
              let recipe = recipe(id: plannedMeals[mealIndex].recipeID) else { return }

        let meal = plannedMeals[mealIndex]
        let ratio = Double(meal.servings) / Double(recipe.baseServings)

        for ingredient in recipe.ingredients {
            guard let stockIndex = stockItems.firstIndex(where: {
                TextNormalizer.matches($0.name, aliases: ingredient.aliases) &&
                UnitConverter.convert($0.quantity, from: $0.unit, to: ingredient.unit) != nil
            }) else { continue }

            let required = ingredient.quantity * ratio
            guard let requiredInStockUnit = UnitConverter.convert(
                required,
                from: ingredient.unit,
                to: stockItems[stockIndex].unit
            ) else { continue }

            let removed = min(stockItems[stockIndex].quantity, requiredInStockUnit)
            stockItems[stockIndex].quantity = max(0, stockItems[stockIndex].quantity - removed)
            stockItems[stockIndex].updatedAt = .now
            movements.insert(StockMovement(
                stockItemID: stockItems[stockIndex].id,
                itemName: stockItems[stockIndex].name,
                delta: -removed,
                unit: stockItems[stockIndex].unit,
                reason: recipe.name
            ), at: 0)
        }

        plannedMeals[mealIndex].isConsumed = true
        plannedMeals[mealIndex].consumedAt = .now
        persist()
    }

    private func persist() {
        let snapshot = Snapshot(
            stockItems: stockItems,
            movements: movements,
            plannedMeals: plannedMeals,
            generatedRecipes: generatedRecipes,
            kitchenAppliances: Array(kitchenAppliances),
            generatedRecipeInventorySignature: generatedRecipeInventorySignature,
            foodProfile: foodProfile,
            desiredRecipeCount: desiredRecipeCount,
            calendarPreferences: calendarPreferences
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        stockItems = snapshot.stockItems
        movements = snapshot.movements
        generatedRecipes = snapshot.generatedRecipes ?? []
        kitchenAppliances = Set(snapshot.kitchenAppliances ?? [.oven, .fryingPan])
        generatedRecipeInventorySignature = snapshot.generatedRecipeInventorySignature
        foodProfile = snapshot.foodProfile ?? FoodProfile()
        desiredRecipeCount = snapshot.desiredRecipeCount ?? 5
        calendarPreferences = snapshot.calendarPreferences ?? CalendarPreferences()
        plannedMeals = snapshot.plannedMeals.map { meal in
            var updated = meal
            let time = Calendar.current.dateComponents([.hour, .minute], from: meal.scheduledDate)
            if time.hour == 0 && time.minute == 0 {
                updated.scheduledDate = calendarPreferences.date(on: meal.scheduledDate, for: meal.slot)
            }
            return updated
        }
    }

    private struct Snapshot: Codable {
        let stockItems: [StockItem]
        let movements: [StockMovement]
        let plannedMeals: [PlannedMeal]
        let generatedRecipes: [Recipe]?
        let kitchenAppliances: [KitchenAppliance]?
        let generatedRecipeInventorySignature: String?
        let foodProfile: FoodProfile?
        let desiredRecipeCount: Int?
        let calendarPreferences: CalendarPreferences?
    }
}
