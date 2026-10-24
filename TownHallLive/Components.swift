import SwiftUI

// Shared small pieces so every screen looks and behaves the same.

struct CategoryChip: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.goldSoft.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
    }
}

struct OutcomeChip: View {
    let result: String

    private var color: Color {
        switch result {
        case "passed": Theme.green
        case "failed": Theme.burgundy
        default: Theme.inkSecondary
        }
    }

    var body: some View {
        Text(result.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

struct LiveBadge: View {
    var demo = true

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(demo ? Theme.goldBright : Color.red)
                .frame(width: 7, height: 7)
            Text(demo ? "DEMO SESSION" : "LIVE")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(demo ? Theme.gold : Theme.burgundy)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background((demo ? Theme.goldBright : Color.red).opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder((demo ? Theme.goldBright : Color.red).opacity(0.5), lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.inkSecondary)
    }
}

// Numeric results where comparisons matter.
struct TallyRow: View {
    let label: String
    let count: Int
    let maxCount: Int
    let color: Color
    let highlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(highlight ? .semibold : .regular))
                    .foregroundStyle(highlight ? Theme.navy : Theme.ink)
                Spacer()
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(highlight ? Theme.navy : Theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.parchmentDeep)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * ratio))
                        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: count)
                }
            }
            .frame(height: 7)
        }
    }

    private var ratio: CGFloat {
        maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
    }
}
