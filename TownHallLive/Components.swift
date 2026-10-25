import SwiftUI

// Shared small pieces so every screen looks and behaves the same.

struct CategoryChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.tile, in: Capsule())
    }
}

struct OutcomeChip: View {
    let result: String

    private var label: String {
        result == "no action" ? "No action" : result.capitalized
    }

    private var tint: Color {
        switch result {
        case "passed": Theme.green
        case "failed": Theme.red
        default: Theme.inkSecondary
        }
    }

    private var background: Color {
        switch result {
        case "passed": Theme.greenSoft
        case "failed": Theme.redSoft
        default: Theme.tile
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

struct LiveBadge: View {
    var demo = true

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(demo ? Theme.accent : Color.red)
                .frame(width: 7, height: 7)
            Text(demo ? "Demo session" : "Live")
                .font(.caption.weight(.bold))
                .foregroundStyle(demo ? Theme.accent : Color.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(demo ? Theme.accentSoft : Theme.redSoft, in: Capsule())
    }
}

// Numeric results where comparisons matter. Bars spring; numbers count.
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
                    .foregroundStyle(highlight ? Theme.ink : Theme.inkSecondary)
                Spacer()
                Text("\(Int(rubberCount))")
                    .font(.subheadline.weight(highlight ? .bold : .regular))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                    .foregroundStyle(highlight ? Theme.ink : Theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tile)
                    Capsule()
                        .fill(color)
                        // A zero count shows nothing — no ghost dot.
                        .frame(width: count == 0 ? 0 : max(6, geo.size.width * ratio))
                        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: count)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.95), value: count)
        .onAppear { rubberCount = Double(count) }
        .onChange(of: count) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.95)) {
                rubberCount = Double(newValue)
            }
        }
    }

    // Visible digit rolls with the same spring as the bar.
    @State private var rubberCount: Double = 0

    private var ratio: CGFloat {
        maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
    }
}
