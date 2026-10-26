import SwiftUI

// "What's happening now": the next scheduled meeting, the newest Town TV
// meeting recordings, and a compact recap of the last Town Meeting that links
// into the Warrants library.
struct LiveView: View {
    let store: DataStore
    var openWarrants: () -> Void = {}

    var body: some View {
        VerticalPage {
            VStack(alignment: .leading, spacing: 24) {
                hero
                nextMeetingSection
                recordingsSection
                if let meeting = store.lastTownMeeting {
                    LastTownMeetingCard(store: store, meeting: meeting, openWarrants: openWarrants)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .refreshable { await store.refresh() }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("TownHall Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel(L("Settings"))
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                SectionLabel(text: "\(store.data?.town.name ?? L("Town")) · \(L(store.data?.town.state ?? "Massachusetts"))")
            }
            Text(L("Happening now"))
                .font(Theme.displayFont)
                .foregroundStyle(Theme.ink)
            LiveStatusLine(store: store)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: Next meeting

    @ViewBuilder
    private var nextMeetingSection: some View {
        let upcoming = store.upcomingMeetings
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(text: L("Next meeting"))
            if let next = upcoming.first {
                upcomingCard(next, featured: true)
                ForEach(upcoming.dropFirst().prefix(2)) { meeting in
                    upcomingCard(meeting, featured: false)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(Theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("No Town Meeting scheduled."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(L("Annual Town Meeting is held each spring."))
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Theme.cardPadding)
                .card()
            }
        }
    }

    private func upcomingCard(_ meeting: Meeting, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                SectionLabel(text: L("Upcoming"))
            }
            Text(meetingNameText(meeting.title))
                .font(featured ? Theme.titleFont : .subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(dateLineText(meeting.date))
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if featured {
                HStack(spacing: 10) {
                    if meeting.isTownMeeting, !store.articles(in: meeting.id).isEmpty {
                        Button(action: openWarrants) {
                            pillStyle(L("Read the warrant"), systemImage: "doc.text", filled: true)
                        }
                        .pressable()
                    }
                    if let link = meeting.link.flatMap(URL.init(string:)) {
                        Link(destination: link) {
                            pillStyle(L("Event details"), systemImage: "arrow.up.right", filled: false)
                        }
                        .pressable()
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Recordings

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(text: L("Latest meeting recordings"))
            let items = Array(store.recordings.prefix(6))
            if items.isEmpty {
                Text(L("Recordings from Town TV appear here once the channel posts them."))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(items) { recording in
                if let link = recording.streamURL.flatMap(URL.init(string:)) {
                    Link(destination: link) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.tile)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.ink)
                                )
                                .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meetingNameText(recording.title))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(dateLineText(recording.date))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary.opacity(0.5))
                        }
                        .padding(13)
                        .card()
                    }
                    .pressable()
                }
            }
        }
    }
}

// "Last Town Meeting · May 4, 2026" with its outcomes at a glance.
struct LastTownMeetingCard: View {
    let store: DataStore
    let meeting: Meeting
    var openWarrants: () -> Void

    private var articles: [WarrantArticle] { store.articles(in: meeting.id) }

    private func count(_ result: String) -> Int {
        articles.filter { $0.officialOutcome?.result == result }.count
    }

    private var dateText: String {
        guard let date = meeting.parsedDate else { return meeting.date }
        return date.formatted(.dateTime.month(.wide).day().year().locale(AppSettings.shared.language.locale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: L("Last Town Meeting · %@", dateText))
            Text(meetingNameText(meeting.title))
                .font(Theme.titleFont)
                .foregroundStyle(Theme.ink)
            if articles.isEmpty {
                Text(L("Outcomes appear here once the results are published."))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Articles on the warrant: %@", String(articles.count)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                outcomeSummary
            }
            HStack(spacing: 10) {
                NavigationLink(value: meeting.id) {
                    pillStyle(L("See outcomes"), systemImage: "checklist", filled: true)
                }
                .pressable()
                Button(action: openWarrants) {
                    pillStyle(L("Warrants"), systemImage: "doc.text", filled: false)
                }
                .pressable()
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // Wraps onto as many lines as it needs instead of growing sideways.
    private var outcomeSummary: some View {
        let items: [(String, Int)] = [("passed", count("passed")), ("failed", count("failed")),
                                      ("no action", count("no action")), ("postponed", count("postponed"))]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(items.filter { $0.1 > 0 }, id: \.0) { result, n in
                HStack(spacing: 8) {
                    OutcomeChip(result: result)
                    Text(verbatim: String(n))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }
}
