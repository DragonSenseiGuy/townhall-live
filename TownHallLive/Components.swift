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
                    .foregroundStyle(highlight ? Theme.ink : Theme.inkSecondary)
                Spacer()
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(highlight ? Theme.ink : Theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tile)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * ratio))
                        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: count)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
    }

    private var ratio: CGFloat {
        maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
    }
}

// "Updated 5 minutes ago" — where the data on screen came from and how fresh it is.
struct LiveStatusLine: View {
    let store: DataStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(text(now: context.date))
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func text(now: Date) -> String {
        if store.isRefreshing { return "Updating from the town website…" }
        guard store.isLiveConfigured, let updated = store.lastUpdated else { return "Showing saved town data" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: min(updated, now), relativeTo: now))"
    }
}
