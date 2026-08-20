import SwiftUI

@main
struct MijotApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var calendarService = MealCalendarService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(FrigoTheme.accent)
                .preferredColorScheme(.light)
                .environmentObject(store)
                .environmentObject(calendarService)
        }
    }
}
