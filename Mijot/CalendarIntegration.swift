import EventKit
import SwiftUI

struct CalendarOption: Identifiable, Hashable {
    let id: String
    let title: String
    let account: String

    var displayName: String {
        account.isEmpty ? title : "\(title) · \(account)"
    }
}

enum MealCalendarError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Mijot n’a pas accès au calendrier. Autorisez-le dans Réglages > Confidentialité et sécurité > Calendriers."
        case .noWritableCalendar:
            "Aucun calendrier modifiable n’est disponible. Ajoutez d’abord un compte iCloud ou Google dans les réglages de l’iPhone."
        case .saveFailed:
            "Le repas n’a pas pu être ajouté au calendrier."
        }
    }
}

@MainActor
final class MealCalendarService: ObservableObject {
    private let eventStore = EKEventStore()

    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendars: [CalendarOption] = []

    init() {
        refresh()
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var authorizationLabel: String {
        if authorizationStatus == .fullAccess { return "Autorisé" }
        return switch authorizationStatus {
        case .notDetermined: "Non demandé"
        case .restricted: "Accès restreint"
        case .denied: "Accès refusé"
        case .writeOnly: "Écriture uniquement"
        default: "État inconnu"
        }
    }

    func refresh() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard hasFullAccess else {
            calendars = []
            return
        }
        eventStore.refreshSourcesIfNecessary()
        calendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map {
                CalendarOption(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    account: $0.source.title
                )
            }
            .sorted {
                if $0.account != $1.account { return $0.account.localizedCaseInsensitiveCompare($1.account) == .orderedAscending }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    @discardableResult
    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        refresh()
        return granted
    }

    func ensureAccess() async throws {
        refresh()
        if hasFullAccess { return }
        guard authorizationStatus == .notDetermined else { throw MealCalendarError.accessDenied }
        guard try await requestAccess() else { throw MealCalendarError.accessDenied }
    }

    func createEvent(
        for recipe: Recipe,
        on day: Date,
        slot: MealSlot,
        servings: Int,
        preferences: CalendarPreferences
    ) async throws -> String {
        try await ensureAccess()

        let selected = preferences.selectedCalendarIdentifier.flatMap(eventStore.calendar(withIdentifier:))
        guard let calendar = selected ?? eventStore.defaultCalendarForNewEvents,
              calendar.allowsContentModifications else {
            throw MealCalendarError.noWritableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = "🍽️ \(recipe.name)"
        event.startDate = preferences.date(on: day, for: slot)
        event.endDate = Calendar.current.date(
            byAdding: .minute,
            value: preferences.eventDurationMinutes,
            to: event.startDate
        ) ?? event.startDate.addingTimeInterval(3_600)
        event.notes = eventNotes(for: recipe, servings: servings)
        event.availability = .free

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            throw MealCalendarError.saveFailed
        }
        guard let identifier = event.eventIdentifier else { throw MealCalendarError.saveFailed }
        return identifier
    }

    func removeEvent(identifier: String) {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        try? eventStore.remove(event, span: .thisEvent, commit: true)
    }

    func moveEvent(
        identifier: String,
        to day: Date,
        slot: MealSlot,
        preferences: CalendarPreferences
    ) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        event.startDate = preferences.date(on: day, for: slot)
        event.endDate = Calendar.current.date(
            byAdding: .minute,
            value: preferences.eventDurationMinutes,
            to: event.startDate
        ) ?? event.startDate.addingTimeInterval(3_600)
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            throw MealCalendarError.saveFailed
        }
    }

    private func eventNotes(for recipe: Recipe, servings: Int) -> String {
        let calories = recipe.estimatedCalories.map { " · \($0) kcal" } ?? ""
        let ingredients = recipe.ingredients
            .map { "• \($0.quantity.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit.shortLabel) \($0.name)" }
            .joined(separator: "\n")
        return """
        Ajouté avec Mijot · \(servings) personne\(servings > 1 ? "s" : "")\(calories)

        Ingrédients
        \(ingredients)
        """
    }
}

struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var calendarService: MealCalendarService

    @State private var draft: CalendarPreferences
    @State private var accessError: String?
    @State private var isRequestingAccess = false

    init(preferences: CalendarPreferences) {
        _draft = State(initialValue: preferences)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Ajouter les repas au calendrier", isOn: $draft.isEnabled)

                    HStack {
                        Label("Autorisation", systemImage: calendarService.hasFullAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                        Spacer()
                        Text(calendarService.authorizationLabel)
                            .foregroundStyle(.secondary)
                    }

                    if draft.isEnabled && !calendarService.hasFullAccess {
                        Button {
                            requestAccess()
                        } label: {
                            Label(isRequestingAccess ? "Autorisation…" : "Autoriser le calendrier", systemImage: "calendar.badge.plus")
                        }
                        .disabled(isRequestingAccess)
                    }
                } header: {
                    Text("Synchronisation")
                } footer: {
                    Text("EventKit ajoute l’événement au calendrier Apple, iCloud ou Google configuré sur cet appareil. Mijot ne reçoit jamais le mot de passe du compte.")
                }

                if calendarService.hasFullAccess {
                    Section("Calendrier de destination") {
                        Picker("Calendrier", selection: $draft.selectedCalendarIdentifier) {
                            Text("Calendrier par défaut").tag(nil as String?)
                            ForEach(calendarService.calendars) { calendar in
                                Text(calendar.displayName).tag(Optional(calendar.id))
                            }
                        }
                    }
                }

                Section {
                    DatePicker(
                        "Déjeuner",
                        selection: timeBinding(for: .lunch),
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "Dîner",
                        selection: timeBinding(for: .dinner),
                        displayedComponents: .hourAndMinute
                    )
                    Stepper(
                        "Durée : \(draft.eventDurationMinutes) min",
                        value: $draft.eventDurationMinutes,
                        in: 15...180,
                        step: 15
                    )
                } header: {
                    Text("Horaires par défaut")
                } footer: {
                    Text("Valeurs initiales : 12 h 30 pour le déjeuner et 19 h 30 pour le dîner.")
                }

                if let accessError {
                    Section {
                        Label(accessError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Calendrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.saveCalendarPreferences(draft)
                        Haptics.success()
                        dismiss()
                    }
                }
            }
            .onAppear { calendarService.refresh() }
        }
        .presentationDetents([.medium, .large])
    }

    private func timeBinding(for slot: MealSlot) -> Binding<Date> {
        Binding(
            get: { draft.date(on: .now, for: slot) },
            set: { draft.setTime($0, for: slot) }
        )
    }

    private func requestAccess() {
        isRequestingAccess = true
        accessError = nil
        Task {
            do {
                let granted = try await calendarService.requestAccess()
                if !granted { accessError = MealCalendarError.accessDenied.localizedDescription }
            } catch {
                accessError = error.localizedDescription
            }
            isRequestingAccess = false
        }
    }
}
