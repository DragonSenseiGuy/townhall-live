import SwiftUI

enum Theme {
    // Uber-style: near-white canvas, flat white cards, heavy black type,
    // hairline gaps instead of borders. One accent blue does all signaling.
    static let canvas        = Color(hex: 0xF6F6F6)   // "dark white"
    static let surface       = Color(hex: 0xFFFFFF)
    static let tile          = Color(hex: 0xF1F1F2)   // gray icon tiles
    static let ink           = Color(hex: 0x0B0B0C)
    static let inkSecondary  = Color(hex: 0x6C6C70)
    static let divider       = Color(hex: 0xEBEBEC)
    static let accent        = Color(hex: 0x0E5FD8)   // Uber blue
    static let accentSoft    = Color(hex: 0xE8F0FE)
    static let green         = Color(hex: 0x1B7A34)
    static let greenSoft     = Color(hex: 0xE7F4EA)
    static let red           = Color(hex: 0xC21F1F)
    static let redSoft       = Color(hex: 0xFBEBEB)

    static let pagePadding: CGFloat = 18
    static let cardPadding: CGFloat = 16

    // Uber-style hierarchy: weight does the work, no serif, no decorative fonts.
    static let displayFont  = Font.system(.title, design: .default, weight: .bold)
    static let titleFont    = Font.system(.title3, design: .default, weight: .bold)
    static let headlineFont = Font.system(.headline, design: .default, weight: .semibold)
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

// Flat card: white surface, no border, no shadow — separation comes from the
// canvas gap under it.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// Press feedback for tappable rows: answers instantly, releases fast.
    func pressable() -> some View { buttonStyle(PressableButtonStyle()) }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// Uber-style section title: bold sentence case, no rules, no decor.
struct SectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.headline, design: .default, weight: .bold))
            .foregroundStyle(Theme.ink)
    }
}

// Micro-label: the only place tracked caps survive.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased(with: AppSettings.shared.language.locale))
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.inkSecondary)
    }
}

// The shared row recipe for any warrant article. Gray number tile — the
// Uber menu-motif — leads; SF Symbols and chips trail.
struct ArticleRow: View {
    let article: WarrantArticle
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            NumberTile(number: article.number, highlighted: isCurrent)
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(Theme.ink)
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.5))
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// Gray rounded tile with the article number, lifting to blue for the article
// currently on the floor.
struct NumberTile: View {
    let number: Int
    var highlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(highlighted ? Theme.accent : Theme.tile)
            .overlay(
                Text(verbatim: "\(number)")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(highlighted ? .white : Theme.ink)
            )
            .frame(width: 34, height: 34)
    }
}

func pillStyle(_ label: String, systemImage: String, filled: Bool) -> some View {
    HStack(spacing: 6) {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
        Text(label)
            .font(.subheadline.weight(.semibold))
    }
    .foregroundStyle(filled ? .white : Theme.ink)
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
    .background(filled ? Theme.ink : Theme.tile, in: Capsule())
}

// Every screen scrolls vertically only. The content is pinned to the scroll
// view's own width (`containerRelativeFrame`), so nothing inside — a long
// unbreakable run of text, a row whose ideal width is wider than the phone, a
// sliding transition — can widen the scroll content and let the whole page
// pan sideways on a horizontal swipe.
struct VerticalPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollIndicators(.hidden)
    }
}
