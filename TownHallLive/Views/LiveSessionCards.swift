import SwiftUI

// The 20-second magic of the demo video: a clearly-labeled simulated session
// that plays through a real past meeting's script.
struct DemoSessionCard: View {
    var session: DemoSessionController
    let store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Simulated live feed")
                Spacer()
                Text("\(session.stepIndex + 1) of \(session.steps.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }

            if let step = session.current {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.headline)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.caption)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step.id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                progressDots

                if let article = store.article(id: step.articleID) {
                    NavigationLink(value: article.id) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.footnote)
                            Text("Read Article \(article.number)")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .pressable()
                }

                controls
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Watch the meeting as it happens")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A simulated playback of a recent Town Meeting so you can see how a remote session feels.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        session.start()
                    } label: {
                        pillLabel("Play demo session", systemImage: "play.fill", filled: true)
                    }
                    .pressable()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.cardPadding)
        .card()
        .animation(.easeOut(duration: 0.3), value: session.current?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: session.current?.id)
    }

    // Progress only moves forward like the meeting does.
    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(session.steps) { step in
                Capsule()
                    .fill(fill(for: step))
                    .frame(width: width(for: step), height: 4)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.current?.id)
    }

    private func fill(for step: DemoStep) -> Color {
        guard let current = session.current else { return Theme.tile }
        if step.id == current.id { return Theme.accent }
        return step.id < current.id ? Theme.accent.opacity(0.4) : Theme.tile
    }

    private func width(for step: DemoStep) -> CGFloat {
        session.current?.id == step.id ? 18 : 4
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                session.isRunning ? session.pause() : session.start()
            } label: {
                iconControl(session.isRunning ? "pause.fill" : "play.fill", filled: true)
            }
            .pressable()
            Button {
                session.next()
            } label: {
                iconControl("forward.end.fill", filled: false)
            }
            .pressable()
            Button {
                session.stop()
            } label: {
                Text("End demo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.tile, in: Capsule())
            }
            .pressable()
            Spacer()
        }
    }

    private func iconControl(_ symbol: String, filled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.callout)
            .foregroundStyle(filled ? .white : Theme.ink)
            .frame(width: 38, height: 38)
            .background(filled ? Theme.ink : Theme.tile, in: Circle())
    }

    private func pillLabel(_ text: String, systemImage: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(filled ? .white : Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(filled ? Theme.ink : Theme.tile, in: Capsule())
    }
}

// Mock voting: the user can't vote officially — a clearly-labeled simulated
// poll so remote constituents can make their voice feel heard.
struct MockVoteCard: View {
    let article: WarrantArticle
    var votes: MockVoteController

    private var myVote: VoteChoice? { votes.myVote(for: article.id) }

    private var counts: (yay: Int, nay: Int, abstain: Int) {
        let add: (VoteChoice) -> Int = { myVote == $0 ? 1 : 0 }
        return (
            article.simulatedTally.yay + add(.yay),
            article.simulatedTally.nay + add(.nay),
            (article.simulatedTally.abstain ?? 0) + add(.abstain)
        )
    }

    private var maxCount: Int {
        max(counts.yay, counts.nay, counts.abstain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(text: "How would you vote?")
                Text("Simulated")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(alignment: .top, spacing: 12) {
                NumberTile(number: article.number)
                Text(article.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(VoteChoice.allCases) { choice in
                    voteButton(choice)
                }
            }

            if let vote = myVote {
                results(vote)
                    .transition(.opacity)
            } else {
                Text("Your vote is recorded locally as a simulation — real voting happens in person at the meeting.")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }
        }
        .padding(Theme.cardPadding)
        .card()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: myVote)
    }

    private func voteButton(_ choice: VoteChoice) -> some View {
        let selected = myVote == choice
        let color: Color = choice == .yay ? Theme.green : (choice == .nay ? Theme.red : Theme.inkSecondary)
        return Button {
            votes.cast(choice, for: article.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: choice == .yay ? "checkmark" : (choice == .nay ? "xmark" : "minus"))
                    .font(.footnote.weight(.bold))
                Text(choice.rawValue)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selected ? .white : color)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selected ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .pressable()
        .sensoryFeedback(.impact(weight: .medium), trigger: votes.votes[article.id])
    }

    private func results(_ vote: VoteChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text("You voted \(vote.rawValue.lowercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            TallyRow(label: "Yay", count: counts.yay, maxCount: maxCount, color: Theme.green, highlight: vote == .yay)
            TallyRow(label: "Nay", count: counts.nay, maxCount: maxCount, color: Theme.red, highlight: vote == .nay)
            TallyRow(label: "Abstain", count: counts.abstain, maxCount: maxCount, color: Theme.inkSecondary, highlight: vote == .abstain)
            Text("Community numbers are simulated demo data.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary.opacity(0.75))
        }
    }
}
