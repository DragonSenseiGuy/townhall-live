import SwiftUI

// The 20-second magic of the demo video: a clearly-labeled simulated session
// that plays through a real past meeting's script.
struct DemoSessionCard: View {
    var session: DemoSessionController
    let store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                        .foregroundStyle(Theme.navy)
                    Text(step.caption)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step.id)
                .transition(.opacity)

                progressDots

                if let article = store.article(id: step.articleID) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.footnote)
                        Text("Read Article \(article.number)")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(Theme.gold)
                }

                controls
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Watch the meeting as it happens")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.navy)
                    Text("A simulated playback of a recent Town Meeting so you can see how a remote session feels.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    Button {
                        session.start()
                    } label: {
                        Label("Play demo session", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Theme.navy, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .card()
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(session.steps) { step in
                Capsule()
                    .fill(step.id <= session.current?.id ?? 0 ? Theme.gold : Theme.divider)
                    .frame(width: step.id == session.current?.id ? 18 : 5, height: 5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.current?.id)
            }
            Spacer()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                session.isRunning ? session.pause() : session.start()
            } label: {
                Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                    .font(.callout)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Theme.navy)
                    .background(Theme.goldSoft.opacity(0.6), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            Button {
                session.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.callout)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Theme.navy)
                    .background(Theme.goldSoft.opacity(0.6), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            Button {
                session.stop()
            } label: {
                Text("End")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
            Spacer()
        }
    }
}

// Mock voting: the user can't vote officially — this is a clearly-labeled
// simulated poll so remote constituents can make their voice feel heard.
struct MockVoteCard: View {
    let article: WarrantArticle
    var votes: MockVoteController

    private var myVote: VoteChoice? { votes.myVote(for: article.id) }
    private var maxCount: Int {
        let base = [article.simulatedTally.yay, article.simulatedTally.nay, article.simulatedTally.abstain ?? 0].max() ?? 0
        let mine = myVote == nil ? 0 : 1
        return base + mine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "How would you vote?")
                Spacer()
                Text("SIMULATED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text(article.displayNumber + ": " + article.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.navy)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(VoteChoice.allCases) { choice in
                    voteButton(choice)
                }
            }

            if let vote = myVote {
                results(vote)
            }
        }
        .padding(16)
        .card()
    }

    private func voteButton(_ choice: VoteChoice) -> some View {
        let selected = myVote == choice
        let color: Color = choice == .yay ? Theme.green : (choice == .nay ? Theme.burgundy : Theme.inkSecondary)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                votes.cast(choice, for: article.id)
            }
        } label: {
            Text(choice.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? color : color.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func results(_ vote: VoteChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.gold)
                Text("You voted \(vote.rawValue.lowercased()) — official voting happens in person at the meeting.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            TallyRow(label: "Yay", count: article.simulatedTally.yay + (vote == .yay ? 1 : 0), maxCount: maxCount, color: Theme.green, highlight: vote == .yay)
            TallyRow(label: "Nay", count: article.simulatedTally.nay + (vote == .nay ? 1 : 0), maxCount: maxCount, color: Theme.burgundy, highlight: vote == .nay)
            TallyRow(label: "Abstain", count: (article.simulatedTally.abstain ?? 0) + (vote == .abstain ? 1 : 0), maxCount: maxCount, color: Theme.inkSecondary, highlight: vote == .abstain)
            Text("Community numbers are simulated demo data.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary.opacity(0.75))
        }
        .transition(.opacity)
    }
}

// Press feedback: the UI answers the finger immediately, commit lands on release.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
