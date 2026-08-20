import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }

            TicketImportView()
                .tabItem { Label("Ticket", systemImage: "doc.text.viewfinder") }

            InventoryView()
                .tabItem { Label("Stock", systemImage: "basket.fill") }

            RecipesView()
                .tabItem { Label("Recettes", systemImage: "fork.knife") }

            PlannerView()
                .tabItem { Label("Semaine", systemImage: "calendar") }
        }
        .toolbarBackground(Color.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
