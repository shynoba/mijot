import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var itemToEdit: StockItem?
    @State private var showNewItem = false
    @State private var showHistory = false
    @State private var showClearConfirmation = false
    @State private var isClassifying = false
    @State private var classificationError: String?

    private var items: [StockItem] {
        store.stockItems.sorted {
            let firstDate = $0.expirationDate ?? .distantFuture
            let secondDate = $1.expirationDate ?? .distantFuture
            if firstDate != secondDate { return firstDate < secondDate }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    private var movements: [StockMovement] { store.movements.sorted { $0.createdAt > $1.createdAt } }
    private var lowStockCount: Int { items.filter(\.isNearlyEmpty).count }
    private var urgentCount: Int {
        let limit = Calendar.current.date(byAdding: .hour, value: 48, to: .now) ?? .now
        return items.filter { item in
            guard let expiration = item.expirationDate else { return false }
            return expiration <= limit
        }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if items.isEmpty {
                    EmptyStateView(
                        symbol: "refrigerator",
                        title: "Votre frigo est vide",
                        message: "Importez un ticket PDF ou ajoutez votre premier produit manuellement."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            summaryCard
                            if isClassifying {
                                GlassCard {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                        Text("Gemini reclasse votre ancien stock…")
                                            .font(.subheadline.weight(.medium))
                                    }
                                }
                            }
                            ForEach(StorageLocation.allCases) { storage in
                                storageSection(storage)
                            }
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Mes aliments")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Historique")
                    Button { showNewItem = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Ajouter un produit")
                    Menu {
                        Button("Vider le stock", systemImage: "trash", role: .destructive) {
                            showClearConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showNewItem) {
                InventoryEditorView(item: nil)
                    .environmentObject(store)
            }
            .sheet(item: $itemToEdit) { item in
                InventoryEditorView(item: item)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showHistory) {
                MovementHistoryView(movements: movements)
            }
            .confirmationDialog(
                "Vider complètement le stock ?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Vider le stock", role: .destructive) {
                    withAnimation { store.clearInventory() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous les produits et leur historique seront supprimés.")
            }
            .alert("Classement incomplet", isPresented: Binding(
                get: { classificationError != nil },
                set: { if !$0 { classificationError = nil } }
            )) {
                Button("OK", role: .cancel) { classificationError = nil }
            } message: {
                Text(classificationError ?? "Gemini n’a pas pu classer l’ancien stock.")
            }
            .task(id: store.needsGeminiStockClassification) {
                await classifyExistingStockIfNeeded()
            }
        }
    }

    @MainActor
    private func classifyExistingStockIfNeeded() async {
        guard store.needsGeminiStockClassification,
              !isClassifying,
              let apiKey = GeminiKeychain.load() else { return }
        isClassifying = true
        defer { isClassifying = false }
        do {
            let classifications = try await GeminiReceiptService.classifyExistingStock(
                store.stockItems,
                apiKey: apiKey
            )
            store.applyGeminiClassifications(classifications)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            classificationError = error.localizedDescription
        }
    }

    private var summaryCard: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(items.count) produit\(items.count > 1 ? "s" : "")")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text(summaryMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SymbolBadge(
                    symbol: urgentCount > 0 ? "clock.badge.exclamationmark" : (lowStockCount == 0 ? "checkmark" : "basket.fill"),
                    color: urgentCount > 0 || lowStockCount > 0 ? .orange : FrigoTheme.accent
                )
            }
        }
        .padding(.top, 2)
    }

    private var summaryMessage: String {
        if urgentCount > 0 {
            return "\(urgentCount) produit\(urgentCount > 1 ? "s" : "") à consommer sous 48 h"
        }
        return lowStockCount == 0 ? "Tout semble bien rempli" : "\(lowStockCount) bientôt à renouveler"
    }

    @ViewBuilder
    private func storageSection(_ storage: StorageLocation) -> some View {
        let storedItems = items.filter { $0.storage == storage }
        if !storedItems.isEmpty {
            SectionTitle(
                title: storage.label,
                subtitle: storage == .refrigerator
                    ? "Produits qui nécessitent le froid"
                    : "Placard, corbeille ou plan de travail"
            )
            .padding(.top, 6)

            ForEach(FoodCategory.allCases) { category in
                let categoryItems = storedItems.filter { $0.category == category }
                if !categoryItems.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: category.symbol)
                        Text(category.label)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    ForEach(categoryItems) { item in
                        inventoryRow(item)
                    }
                }
            }
        }
    }

    private func inventoryRow(_ item: StockItem) -> some View {
        Button {
            itemToEdit = item
        } label: {
            GlassCard {
                HStack(spacing: 14) {
                    EmojiBadge(emoji: item.displayEmoji, size: 46)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(item.expirationDate.map { "À consommer avant le \($0.formatted(date: .abbreviated, time: .shortened))" } ?? item.storage.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.formattedQuantity)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(item.isNearlyEmpty ? .orange : .primary)
                        if let value = item.currentStockValue {
                            Text(value, format: .currency(code: "EUR").precision(.fractionLength(2)))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Supprimer", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteStockItem(id: item.id) }
            }
        }
    }
}

private struct InventoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let item: StockItem?

    @State private var name: String
    @State private var quantity: Double
    @State private var unit: InventoryUnit
    @State private var storage: StorageLocation
    @State private var category: FoodCategory
    @State private var emoji: String
    @State private var totalValue: Double
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date

    init(item: StockItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _quantity = State(initialValue: item?.quantity ?? 1)
        _unit = State(initialValue: item?.unit ?? .piece)
        _storage = State(initialValue: item?.storage ?? .roomTemperature)
        _category = State(initialValue: item?.category ?? .snacksAndPantry)
        _emoji = State(initialValue: item?.displayEmoji ?? "🛒")
        _totalValue = State(initialValue: item?.currentStockValue ?? 0)
        _hasExpiration = State(initialValue: item?.expirationDate != nil)
        _expirationDate = State(initialValue: item?.expirationDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Produit") {
                    TextField("Émoji", text: $emoji)
                    TextField("Nom", text: $name)
                    TextField("Quantité", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                    Picker("Unité", selection: $unit) {
                        ForEach(InventoryUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    HStack {
                        TextField("Valeur actuelle", value: $totalValue, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                        Text("€")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Conservation") {
                    Picker("Rangement", selection: $storage) {
                        ForEach(StorageLocation.allCases) { location in
                            Label(location.label, systemImage: location.symbol).tag(location)
                        }
                    }
                    Picker("Catégorie", selection: $category) {
                        ForEach(FoodCategory.allCases) { foodCategory in
                            Label(foodCategory.label, systemImage: foodCategory.symbol).tag(foodCategory)
                        }
                    }
                    Toggle("Ajouter une date limite", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Date", selection: $expirationDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(item == nil ? "Nouveau produit" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || quantity < 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        if let item {
            var updated = item
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.quantity = quantity
            updated.unit = unit
            updated.storage = storage
            updated.category = category
            updated.emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
            updated.unitPrice = quantity > 0 && totalValue > 0 ? totalValue / quantity : nil
            updated.expirationDate = hasExpiration ? expirationDate : nil
            updated.updatedAt = .now
            store.saveStockItem(updated, previousQuantity: item.quantity)
        } else {
            let newItem = StockItem(
                name: name.trimmingCharacters(in: .whitespaces),
                quantity: quantity,
                unit: unit,
                storage: storage,
                category: category,
                emoji: emoji.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init),
                unitPrice: quantity > 0 && totalValue > 0 ? totalValue / quantity : nil,
                expirationDate: hasExpiration ? expirationDate : nil
            )
            store.saveStockItem(newItem)
        }
        Haptics.success()
        dismiss()
    }
}

private struct MovementHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let movements: [StockMovement]

    var body: some View {
        NavigationStack {
            List(movements) { movement in
                HStack(spacing: 12) {
                    Image(systemName: movement.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(movement.delta >= 0 ? FrigoTheme.accent : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(movement.itemName).font(.headline)
                        Text(movement.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(movement.delta >= 0 ? "+" : "")\(movement.delta.formatted(.number.precision(.fractionLength(0...2)))) \(movement.unitRawValue)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text(movement.createdAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if movements.isEmpty {
                    EmptyStateView(symbol: "clock", title: "Aucun mouvement", message: "Les ajouts et consommations apparaîtront ici.")
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}
