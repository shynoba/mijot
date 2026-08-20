import SwiftUI

struct PlannerView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var calendarService: MealCalendarService
    @State private var displayedWeek = Calendar.current.startOfWeek(containing: .now)
    @State private var addDate = Date.now
    @State private var showAddMeal = false
    @State private var showCalendarSettings = false
    @State private var errorMessage: String?

    private var meals: [PlannedMeal] { store.plannedMeals.sorted { $0.scheduledDate < $1.scheduledDate } }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: displayedWeek) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 14) {
                    weekSelector
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(days, id: \.self) { day in
                                DayColumn(
                                    date: day,
                                    meals: mealsForDay(day),
                                    onAdd: { addDate = day; showAddMeal = true },
                                    onConsume: consume,
                                    onDelete: delete,
                                    onDropMeal: { moveMeal(id: $0, to: day) }
                                )
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
            .navigationTitle("Ma semaine")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showCalendarSettings = true
                    } label: {
                        Image(systemName: store.calendarPreferences.isEnabled ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    }
                    Button { addDate = .now; showAddMeal = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddMeal) {
                AddMealView(initialDate: addDate)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCalendarSettings) {
                CalendarSettingsView(preferences: store.calendarPreferences)
                    .environmentObject(store)
                    .environmentObject(calendarService)
            }
            .alert("Action impossible", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Une erreur est survenue.")
            }
        }
    }

    private var weekSelector: some View {
        GlassCard {
            HStack {
                Button { changeWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)

                Spacer()
                VStack(spacing: 3) {
                    Text("Semaine du \(displayedWeek.formatted(.dateTime.day().month(.wide)))")
                        .font(.headline)
                    Button("Aujourd’hui") {
                        withAnimation(.snappy) { displayedWeek = Calendar.current.startOfWeek(containing: .now) }
                    }
                    .font(.caption.weight(.semibold))
                }
                Spacer()

                Button { changeWeek(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
        }
    }

    private func mealsForDay(_ day: Date) -> [PlannedMeal] {
        meals.filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: day) }
            .sorted { ($0.slot == .lunch ? 0 : 1) < ($1.slot == .lunch ? 0 : 1) }
    }

    private func changeWeek(by offset: Int) {
        withAnimation(.snappy) {
            displayedWeek = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: displayedWeek) ?? displayedWeek
        }
        Haptics.selection()
    }

    private func moveMeal(id: String, to date: Date) {
        guard let uuid = UUID(uuidString: id), let meal = meals.first(where: { $0.id == uuid }) else { return }
        let newDate = store.calendarPreferences.date(on: date, for: meal.slot)
        do {
            if let identifier = meal.calendarEventIdentifier {
                try calendarService.moveEvent(
                    identifier: identifier,
                    to: date,
                    slot: meal.slot,
                    preferences: store.calendarPreferences
                )
            }
            withAnimation(.snappy) {
                store.moveMeal(id: meal.id, to: newDate)
            }
            Haptics.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func consume(_ meal: PlannedMeal) {
        guard !meal.isConsumed else { return }
        do {
            try store.consumeMeal(id: meal.id)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ meal: PlannedMeal) {
        if let identifier = meal.calendarEventIdentifier {
            calendarService.removeEvent(identifier: identifier)
        }
        withAnimation {
            store.deleteMeal(id: meal.id)
        }
    }
}

private struct DayColumn: View {
    let date: Date
    let meals: [PlannedMeal]
    let onAdd: () -> Void
    let onConsume: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void
    let onDropMeal: (String) -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.subheadline.weight(isToday ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? FrigoTheme.accent : .secondary)
            }
            .frame(maxWidth: .infinity)

            if meals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Aucun repas")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 130)
            } else {
                ForEach(meals) { meal in
                    PlannedMealCard(meal: meal, onConsume: { onConsume(meal) }, onDelete: { onDelete(meal) })
                        .draggable(meal.id.uuidString)
                }
            }

            Button(action: onAdd) {
                Label("Ajouter", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 210)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isToday ? Color.black : Color.black.opacity(0.07), lineWidth: isToday ? 1.5 : 0.7)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            onDropMeal(id)
            return true
        } isTargeted: { _ in }
    }
}

private struct PlannedMealCard: View {
    let meal: PlannedMeal
    let onConsume: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(meal.slot.rawValue, systemImage: meal.slot.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(meal.slot == .lunch ? .orange : .indigo)
                Spacer()
                if meal.isConsumed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FrigoTheme.accent)
                }
            }
            Text(meal.recipeName)
                .font(.headline)
                .strikethrough(meal.isConsumed, color: .secondary)
                .foregroundStyle(meal.isConsumed ? .secondary : .primary)
            Label("\(meal.servings) pers.", systemImage: "person.2")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(meal.scheduledDate.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                if meal.calendarEventIdentifier != nil {
                    Label("Calendrier", systemImage: "calendar.badge.checkmark")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !meal.isConsumed {
                Button(action: onConsume) {
                    Text("Plat préparé")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(FrigoTheme.accent)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("Supprimer", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

private struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var calendarService: MealCalendarService
    let initialDate: Date

    @State private var selectedRecipeID = ""
    @State private var date: Date
    @State private var slot = MealSlot.dinner
    @State private var servings = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialDate: Date) {
        self.initialDate = initialDate
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recette") {
                    if store.allRecipes.isEmpty {
                        Label("Générez d’abord vos recettes avec Gemini.", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Choisir", selection: $selectedRecipeID) {
                            ForEach(store.allRecipes) { recipe in
                                Label(recipe.name, systemImage: recipe.symbol).tag(recipe.id)
                            }
                        }
                        .onChange(of: selectedRecipeID) { _, newValue in
                            servings = store.recipe(id: newValue)?.baseServings ?? 1
                        }
                    }
                }
                Section("Quand ?") {
                    DatePicker("Jour", selection: $date, displayedComponents: .date)
                    Picker("Repas", selection: $slot) {
                        ForEach(MealSlot.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    Stepper("\(servings) personne\(servings > 1 ? "s" : "")", value: $servings, in: 1...12)
                    LabeledContent("Heure") {
                        Text(store.calendarPreferences.timeLabel(for: slot))
                    }
                }
                if store.calendarPreferences.isEnabled {
                    Section {
                        Label("Le repas sera également ajouté au calendrier choisi.", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle("Ajouter un repas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Ajout…" : "Ajouter") {
                        Task { await saveMeal() }
                    }
                    .disabled(store.recipe(id: selectedRecipeID) == nil || isSaving)
                }
            }
            .onAppear {
                if selectedRecipeID.isEmpty {
                    selectedRecipeID = store.allRecipes.first?.id ?? ""
                }
            }
            .alert("Calendrier indisponible", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Une erreur est survenue.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func saveMeal() async {
        guard let recipe = store.recipe(id: selectedRecipeID) else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let preferences = store.calendarPreferences
            let eventIdentifier = preferences.isEnabled
                ? try await calendarService.createEvent(
                    for: recipe,
                    on: date,
                    slot: slot,
                    servings: servings,
                    preferences: preferences
                )
                : nil
            store.addMeal(PlannedMeal(
                recipeID: recipe.id,
                recipeName: recipe.name,
                scheduledDate: preferences.date(on: date, for: slot),
                slot: slot,
                servings: servings,
                calendarEventIdentifier: eventIdentifier
            ))
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
