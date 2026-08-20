import SwiftUI

struct RecipesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showGeminiSetup = false
    @State private var showRecipeSettings = false
    @State private var isGenerating = false
    @State private var notice: GeminiNotice?

    private var stock: [StockItem] { store.stockItems.sorted { $0.updatedAt > $1.updatedAt } }
    private var recipesAreCurrent: Bool {
        store.generatedRecipeInventorySignature == store.inventorySignature
    }
    private var matches: [RecipeMatch] {
        LocalRecipeEngine.matches(for: stock, recipes: recipesAreCurrent ? store.generatedRecipes : [])
    }
    private var pricedMatches: [RecipeMatch] { matches.filter { $0.estimatedCost != nil } }
    private var totalMealCost: Double { pricedMatches.compactMap(\.estimatedCost).reduce(0, +) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if stock.isEmpty {
                    EmptyStateView(
                        symbol: "fork.knife",
                        title: "À table, bientôt",
                        message: "Ajoutez quelques aliments au stock pour que Gemini prépare vos recettes."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if isGenerating {
                                generationProgress
                            }
                            suggestionHeader
                            if !pricedMatches.isEmpty {
                                budgetSummary
                            }
                            if matches.isEmpty && !isGenerating {
                                generationCallToAction
                            }
                            ForEach(matches) { match in
                                NavigationLink(value: match.recipe) {
                                    RecipeCard(match: match)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Pour vous")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showRecipeSettings = true
                    } label: {
                        Label("Réglages de cuisine", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        showGeminiSetup = true
                    } label: {
                        Label("Recettes Gemini", systemImage: "sparkles")
                    }
                    .disabled(isGenerating)
                }
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .sheet(isPresented: $showGeminiSetup) {
                GeminiKeySheet(
                    title: "Recettes avec Gemini",
                    intro: "Gemini imagine \(store.desiredRecipeCount) recettes à partir de vos aliments et de vos choix.",
                    privacyMessage: "Le stock, les réglages de cuisine et votre profil alimentaire sont envoyés pour personnaliser les recettes.",
                    actionTitle: "Enregistrer et générer",
                    canContinue: !stock.isEmpty
                ) { key in
                    Task { await generateWithGemini(apiKey: key) }
                }
            }
            .sheet(isPresented: $showRecipeSettings) {
                RecipeSettingsView()
                    .environmentObject(store)
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .task(id: store.inventorySignature) {
                await generateAutomaticallyIfNeeded()
            }
        }
    }

    private var generationProgress: some View {
        GlassCard {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gemini compose vos recettes")
                        .font(.headline)
                    Text("Seule la liste des ingrédients est envoyée.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var suggestionHeader: some View {
        GlassCard {
            HStack(spacing: 14) {
                MijotLogoView(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.foodProfile.hasCompletedOnboarding
                         ? "Pour \(store.foodProfile.firstName)"
                         : "Selon vos aliments")
                        .font(.title3.weight(.semibold))
                    Text(store.generatedRecipes.isEmpty
                         ? "Gemini prépare \(store.desiredRecipeCount) recettes selon tous vos réglages."
                         : "Recettes créées par Gemini selon votre stock, vos goûts et vos contraintes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var generationCallToAction: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Recettes Gemini à préparer", systemImage: "sparkles")
                    .font(.headline)
                Text("Les recettes affichées ici sont entièrement générées par Gemini, avec leurs ingrédients, quantités et étapes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Configurer Gemini") {
                    showGeminiSetup = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var budgetSummary: some View {
        GlassCard {
            HStack(spacing: 14) {
                SymbolBadge(symbol: "eurosign.circle.fill", size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Budget des repas")
                        .font(.headline)
                    Text(
                        pricedMatches.allSatisfy(\.costEstimate.isComplete)
                            ? "\(pricedMatches.count) repas · moyenne calculée avec les prix du ticket"
                            : "Minimum connu · certains ingrédients n’ont pas encore de prix"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(totalMealCost, format: .currency(code: "EUR").precision(.fractionLength(2)))
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text(totalMealCost / Double(pricedMatches.count), format: .currency(code: "EUR").precision(.fractionLength(2)))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("par repas")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func generateAutomaticallyIfNeeded() async {
        guard !stock.isEmpty,
              store.generatedRecipeInventorySignature != store.inventorySignature,
              !isGenerating,
              let apiKey = GeminiKeychain.load() else { return }
        await generateWithGemini(apiKey: apiKey, showsSuccessNotice: false)
    }

    @MainActor
    private func generateWithGemini(apiKey: String, showsSuccessNotice: Bool = true) async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let recipes = try await GeminiRecipeService.generateRecipes(
                from: stock,
                appliances: store.kitchenAppliances,
                profile: store.foodProfile,
                recipeCount: store.desiredRecipeCount,
                apiKey: apiKey
            )
            store.saveGeneratedRecipes(recipes)
            Haptics.success()
            if showsSuccessNotice {
                notice = GeminiNotice(
                    title: "Recettes prêtes",
                    message: "\(recipes.count) nouvelles idées Gemini remplacent les précédentes pour correspondre au stock actuel."
                )
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            notice = GeminiNotice(
                title: "Génération impossible",
                message: error.localizedDescription
            )
        }
    }
}

private struct RecipeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Toutes les recettes Gemini sont calculées pour une personne.", systemImage: "person.fill")
                    Label(
                        "Chaque repas apporte entre \(store.foodProfile.minimumCalories) et \(store.foodProfile.maximumCalories) kcal.",
                        systemImage: "flame.fill"
                    )
                    Label(
                        store.foodProfile.requiresStarch ? "Féculent obligatoire selon votre sélection." : "Féculent facultatif.",
                        systemImage: "leaf.fill"
                    )
                    Label("Elles utilisent de quatre à sept ingrédients principaux.", systemImage: "list.number")
                } header: {
                    Text("Format des recettes")
                }

                Section {
                    ForEach(KitchenAppliance.allCases) { appliance in
                        Toggle(isOn: Binding(
                            get: { store.kitchenAppliances.contains(appliance) },
                            set: { store.setAppliance(appliance, enabled: $0) }
                        )) {
                            Label(appliance.rawValue, systemImage: appliance.symbol)
                        }
                    }
                } header: {
                    Text("Appareils disponibles")
                } footer: {
                    Text("Gemini ne proposera que des préparations compatibles avec les appareils activés. Sans appareil, il proposera des recettes froides.")
                }

                Section("Produits frais") {
                    Label("Viande et poisson frais : priorité sous 48 h", systemImage: "clock.badge.exclamationmark")
                    Text("Lorsqu’un paquet correspond à deux portions, Gemini prépare deux idées différentes pour utiliser une moitié à chaque repas.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cuisine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct GeminiNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RecipeCard: View {
    let match: RecipeMatch

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                SymbolBadge(
                    symbol: match.recipe.symbol,
                    color: FrigoTheme.color(named: match.recipe.tintName),
                    size: 50
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(match.recipe.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(match.recipe.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if match.recipe.id.hasPrefix("gemini-") {
                        Label("Créée avec Gemini", systemImage: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: 10) {
                        Label("\(match.recipe.durationMinutes) min", systemImage: "clock")
                        if let calories = match.recipe.estimatedCalories {
                            Label("\(calories) kcal", systemImage: "flame.fill")
                        }
                        if let cost = match.estimatedCost {
                            Label(
                                cost.formatted(.currency(code: "EUR").precision(.fractionLength(2))),
                                systemImage: "eurosign.circle"
                            )
                        }
                        if match.canCook {
                            Label("Tout est là", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(FrigoTheme.accent)
                        } else {
                            Text("\(match.missingIngredients.count) manquant\(match.missingIngredients.count > 1 ? "s" : "")")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.weight(.medium))
                }

                Spacer(minLength: 4)

                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: match.coverage)
                        .stroke(match.canCook ? FrigoTheme.accent : .orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(match.coverage, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
                .frame(width: 48, height: 48)
            }
        }
    }
}

struct GeminiKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let intro: String
    let privacyMessage: String
    let actionTitle: String
    let canContinue: Bool
    let onSave: (String) -> Void

    @State private var apiKey: String
    @State private var keyError: String?

    init(
        title: String,
        intro: String,
        privacyMessage: String,
        actionTitle: String,
        canContinue: Bool,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.intro = intro
        self.privacyMessage = privacyMessage
        self.actionTitle = actionTitle
        self.canContinue = canContinue
        self.onSave = onSave
        _apiKey = State(initialValue: GeminiKeychain.load() ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clé Gemini personnelle")
                                .font(.headline)
                            Text(intro)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Clé API personnelle") {
                    SecureField("Coller la clé Gemini", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        Label("Créer une clé dans Google AI Studio", systemImage: "arrow.up.right.square")
                    }
                    if let keyError {
                        Text(keyError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Confidentialité") {
                    Label("La clé est conservée dans le Trousseau de cet appareil.", systemImage: "key.fill")
                    Label(privacyMessage, systemImage: "lock.shield.fill")
                    Text("Le quota gratuit et l’utilisation des données dépendent des conditions de Google. Pour une application publiée, utilisez un serveur intermédiaire et ne distribuez jamais une clé dans l’app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        saveAndGenerate()
                    } label: {
                        Label(actionTitle, systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canContinue)

                    if GeminiKeychain.load() != nil {
                        Button("Oublier la clé", role: .destructive) {
                            GeminiKeychain.delete()
                            apiKey = ""
                        }
                    }
                } footer: {
                    if !canContinue {
                        Text("Importez d’abord un ticket ou ajoutez un aliment au stock.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveAndGenerate() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try GeminiKeychain.save(trimmedKey)
            dismiss()
            onSave(trimmedKey)
        } catch {
            keyError = error.localizedDescription
        }
    }
}

private struct RecipeDetailView: View {
    @EnvironmentObject private var store: AppStore
    let recipe: Recipe

    @State private var showScheduleSheet = false
    private var stock: [StockItem] { store.stockItems }
    private var costEstimate: RecipeCostEstimate {
        LocalRecipeEngine.costEstimate(for: recipe, stock: stock)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    ingredients
                    steps
                    Button {
                        showScheduleSheet = true
                    } label: {
                        Label("Ajouter à ma semaine", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleRecipeView(recipe: recipe)
                .environmentObject(store)
        }
    }

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    SymbolBadge(symbol: recipe.symbol, color: FrigoTheme.color(named: recipe.tintName), size: 62)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.name).font(.title2.weight(.bold))
                        Text(recipe.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 18) {
                    Label("\(recipe.durationMinutes) min", systemImage: "clock")
                    Label("\(recipe.baseServings) personne\(recipe.baseServings > 1 ? "s" : "")", systemImage: "person.2")
                    if let calories = recipe.estimatedCalories {
                        Label("\(calories) kcal", systemImage: "flame.fill")
                    }
                    if let cost = costEstimate.estimatedTotal {
                        Label(
                            cost.formatted(.currency(code: "EUR").precision(.fractionLength(2))),
                            systemImage: "eurosign.circle"
                        )
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                if costEstimate.estimatedTotal != nil && !costEstimate.isComplete {
                    Label("Prix minimum connu : certains ingrédients ne sont pas chiffrés", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let starch = recipe.starchIngredient, !starch.isEmpty {
                    Label("Féculent : \(starch)", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Ingrédients")
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        let available = stock.contains { TextNormalizer.matches($0.name, aliases: ingredient.aliases) }
                        HStack {
                            Image(systemName: available ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(available ? FrigoTheme.accent : .orange)
                            Text(ingredient.name)
                            Spacer()
                            Text("\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit.shortLabel)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 11)
                        if index < recipe.ingredients.count - 1 { Divider().padding(.leading, 30) }
                    }
                }
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Préparation")
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                GlassCard {
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(FrigoTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(FrigoTheme.accent.opacity(0.12), in: Circle())
                        Text(step)
                            .font(.body)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}

struct ScheduleRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var calendarService: MealCalendarService
    let recipe: Recipe
    var initialDate: Date = .now

    @State private var selectedMoments: Set<MealMoment>
    @State private var servings: Int
    @State private var isSaving = false
    @State private var calendarError: String?

    init(recipe: Recipe, initialDate: Date = .now) {
        self.recipe = recipe
        self.initialDate = initialDate
        let day = Calendar.current.startOfDay(for: initialDate)
        _selectedMoments = State(initialValue: [MealMoment(day: day, slot: .dinner)])
        _servings = State(initialValue: recipe.baseServings)
    }

    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: initialDate)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        SymbolBadge(symbol: recipe.symbol, color: FrigoTheme.color(named: recipe.tintName))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.name).font(.headline)
                            Text("\(recipe.durationMinutes) minutes").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                .font(.headline)
                            HStack(spacing: 10) {
                                ForEach(MealSlot.allCases) { slot in
                                    momentButton(day: day, slot: slot)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                } header: {
                    Text("Jours et repas")
                } footer: {
                    Text("Vous pouvez sélectionner plusieurs midis et soirs pour ajouter cette recette à la semaine.")
                }
                Section("Portions") {
                    Stepper("\(servings) personne\(servings > 1 ? "s" : "")", value: $servings, in: 1...12)
                }
                Section("Horaires") {
                    LabeledContent("Déjeuner", value: store.calendarPreferences.timeLabel(for: .lunch))
                    LabeledContent("Dîner", value: store.calendarPreferences.timeLabel(for: .dinner))
                    if store.calendarPreferences.isEnabled {
                        Label("Chaque créneau sera aussi ajouté au calendrier.", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle("Planifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Ajout…" : "Ajouter \(selectedMoments.count) créneau\(selectedMoments.count > 1 ? "x" : "")") {
                        Task { await saveMoments() }
                    }
                    .disabled(selectedMoments.isEmpty || isSaving)
                }
            }
            .alert("Calendrier indisponible", isPresented: Binding(
                get: { calendarError != nil },
                set: { if !$0 { calendarError = nil } }
            )) {
                Button("OK", role: .cancel) { calendarError = nil }
            } message: {
                Text(calendarError ?? "Une erreur est survenue.")
            }
        }
        .presentationDetents([.large])
    }

    private func momentButton(day: Date, slot: MealSlot) -> some View {
        let moment = MealMoment(day: Calendar.current.startOfDay(for: day), slot: slot)
        let isSelected = selectedMoments.contains(moment)
        return Button {
            if isSelected { selectedMoments.remove(moment) }
            else { selectedMoments.insert(moment) }
            Haptics.selection()
        } label: {
            Label(slot.rawValue, systemImage: slot.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected ? Color.black : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func saveMoments() async {
        isSaving = true
        defer { isSaving = false }

        let preferences = store.calendarPreferences
        let moments = selectedMoments.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.slot.rawValue < $1.slot.rawValue
        }
        var calendarEvents: [MealMoment: String] = [:]

        do {
            if preferences.isEnabled {
                for moment in moments {
                    calendarEvents[moment] = try await calendarService.createEvent(
                        for: recipe,
                        on: moment.day,
                        slot: moment.slot,
                        servings: servings,
                        preferences: preferences
                    )
                }
            }

            for moment in moments {
                store.addMeal(PlannedMeal(
                    recipeID: recipe.id,
                    recipeName: recipe.name,
                    scheduledDate: preferences.date(on: moment.day, for: moment.slot),
                    slot: moment.slot,
                    servings: servings,
                    calendarEventIdentifier: calendarEvents[moment]
                ))
            }
            Haptics.success()
            dismiss()
        } catch {
            calendarEvents.values.forEach { calendarService.removeEvent(identifier: $0) }
            calendarError = error.localizedDescription
        }
    }
}

private struct MealMoment: Hashable {
    let day: Date
    let slot: MealSlot
}
