import SwiftUI

enum Theme {
    // Civic-formal. Parchment page, deep navy ink, brass accents used sparingly
    // (hairlines, seals, one rule per section). Burgundy is reserved for failures.
    static let parchment      = Color(hex: 0xF3EEE3)
    static let parchmentCard  = Color(hex: 0xFFFCF4)
    static let parchmentDeep  = Color(hex: 0xEBE4D3)
    static let navy           = Color(hex: 0x1E2A48)
    static let ink            = Color(hex: 0x2A3145)
    static let inkSecondary   = Color(hex: 0x6B7180)
    static let gold           = Color(hex: 0xA67C22)
    static let goldBright     = Color(hex: 0xC9A651)
    static let goldSoft       = Color(hex: 0xEFE6CE)
    static let burgundy       = Color(hex: 0x7A2632)
    static let green          = Color(hex: 0x3D6B43)
    static let divider        = Color(hex: 0xE7DECB)

    // One 4-pt rhythm. Cards breathe on 16; pages on 20.
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16

    static let displayFont  = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let titleFont    = Font.system(.title2, design: .serif, weight: .semibold)
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

// A quiet card: flat fill, hairline edge, one soft shadow for lift.
// Nothing stacked, nothing loud.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.parchmentCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.045), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// Press feedback for tappable rows: answers the finger instantly, releases fast.
    func pressable() -> some View { buttonStyle(PressableButtonStyle()) }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

// Section header: tracked caps label finishing in a gold hairline.
struct SectionHeader: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.inkSecondary)
            Rectangle()
                .fill(Theme.gold.opacity(0.55))
                .frame(height: 1)
            Spacer(minLength: 0)
        }
    }
}

// The shared row recipe for any warrant article, so the agenda, the warrants
// list, and meeting details read identically.
struct ArticleRow: View {
    let article: WarrantArticle
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            NumberSeal(number: article.number, highlighted: isCurrent)
            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    CategoryChip(text: article.category)
                    if let outcome = article.officialOutcome {
                        OutcomeChip(result: outcome.result)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.divider)
        }
        .padding(12)
        .background(
            isCurrent ? Theme.goldSoft.opacity(0.5) : Theme.parchmentCard,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if isCurrent {
                Capsule()
                    .fill(Theme.gold)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, -1)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isCurrent ? Theme.gold.opacity(0.55) : Theme.divider, lineWidth: 1)
        )
    }
}

// Small circle "seal" carrying the article number — the institutional motif
// that replaces bare digits.
struct NumberSeal: View {
    let number: Int
    var highlighted = false

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted ? Theme.gold : Theme.parchmentDeep)
            Circle()
                .strokeBorder(highlighted ? Theme.goldBright : Theme.divider, lineWidth: 1)
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(highlighted ? .white : Theme.navy)
        }
        .frame(width: 32, height: 32)
    }
}
