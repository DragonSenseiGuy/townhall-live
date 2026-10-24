import SwiftUI

// Shared small pieces so every screen looks and behaves the same.

struct CategoryChip: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule().strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1)
            )
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
            .font(.caption.weight(.bold))
            .tracking(0.6)
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
                .fill(demo ? Theme.gold : Color.red)
                .frame(width: 7, height: 7)
            Text(demo ? "DEMO SESSION" : "LIVE")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(demo ? Theme.gold : Color.red)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .overlay(Capsule().strokeBorder((demo ? Theme.gold : Color.red).opacity(0.5), lineWidth: 1))
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
                Spacer()
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(highlight ? Theme.navy : Theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.divider.opacity(0.5))
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
        }
    }

    private var ratio: CGFloat {
        maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.inkSecondary)
    }
}
