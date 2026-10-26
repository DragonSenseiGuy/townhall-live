import SwiftUI

// Shared small pieces so every screen looks and behaves the same.

struct CategoryChip: View {
    let text: String

    var body: some View {
        Text(L(text))
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

    private var label: String { outcomeLabel(result) }

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
        if store.isRefreshing { return L("Updating from the town website…") }
        guard store.isLiveConfigured, let updated = store.lastUpdated else { return L("Showing saved town data") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = AppSettings.shared.language.locale
        return L("Updated %@", formatter.localizedString(for: min(updated, now), relativeTo: now))
    }
}
