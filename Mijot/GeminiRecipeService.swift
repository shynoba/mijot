import Foundation
import Security

enum GeminiKeychain {
    private static let service = "Mijot.Gemini"
    private static let account = "personal-api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        delete()
        let value = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw GeminiServiceError.keychain(status) }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum GeminiRecipeService {
    static let model = "gemini-3.5-flash-lite"

    static func generateRecipes(
        from stock: [StockItem],
        appliances: Set<KitchenAppliance>,
        profile: FoodProfile,
        recipeCount: Int,
        apiKey: String
    ) async throws -> [Recipe] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiServiceError.missingKey }
        guard !stock.isEmpty else { throw GeminiServiceError.emptyInventory }

        let inventory = stock.prefix(80).map {
            let expiration = $0.expirationDate.map {
                "; à consommer avant \($0.formatted(date: .abbreviated, time: .shortened))"
            } ?? ""
            let price = $0.currentStockValue.map {
                "; valeur actuelle \($0.formatted(.currency(code: "EUR").precision(.fractionLength(2))))"
            } ?? "; prix inconnu"
            return "- \($0.name): \($0.quantity.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit.rawValue); \($0.category.label); \($0.storage.label)\(price)\(expiration)"
        }.joined(separator: "\n")
        let applianceList = appliances.isEmpty
            ? "aucun appareil de cuisson (recettes froides uniquement)"
            : appliances.map(\.rawValue).sorted().joined(separator: ", ")

        let prompt = """
        Tu es un diététicien et cuisinier français précis. Propose exactement \(recipeCount) vrais repas complets à partir de l'inventaire ci-dessous. Ne propose ni dessert seul, ni snack seul, ni simple assemblage de deux aliments.

        Profil de la personne à respecter :
        \(profile.geminiPrompt)

        Règles obligatoires :
        - Chaque recette est pour exactement 1 personne : servings vaut toujours 1 et toutes les quantités correspondent à une seule portion.
        - Chaque assiette doit apporter entre \(profile.minimumCalories) et \(profile.maximumCalories) kcal au total. estimatedCalories doit être une estimation réaliste qui inclut tous les ingrédients et l'huile utilisée.
        - Le féculent est \(profile.requiresStarch ? "obligatoire" : "facultatif"). Utilise uniquement cette sélection : \(profile.allowedStarches.map(\.label).sorted().joined(separator: ", ")). Lorsqu'il y en a un, indique-le dans starchIngredient et inclus-le dans ingredients.
        - Repères pour une portion : 70 à 100 g crus de riz/pâtes/semoule/quinoa, 250 à 350 g de pommes de terre, 80 à 120 g de pain, ou 150 à 220 g cuits de lentilles/pois chiches/haricots rouges.
        - Construis si possible l'assiette avec un féculent, une source de protéines et un légume ou fruit. Utilise entre 4 et 7 ingrédients principaux maximum, sans compter sel, poivre et eau.
        - Priorise les aliments disponibles. Tu peux ajouter au maximum deux ingrédients absents lorsque le stock ne contient pas de féculent ou manque d'un élément essentiel à un repas équilibré.
        - Pour tout ingrédient disponible, recopie exactement son nom tel qu'il apparaît dans l'inventaire afin que l'application puisse le reconnaître.
        - Utilise exclusivement ces appareils : \(applianceList).
        - Respecte un temps total maximal de \(profile.maximumPrepMinutes) minutes et un niveau d'épices « \(profile.spiceLevel.label) ».
        - Donne 4 à 7 étapes courtes, concrètes et ordonnées. Mentionne le réglage ou la température de l'appareil lorsque nécessaire.
        - Les aliments dont la date limite est la plus proche doivent être utilisés en premier.
        - Viande et poisson sont souvent vendus par deux tranches ou deux filets. Si le stock permet deux portions et doit être consommé sous 48 h, crée deux recettes réellement différentes d'une personne utilisant chacune environ la moitié, avec des féculents, sauces ou légumes différents. Le sous-titre doit indiquer « portion 1 sur 2 » puis « portion 2 sur 2 ».
        - N'invente pas une quantité supérieure au stock disponible.
        - Les allergies, intolérances, aliments refusés et le régime du profil sont des interdictions strictes. Les goûts, cuisines et objectifs personnels servent à classer et varier les propositions.

        Réponds exclusivement selon le schéma JSON demandé, en français.

        Inventaire :
        \(inventory)
        """

        let ingredientSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "quantity": ["type": "number"],
                "unit": ["type": "string", "enum": InventoryUnit.allCases.map(\.rawValue)]
            ],
            "required": ["name", "quantity", "unit"]
        ]
        let recipeSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "subtitle": ["type": "string"],
                "durationMinutes": ["type": "integer"],
                "servings": ["type": "integer"],
                "estimatedCalories": ["type": "integer", "minimum": profile.minimumCalories, "maximum": profile.maximumCalories],
                "starchIngredient": ["type": "string"],
                "ingredients": ["type": "array", "minItems": 4, "maxItems": 7, "items": ingredientSchema],
                "steps": ["type": "array", "minItems": 4, "maxItems": 7, "items": ["type": "string"]]
            ],
            "required": ["name", "subtitle", "durationMinutes", "servings", "estimatedCalories", "starchIngredient", "ingredients", "steps"]
        ]
        let responseSchema: [String: Any] = [
            "type": "object",
            "properties": ["recipes": ["type": "array", "minItems": recipeCount, "maxItems": recipeCount, "items": recipeSchema]],
            "required": ["recipes"]
        ]

        for attempt in 0..<2 {
            let correction = attempt == 0 ? "" : "\nVérification finale : respecte exactement le nombre demandé, la plage calorique et les choix de féculents."
            let payloadData = try await GeminiAPI.generateJSON(
                model: model,
                apiKey: trimmedKey,
                parts: [["text": prompt + correction]],
                schema: responseSchema
            )
            let payload = try JSONDecoder().decode(GeneratedRecipesPayload.self, from: payloadData)
            let candidates = Array(payload.recipes.prefix(recipeCount))
            guard candidates.count == recipeCount,
                  candidates.allSatisfy({ $0.isValidMeal(for: profile) }) else { continue }
            return candidates.enumerated().map { index, generated in
                generated.recipe(index: index)
            }
        }
        throw GeminiServiceError.invalidResponse
    }
}

enum GeminiReceiptService {
    static let model = "gemini-3.5-flash"

    static func detectFood(in ticket: ExtractedTicket, apiKey: String) async throws -> [ReceiptLineDraft] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiServiceError.missingKey }

        let productSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "quantity": ["type": "number"],
                "unit": ["type": "string", "enum": InventoryUnit.allCases.map(\.rawValue)],
                "confidence": ["type": "number"],
                "consumeWithinHours": ["type": "integer"],
                "storage": ["type": "string", "enum": StorageLocation.allCases.map(\.rawValue)],
                "category": ["type": "string", "enum": FoodCategory.allCases.map(\.rawValue)],
                "emoji": ["type": "string"],
                "lineTotalPrice": ["type": "number", "minimum": 0]
            ],
            "required": ["name", "quantity", "unit", "confidence", "consumeWithinHours", "storage", "category", "emoji", "lineTotalPrice"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["products": ["type": "array", "items": productSchema]],
            "required": ["products"]
        ]
        let prompt = """
        Analyse ce ticket de caisse français comme un expert en courses alimentaires.

        Retourne uniquement les aliments et boissons réellement achetés. N'ajoute jamais comme produit le nom du magasin, l'adresse, le téléphone, les horaires, le SIRET, un prix isolé, la TVA, les totaux, le paiement, la fidélité, les sacs ou une ligne administrative.
        Reconstitue les libellés coupés ou abrégés en noms français lisibles. Garde la marque seulement si elle aide à identifier l'aliment.
        La quantité représente le contenu à ajouter au stock, jamais le prix. Utilise la masse ou le volume imprimé lorsqu'il est fiable ; sinon utilise un nombre de pièces. Pour un lot, multiplie correctement la quantité.
        lineTotalPrice représente en euros le montant réellement payé pour toute la ligne de cet article, après une éventuelle remise immédiatement associée au produit. Pour un article pesé, utilise le prix total de la ligne et non le prix au kilogramme. Pour un lot, utilise le total du lot. Ignore les remises globales, les cagnottes et les totaux du ticket. Si le prix ne peut pas être relié avec certitude à l'article, mets 0.
        Pour toute viande fraîche ou tout poisson frais, consumeWithinHours vaut 48. Pour tous les autres aliments, la valeur vaut 0. Ne mets jamais 48 pour les conserves, produits surgelés ou produits secs.
        Détermine aussi le rangement : refrigerator seulement pour les viandes et poissons frais, laitages réfrigérés, plats frais et produits dont la chaîne du froid est nécessaire. roomTemperature pour les noix, biscuits, pâtes, riz, céréales, conserves, épices, huiles, boissons UHT non ouvertes et les fruits ou légumes qui se conservent normalement hors du réfrigérateur. Ne place jamais les noix ni les produits secs au réfrigérateur.
        Classe chaque produit dans une catégorie : meatAndFish, fruitsAndVegetables, dairy ou snacksAndPantry. snacksAndPantry regroupe aussi l'épicerie sèche, les féculents, conserves et boissons qui ne correspondent pas aux trois autres catégories.
        Choisis pour emoji un seul émoji Unicode qui représente précisément l'article : par exemple 🍌 pour banane, 🥛 pour lait, 🧀 pour fromage, 🐟 pour poisson, 🍗 pour poulet, 🍝 pour pâtes. N'utilise ni texte ni plusieurs émojis.
        confidence doit être compris entre 0 et 1. N'invente aucun produit qui n'apparaît pas sur le ticket.
        """

        var parts: [[String: Any]] = []
        if let pdfData = ticket.pdfData {
            parts.append([
                "inline_data": [
                    "mime_type": "application/pdf",
                    "data": pdfData.base64EncodedString()
                ]
            ])
        } else {
            parts.append(["text": "Texte OCR du ticket :\n\(String(ticket.text.prefix(45_000)))"])
        }
        parts.append(["text": prompt])

        let payloadData = try await GeminiAPI.generateJSON(
            model: model,
            apiKey: trimmedKey,
            parts: parts,
            schema: schema
        )
        let payload = try JSONDecoder().decode(DetectedProductsPayload.self, from: payloadData)
        let drafts = mergeDuplicates(payload.products.compactMap(\.draft))
        guard !drafts.isEmpty else { throw GeminiServiceError.noFoodFound }
        return drafts
    }

    static func classifyExistingStock(_ stock: [StockItem], apiKey: String) async throws -> [StockClassification] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiServiceError.missingKey }
        guard !stock.isEmpty else { return [] }

        let itemSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "storage": ["type": "string", "enum": StorageLocation.allCases.map(\.rawValue)],
                "category": ["type": "string", "enum": FoodCategory.allCases.map(\.rawValue)],
                "consumeWithinHours": ["type": "integer"],
                "emoji": ["type": "string"]
            ],
            "required": ["id", "storage", "category", "consumeWithinHours", "emoji"]
        ]
        let inventory = stock.prefix(120).map { "- id=\($0.id.uuidString); produit=\($0.name)" }.joined(separator: "\n")
        let prompt = """
        Classe chaque aliment fourni, sans changer ni omettre son id.
        storage vaut refrigerator uniquement si le produit nécessite normalement la chaîne du froid. Il vaut roomTemperature pour les noix, biscuits, pâtes, riz, céréales, conserves, épices, huiles, boissons UHT non ouvertes et fruits ou légumes normalement gardés hors du réfrigérateur.
        category vaut meatAndFish, fruitsAndVegetables, dairy ou snacksAndPantry. snacksAndPantry inclut aussi l'épicerie sèche, les féculents, conserves et boissons.
        consumeWithinHours vaut 48 uniquement pour une viande ou un poisson frais, sinon 0.
        emoji vaut un seul émoji Unicode représentant précisément le produit, sans texte.

        Aliments :
        \(inventory)
        """
        let data = try await GeminiAPI.generateJSON(
            model: model,
            apiKey: trimmedKey,
            parts: [["text": prompt]],
            schema: [
                "type": "object",
                "properties": ["items": ["type": "array", "items": itemSchema]],
                "required": ["items"]
            ]
        )
        return try JSONDecoder().decode(StockClassificationsPayload.self, from: data).items
    }

    private static func mergeDuplicates(_ drafts: [ReceiptLineDraft]) -> [ReceiptLineDraft] {
        var merged: [ReceiptLineDraft] = []
        for draft in drafts.prefix(120) {
            let key = TextNormalizer.normalize(draft.name)
            if let index = merged.firstIndex(where: {
                TextNormalizer.normalize($0.name) == key && $0.unit == draft.unit
            }) {
                merged[index].quantity += draft.quantity
                merged[index].confidence = max(merged[index].confidence, draft.confidence)
                if draft.storage == .refrigerator {
                    merged[index].storage = .refrigerator
                }
                merged[index].category = draft.category
                if let currentPrice = merged[index].lineTotalPrice,
                   let addedPrice = draft.lineTotalPrice {
                    merged[index].lineTotalPrice = currentPrice + addedPrice
                } else {
                    merged[index].lineTotalPrice = nil
                }
                if let newExpiration = draft.expirationDate {
                    if let currentExpiration = merged[index].expirationDate {
                        merged[index].expirationDate = min(currentExpiration, newExpiration)
                    } else {
                        merged[index].expirationDate = newExpiration
                    }
                }
            } else {
                merged.append(draft)
            }
        }
        return merged
    }
}

private enum GeminiAPI {
    static func generateJSON(
        model: String,
        apiKey: String,
        parts: [[String: Any]],
        schema: [String: Any]
    ) async throws -> Data {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseJsonSchema": schema
            ]
        ]
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = (try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data).error.message)
            throw GeminiServiceError.api(httpResponse.statusCode, serverMessage)
        }
        let envelope = try JSONDecoder().decode(GeminiResponseEnvelope.self, from: data)
        guard let text = envelope.candidates.first?.content.parts.compactMap(\.text).joined(),
              !text.isEmpty,
              let result = text.data(using: .utf8) else {
            throw GeminiServiceError.invalidResponse
        }
        return result
    }
}

enum GeminiServiceError: LocalizedError {
    case missingKey
    case emptyInventory
    case noFoodFound
    case invalidResponse
    case api(Int, String?)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Ajoutez d’abord votre clé Gemini."
        case .emptyInventory:
            "Ajoutez des aliments au stock avant de générer des recettes."
        case .noFoodFound:
            "Gemini n’a trouvé aucun aliment fiable sur ce ticket."
        case .invalidResponse:
            "Gemini a renvoyé une réponse inutilisable. Réessayez dans un instant."
        case let .api(code, message):
            message.map { "Gemini (erreur \(code)) : \($0)" } ?? "Gemini a répondu avec l’erreur \(code)."
        case .keychain:
            "La clé n’a pas pu être enregistrée dans le Trousseau."
        }
    }
}

private struct GeminiResponseEnvelope: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

private struct GeminiErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private struct GeneratedRecipesPayload: Decodable {
    let recipes: [GeneratedRecipe]
}

private struct GeneratedRecipe: Decodable {
    let name: String
    let subtitle: String
    let durationMinutes: Int
    let servings: Int
    let estimatedCalories: Int
    let starchIngredient: String
    let ingredients: [GeneratedIngredient]
    let steps: [String]

    func isValidMeal(for profile: FoodProfile) -> Bool {
        guard servings == 1,
              (profile.minimumCalories...profile.maximumCalories).contains(estimatedCalories),
              (4...7).contains(ingredients.count),
              (4...7).contains(steps.count),
              durationMinutes <= profile.maximumPrepMinutes else { return false }
        guard profile.requiresStarch else { return true }
        guard !starchIngredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return ingredients.contains {
            TextNormalizer.matches($0.name, aliases: [starchIngredient])
        }
    }

    func recipe(index: Int) -> Recipe {
        let slug = TextNormalizer.normalize(name)
            .replacingOccurrences(of: " ", with: "-")
        return Recipe(
            id: "gemini-\(slug.isEmpty ? String(index) : slug)",
            name: name,
            subtitle: subtitle,
            symbol: "sparkles",
            tintName: "purple",
            durationMinutes: max(1, durationMinutes),
            baseServings: 1,
            estimatedCalories: estimatedCalories,
            starchIngredient: starchIngredient,
            ingredients: ingredients.prefix(7).map {
                RecipeIngredient(
                    $0.name,
                    quantity: max(0, $0.quantity),
                    unit: InventoryUnit(rawValue: $0.unit) ?? .piece
                )
            },
            steps: Array(steps.prefix(7))
        )
    }
}

private struct GeneratedIngredient: Decodable {
    let name: String
    let quantity: Double
    let unit: String
}

private struct DetectedProductsPayload: Decodable {
    let products: [DetectedProduct]
}

struct StockClassification: Decodable {
    let id: String
    let storageRawValue: String
    let categoryRawValue: String
    let consumeWithinHours: Int
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case id, consumeWithinHours, emoji
        case storageRawValue = "storage"
        case categoryRawValue = "category"
    }

    var storage: StorageLocation {
        StorageLocation(rawValue: storageRawValue) ?? .roomTemperature
    }

    var category: FoodCategory {
        FoodCategory(rawValue: categoryRawValue) ?? .snacksAndPantry
    }
}

private struct StockClassificationsPayload: Decodable {
    let items: [StockClassification]
}

private struct DetectedProduct: Decodable {
    let name: String
    let quantity: Double
    let unit: String
    let confidence: Double
    let consumeWithinHours: Int
    let storage: String
    let category: String
    let emoji: String
    let lineTotalPrice: Double

    var draft: ReceiptLineDraft? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanName.filter(\.isLetter).count >= 2,
              quantity > 0,
              let parsedUnit = InventoryUnit(rawValue: unit) else { return nil }
        return ReceiptLineDraft(
            name: cleanName,
            quantity: quantity,
            unit: parsedUnit,
            confidence: min(1, max(0, confidence)),
            expirationDate: consumeWithinHours > 0
                ? Calendar.current.date(byAdding: .hour, value: min(48, consumeWithinHours), to: .now)
                : nil,
            storage: StorageLocation(rawValue: storage) ?? .roomTemperature,
            category: FoodCategory(rawValue: category) ?? .snacksAndPantry,
            emoji: emoji.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "🛒",
            lineTotalPrice: lineTotalPrice > 0 ? lineTotalPrice : nil
        )
    }
}
