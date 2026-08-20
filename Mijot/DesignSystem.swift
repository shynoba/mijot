import SwiftUI
import UIKit

enum FrigoTheme {
    static let accent = Color.black
    static let secondaryAccent = Color(white: 0.42)
    static let cardRadius: CGFloat = 20

    static func color(named name: String) -> Color {
        accent
    }
}

struct AppBackground: View {
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: FrigoTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FrigoTheme.cardRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
    }
}

struct SymbolBadge: View {
    let symbol: String
    var color: Color = FrigoTheme.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct EmojiBadge: View {
    let emoji: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityLabel("Illustration du produit")
    }
}

struct MijotLogoView: View {
    var size: CGFloat = 52

    var body: some View {
        Image("MijotLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityLabel("Logo Mijot")
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            SymbolBadge(symbol: symbol, size: 58)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
