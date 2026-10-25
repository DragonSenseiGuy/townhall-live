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
    // Lighter blue so the accent stays readable on the ink-black feed card.
    static let accentOnInk   = Color(hex: 0x6FA5F5)

    static let pagePadding: CGFloat = 18
    static let cardPadding: CGFloat = 16

    // Uber-style hierarchy: weight does the work, no serif, no decorative fonts.
    // Display type is pushed genuinely big — hierarchy comes from size contrast,
    // not from adding more styles.
    static let displayFont  = Font.system(size: 38, weight: .black, design: .default)
    static let titleFont    = Font.system(.title3, design: .default, weight: .bold)
    static let headlineFont = Font.system(.headline, design: .default, weight: .semibold)
    // The "record" register: monospaced metadata that reads like a clerk's log.
    // This is the one place the app's civic voice becomes a visible signature.
    static let recordFont   = Font.system(.caption2, design: .monospaced, weight: .semibold)
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
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.inkSecondary)
    }
}

// The shared row recipe for any warrant article: printed-warrant ledger
// styling. A big monospaced numeral sits in a fixed gutter (the page number
// column of a warrant sheet), the official outcome is set in the record
// register at the trailing edge — no floating cards, no chips.
struct ArticleRow: View {
    let article: WarrantArticle
    let isCurrent: Bool
    static let gutter: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            Text("\(article.number)")
                .font(.system(size: 21, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Theme.accent : Theme.ink)
                .frame(width: Self.gutter, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.footnote.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent {
                    Text("On the floor now")
                        .font(Theme.recordFont)
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 10)
            if let outcome = article.officialOutcome {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(registerLabel(outcome.result))
                        .font(Theme.recordFont)
                        .foregroundStyle(registerTint(outcome.result))
                    if let tally = outcome.tally {
                        Text(verbatim: tally)
                            .font(Theme.recordFont)
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: 116, alignment: .trailing)
            } else {
                Text(registerLabel(article.category))
                    .font(Theme.recordFont)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.45))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func registerLabel(_ result: String) -> String {
        result == "no action" ? "NO ACTION" : result.uppercased()
    }

    private func registerTint(_ result: String) -> Color {
        switch result {
        case "passed": Theme.green
        case "failed": Theme.red
        default: Theme.inkSecondary
        }
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
                Text("\(number)")
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
