import Foundation

/// Runs the computer's choice of stroke on a thread of its own; the game polls for the result.
final class ComputerWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Shot?
    private var stop: StopFlag?
    /// Each start and cancel moves it on, so that a late answer to an old question is dropped.
    private var generation = 0

    func start(position: Simulation, match: Match, level: Int, seed: UInt64) {
        let flag = StopFlag()
        lock.lock()
        stop?.raise()
        stop = flag
        result = nil
        generation += 1
        let ticket = generation
        lock.unlock()
        let thread = Thread { [weak self] in
            let shot = ComputerPlayer.choose(position, match: match, level: level, seed: seed, stop: flag)
            self?.deliver(shot, ticket: ticket)
        }
        thread.stackSize = 4 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func cancel() {
        lock.lock()
        stop?.raise()
        stop = nil
        result = nil
        generation += 1
        lock.unlock()
    }

    /// The stroke, once it is chosen; each answer is given once.
    func take() -> Shot? {
        lock.lock()
        defer { lock.unlock() }
        let shot = result
        result = nil
        return shot
    }

    private func deliver(_ shot: Shot, ticket: Int) {
        lock.lock()
        if ticket == generation {
            result = shot
        }
        lock.unlock()
    }
}
