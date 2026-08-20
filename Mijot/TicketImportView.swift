import SwiftUI
import UniformTypeIdentifiers

struct TicketImportView: View {
    @EnvironmentObject private var store: AppStore

    @State private var isImporterPresented = false
    @State private var showGeminiSetup = false
    @State private var geminiConfigured = GeminiKeychain.load() != nil
    @State private var isAnalyzing = false
    @State private var drafts: [ReceiptLineDraft] = []
    @State private var sourceName = ""
    @State private var errorMessage: String?
    @State private var showSavedConfirmation = false
    @State private var showMealCount = false
    @State private var requestedMealCount = 5

    private var includedCount: Int { drafts.filter(\.isIncluded).count }
    private var pricedIncludedCount: Int {
        drafts.filter { $0.isIncluded && $0.lineTotalPrice != nil }.count
    }
    private var includedPriceTotal: Double {
        drafts.filter(\.isIncluded).compactMap(\.lineTotalPrice).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        hero

                        if isAnalyzing {
                            analyzingCard
                        } else if drafts.isEmpty {
                            howItWorks
                        } else {
                            reviewSection
                        }
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Tickets")
            .toolbar {
                if !drafts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Annuler") {
                            withAnimation { drafts.removeAll() }
                        }
                    }
                }
            }
            .sheet(isPresented: $showGeminiSetup, onDismiss: {
                geminiConfigured = GeminiKeychain.load() != nil
            }) {
                GeminiKeySheet(
                    title: "Analyse des tickets",
                    intro: "Gemini lit directement la mise en page du PDF pour distinguer les aliments des prix et des informations du magasin.",
                    privacyMessage: "Le PDF sélectionné est envoyé à Gemini pour cette analyse.",
                    actionTitle: "Enregistrer et choisir un PDF",
                    canContinue: true
                ) { _ in
                    geminiConfigured = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        isImporterPresented = true
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .alert("Import impossible", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Une erreur inconnue est survenue.")
            }
            .alert("Stock mis à jour", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Les produits ont été rangés. Gemini préparera \(store.desiredRecipeCount) recettes personnalisées.")
            }
            .sheet(isPresented: $showMealCount) {
                MealCountSheet(count: $requestedMealCount) {
                    saveDrafts(recipeCount: requestedMealCount)
                }
            }
        }
    }

    private var hero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    SymbolBadge(symbol: "doc.text.viewfinder", size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Du ticket à votre stock")
                            .font(.title2.weight(.bold))
                        Text("Gemini repère les aliments, nettoie leurs noms et retrouve leurs quantités.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if geminiConfigured {
                        isImporterPresented = true
                    } else {
                        showGeminiSetup = true
                    }
                } label: {
                    Label(drafts.isEmpty ? "Analyser un ticket PDF" : "Choisir un autre PDF", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAnalyzing)

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: geminiConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(geminiConfigured ? Color.primary : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(geminiConfigured ? "Gemini est prêt" : "Clé Gemini nécessaire")
                            .font(.subheadline.weight(.semibold))
                        Text(geminiConfigured ? "Analyse visuelle du PDF avec Gemini 3.5 Flash" : "Ajoutez votre clé personnelle gratuite pour commencer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(geminiConfigured ? "Modifier" : "Configurer") {
                        showGeminiSetup = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var analyzingCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.black)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini analyse le ticket")
                        .font(.headline)
                    Text("Lecture de la mise en page et extraction des aliments…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .transition(.opacity)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Comment ça marche")
            GlassCard {
                VStack(spacing: 0) {
                    stepRow(number: "1", title: "Choisir", message: "Sélectionnez un ticket PDF depuis Fichiers.")
                    Divider().padding(.leading, 48)
                    stepRow(number: "2", title: "Analyser", message: "Gemini conserve uniquement les aliments achetés.")
                    Divider().padding(.leading, 48)
                    stepRow(number: "3", title: "Confirmer", message: "Vérifiez la catégorie et le rangement proposés par Gemini.")
                    Divider().padding(.leading, 48)
                    stepRow(number: "4", title: "Planifier", message: "Choisissez combien de vrais repas Gemini doit préparer.")
                }
            }
        }
    }

    private func stepRow(number: String, title: String, message: String) -> some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.black, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 13)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                SectionTitle(title: "Aliments détectés", subtitle: sourceName)
                Text("\(includedCount) sur \(drafts.count)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(drafts.indices), id: \.self) { index in
                    productEditor(draft: $drafts[index])
                    if index < drafts.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: FrigoTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FrigoTheme.cardRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
            }

            if pricedIncludedCount > 0 {
                GlassCard {
                    HStack(spacing: 14) {
                        SymbolBadge(symbol: "eurosign.circle.fill", size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Total des aliments retenus")
                                .font(.subheadline.weight(.semibold))
                            Text("Prix retrouvé pour \(pricedIncludedCount) article\(pricedIncludedCount > 1 ? "s" : "") sur \(includedCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(includedPriceTotal, format: .currency(code: "EUR").precision(.fractionLength(2)))
                            .font(.title3.weight(.bold).monospacedDigit())
                    }
                }
            }

            Button {
                requestedMealCount = store.desiredRecipeCount
                showMealCount = true
            } label: {
                Label("Ajouter au stock", systemImage: "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(includedCount == 0)
            .padding(.top, 4)
        }
    }

    private func productEditor(draft: Binding<ReceiptLineDraft>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                withAnimation(.snappy) { draft.wrappedValue.isIncluded.toggle() }
                Haptics.selection()
            } label: {
                Image(systemName: draft.wrappedValue.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(draft.wrappedValue.isIncluded ? Color.black : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("🍽️", text: draft.emoji)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .frame(width: 46, height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    TextField("Nom de l’aliment", text: draft.name)
                        .font(.body.weight(.semibold))
                        .textInputAutocapitalization(.sentences)
                }

                HStack(spacing: 10) {
                    TextField(
                        "Prix payé",
                        value: draft.lineTotalPrice,
                        format: .number.precision(.fractionLength(2))
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    Text("€ pour cet article")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField("Quantité", value: draft.quantity, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                    Picker("Unité", selection: draft.unit) {
                        ForEach(InventoryUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    if draft.wrappedValue.confidence < 0.75 {
                        Label("À vérifier", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 10) {
                    Picker("Catégorie", selection: draft.category) {
                        ForEach(FoodCategory.allCases) { category in
                            Label(category.label, systemImage: category.symbol).tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Picker("Rangement", selection: draft.storage) {
                        ForEach(StorageLocation.allCases) { storage in
                            Label(storage.label, systemImage: storage.symbol).tag(storage)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let expiration = draft.wrappedValue.expirationDate {
                    Label(
                        "Produit frais · à consommer avant \(expiration.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                }
            }
            .opacity(draft.wrappedValue.isIncluded ? 1 : 0.38)
        }
        .padding(16)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard let apiKey = GeminiKeychain.load() else {
                showGeminiSetup = true
                return
            }
            sourceName = url.lastPathComponent
            withAnimation {
                isAnalyzing = true
                drafts = []
            }
            Task {
                do {
                    let ticket = try await PDFTicketExtractor.extract(from: url)
                    let detected = try await GeminiReceiptService.detectFood(in: ticket, apiKey: apiKey)
                    await MainActor.run {
                        withAnimation(.smooth) {
                            drafts = detected
                            isAnalyzing = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        isAnalyzing = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func saveDrafts(recipeCount: Int) {
        store.setDesiredRecipeCount(recipeCount)
        store.importLines(drafts)
        drafts.removeAll()
        sourceName = ""
        Haptics.success()
        showSavedConfirmation = true
    }
}

private struct MealCountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var count: Int
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                SymbolBadge(symbol: "fork.knife.circle.fill", size: 64)
                VStack(spacing: 6) {
                    Text("Combien de plats préparer ?")
                        .font(.title2.weight(.bold))
                    Text("Gemini créera exactement ce nombre de recettes à partir de ce ticket et de votre profil.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack {
                    Button { count = max(1, count - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .disabled(count <= 1)
                    Text("\(count)")
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(minWidth: 90)
                    Button { count = min(14, count + 1) } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(count >= 14)
                }
                .font(.title)
                .foregroundStyle(.primary)

                Text("Entre 1 et 14 repas")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Ajouter et générer \(count) recettes") {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .navigationTitle("Recettes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
