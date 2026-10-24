import Foundation

// Drives the simulated (clearly-labeled) live session: one step every few seconds,
// pausable, restartable, loops through a canned script taken from a real past meeting.
@Observable
final class DemoSessionController {
    private(set) var steps: [DemoStep] = []
    private(set) var stepIndex = 0
    private(set) var isRunning = false
    private var runner: Task<Void, Never>?
    private let stepDuration = Duration.seconds(6)

    var current: DemoStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    var currentArticleID: String? { current?.articleID }

    func configure(with steps: [DemoStep]) {
        self.steps = steps
    }

    func start() {
        stepIndex = 0
        isRunning = true
        runLoop()
    }

    func next() { advance() }

    func pause() {
        isRunning = false
        runner?.cancel()
        runner = nil
    }

    func stop() {
        pause()
        stepIndex = 0
    }

    func restart() { start() }

    private func advance() {
        guard !steps.isEmpty else { return }
        stepIndex = stepIndex + 1 >= steps.count ? 0 : stepIndex + 1
    }

    private func runLoop() {
        runner?.cancel()
        runner = Task {
            while isRunning && !Task.isCancelled {
                try? await Task.sleep(for: stepDuration)
                guard isRunning, !Task.isCancelled else { break }
                advance()
            }
        }
    }
}

// Records the user's mock vote per article. The community tally shown alongside
// is seeded data, clearly labeled "simulated" everywhere it's displayed.
@Observable
final class MockVoteController {
    private(set) var votes: [String: VoteChoice] = [:]

    func cast(_ choice: VoteChoice, for articleID: String) {
        votes[articleID] = choice
    }

    func myVote(for articleID: String) -> VoteChoice? {
        votes[articleID]
    }
}
