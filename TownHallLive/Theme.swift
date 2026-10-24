import SwiftUI

enum Theme {
    // Civic-formal palette: parchment page, deep navy ink, brass/gold accents,
    // burgundy reserved for "failed" outcomes. One accent does the work.
    static let parchment    = Color(hex: 0xF6F1E7)
    static let parchmentCard = Color(hex: 0xFDFBF5)
    static let navy         = Color(hex: 0x1E2A48)
    static let ink          = Color(hex: 0x232A3F)
    static let inkSecondary = Color(hex: 0x5D6478)
    static let gold         = Color(hex: 0xA67C22)
    static let goldSoft     = Color(hex: 0xEADFC4)
    static let burgundy     = Color(hex: 0x7A2632)
    static let green        = Color(hex: 0x3D6B43)
    static let divider      = Color(hex: 0xE2D9C6)

    static let displayFont = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let titleFont   = Font.system(.title2, design: .serif, weight: .semibold)
    static let headlineFont = Font.system(.headline, design: .serif)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// A quiet card: flat fill, hairline divider, no stacked shadows.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.parchmentCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
