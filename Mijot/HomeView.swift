import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showProfileEditor = false

    private var profile: FoodProfile { store.foodProfile }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        welcomeCard
                        if profile.hasCompletedOnboarding {
                            profileSummary
                            overviewCard
                        } else {
                            introductionCard
                        }
                        privacyCard
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Mijot")
            .toolbar {
                if profile.hasCompletedOnboarding {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Modifier", systemImage: "person.crop.circle") {
                            showProfileEditor = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfileEditor) {
                FoodProfileEditorView(profile: profile)
                    .environmentObject(store)
            }
        }
    }

    private var welcomeCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 16) {
                MijotLogoView(size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.hasCompletedOnboarding
                         ? "Bienvenue sur Mijot, \(profile.firstName)"
                         : "Bienvenue sur Mijot")
                        .font(.title2.weight(.bold))
                    Text(profile.hasCompletedOnboarding
                         ? "Vos prochaines recettes tiendront compte de votre profil."
                         : "Présentez-vous pour obtenir des repas vraiment adaptés à vos goûts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    private var introductionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Personnaliser Gemini", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                Text("Indiquez votre régime, vos allergies, ce que vous aimez et ce que vous ne voulez jamais retrouver dans une recette.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Créer mon profil alimentaire") {
                    showProfileEditor = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Votre profil", subtitle: "Utilisé comme consigne initiale pour Gemini")
            GlassCard {
                VStack(spacing: 0) {
                    summaryRow(symbol: "fork.knife", title: "Régime", value: profile.dietaryStyle.label)
                    Divider().padding(.leading, 42)
                    summaryRow(
                        symbol: "target",
                        title: "Objectifs",
                        value: profile.goals.isEmpty ? "Aucun" : profile.goals.map(\.label).sorted().joined(separator: " · ")
                    )
                    Divider().padding(.leading, 42)
                    summaryRow(
                        symbol: "flame.fill",
                        title: "Énergie",
                        value: "\(profile.minimumCalories)–\(profile.maximumCalories) kcal"
                    )
                    Divider().padding(.leading, 42)
                    summaryRow(
                        symbol: "leaf.fill",
                        title: "Féculents",
                        value: (profile.requiresStarch ? "Obligatoires · " : "Facultatifs · ")
                            + (profile.allowedStarches.isEmpty
                               ? "aucune préférence"
                               : profile.allowedStarches.map(\.label).sorted().joined(separator: " · "))
                    )
                    Divider().padding(.leading, 42)
                    summaryRow(
                        symbol: "square.stack.3d.up.fill",
                        title: "Prochaine génération",
                        value: "\(store.desiredRecipeCount) recette\(store.desiredRecipeCount > 1 ? "s" : "")"
                    )
                    if !profile.allergies.isEmpty {
                        Divider().padding(.leading, 42)
                        summaryRow(symbol: "exclamationmark.shield.fill", title: "À exclure", value: profile.allergies)
                    }
                    if !profile.dislikedFoods.isEmpty {
                        Divider().padding(.leading, 42)
                        summaryRow(symbol: "hand.thumbsdown.fill", title: "Refusés", value: profile.dislikedFoods)
                    }
                    if !profile.favoriteFoods.isEmpty {
                        Divider().padding(.leading, 42)
                        summaryRow(symbol: "heart.fill", title: "Préférés", value: profile.favoriteFoods)
                    }
                }
            }
        }
    }

    private func summaryRow(symbol: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var overviewCard: some View {
        GlassCard {
            HStack(spacing: 0) {
                metric(value: "\(store.stockItems.count)", label: "aliments")
                Divider().frame(height: 42)
                metric(value: "\(store.generatedRecipes.count)", label: "recettes")
                Divider().frame(height: 42)
                metric(value: "\(store.plannedMeals.filter { !$0.isConsumed }.count)", label: "repas prévus")
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var privacyCard: some View {
        GlassCard {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profil privé sur cet appareil")
                        .font(.subheadline.weight(.semibold))
                    Text("Ces indications sont enregistrées localement et envoyées à Gemini uniquement lors de la génération des recettes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
        }
    }
}

private struct FoodProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var draft: FoodProfile

    init(profile: FoodProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vous") {
                    TextField("Prénom ou pseudonyme", text: $draft.firstName)
                        .textInputAutocapitalization(.words)
                    Picker("Régime alimentaire", selection: $draft.dietaryStyle) {
                        ForEach(DietaryStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                }

                Section {
                    ForEach(FoodGoal.allCases) { goal in
                        Toggle(goal.label, isOn: Binding(
                            get: { draft.goals.contains(goal) },
                            set: { enabled in
                                if enabled { draft.goals.insert(goal) }
                                else { draft.goals.remove(goal) }
                            }
                        ))
                    }
                } header: {
                    Text("Priorités")
                } footer: {
                    Text("Ces choix servent à classer les propositions de Gemini.")
                }

                Section {
                    Stepper(
                        "Minimum : \(draft.minimumCalories) kcal",
                        value: $draft.minimumCalories,
                        in: 300...max(300, draft.maximumCalories - 50),
                        step: 50
                    )
                    Stepper(
                        "Maximum : \(draft.maximumCalories) kcal",
                        value: $draft.maximumCalories,
                        in: min(1_200, draft.minimumCalories + 50)...1_200,
                        step: 50
                    )
                } header: {
                    Text("Calories par repas")
                } footer: {
                    Text("Gemini doit rester dans cette plage pour chaque recette.")
                }

                Section {
                    Toggle("Féculent obligatoire", isOn: $draft.requiresStarch)
                    ForEach(StarchPreference.allCases) { starch in
                        Toggle(isOn: Binding(
                            get: { draft.allowedStarches.contains(starch) },
                            set: { enabled in
                                if enabled { draft.allowedStarches.insert(starch) }
                                else { draft.allowedStarches.remove(starch) }
                            }
                        )) {
                            Text("\(starch.emoji)  \(starch.label)")
                        }
                    }
                } header: {
                    Text("Féculents autorisés")
                } footer: {
                    Text("Si l’option est obligatoire, gardez au moins un choix actif.")
                }

                Section("Style de cuisine") {
                    Stepper(
                        "\(draft.maximumPrepMinutes) minutes maximum",
                        value: $draft.maximumPrepMinutes,
                        in: 10...120,
                        step: 5
                    )
                    Picker("Niveau d’épices", selection: $draft.spiceLevel) {
                        ForEach(SpiceLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }

                Section {
                    TextField("Ex. arachides, lactose, gluten", text: $draft.allergies, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Allergies et intolérances")
                } footer: {
                    Text("Gemini reçoit la consigne de les exclure strictement. Vérifiez malgré tout chaque recette en cas d’allergie sévère.")
                }

                Section("Vos goûts") {
                    TextField("Aliments que vous refusez", text: $draft.dislikedFoods, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Aliments que vous aimez", text: $draft.favoriteFoods, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Cuisines appréciées", text: $draft.favoriteCuisines, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    TextEditor(text: $draft.additionalInstructions)
                        .frame(minHeight: 100)
                } header: {
                    Text("Consigne personnelle pour Gemini")
                } footer: {
                    Text("Ex. plats épicés, sauces légères, moins de vaisselle, textures croustillantes…")
                }
            }
            .navigationTitle("Profil alimentaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(
                            draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (draft.requiresStarch && draft.allowedStarches.isEmpty)
                        )
                }
            }
        }
    }

    private func save() {
        draft.firstName = draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.hasCompletedOnboarding = true
        store.saveFoodProfile(draft)
        Haptics.success()
        dismiss()
    }
}
