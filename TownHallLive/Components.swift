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

// Election-night share bar: one tall capsule split by community share —
// yay, abstain, nay — rather than three separate rows. Zero shares simply
// don't appear; the roll count lives in the legend next to it.
struct VoteShareBar: View {
    let yay: Int
    let abstain: Int
    let nay: Int

    private var total: Int { yay + abstain + nay }
    private var segmentCount: Int { [yay, abstain, nay].filter { $0 > 0 }.count }
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: segmentCount > 1 ? gap : 0) {
                if total == 0 {
                    Capsule().fill(Theme.tile)
                        .frame(maxWidth: .infinity)
                }
                if yay > 0 {
                    segment(Theme.green, count: yay, width: geo.size.width)
                }
                if abstain > 0 {
                    segment(Theme.inkSecondary, count: abstain, width: geo.size.width)
                }
                if nay > 0 {
                    segment(Theme.red, count: nay, width: geo.size.width)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: [yay, abstain, nay])
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func segment(_ color: Color, count: Int, width: CGFloat) -> some View {
        let usable = width - gap * CGFloat(segmentCount - 1)
        let share = total == 0 ? 0 : CGFloat(count) / CGFloat(total)
        return Capsule()
            .fill(color)
            .frame(width: max(8, usable * share))
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: count)
    }
}
