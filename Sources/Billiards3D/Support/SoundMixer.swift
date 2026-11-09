import Foundation

/// The sounds playing, mixed for the output: the game adds voices on the main thread, the audio thread mixes them,
/// each at its own volume, pan and rate, so that many can sound at once.
final class SoundMixer: @unchecked Sendable {
    private struct Voice {
        var effect: Int
        var position = 0.0
        var rate = 1.0
        var left: Float = 1
        var right: Float = 1
    }

    private static let maxVoices = 40

    private let samples: [[Float]]
    private let lock = NSLock()
    private var voices: [Voice] = []

    init(samples: [[Float]]) {
        self.samples = samples
        voices.reserveCapacity(Self.maxVoices)
    }

    /// `volume` 0 to 1, `pan` from -1 (left) to 1 (right), `pitch` as a rate of playback.
    func play(_ effect: SoundEffect, volume: Float, pan: Float, pitch: Float) {
        let pan = min(max(pan, -1), 1)
        let voice = Voice(effect: effect.rawValue, rate: Double(min(max(pitch, 0.25), 4)), left: volume * min(1, 1 - pan),
                          right: volume * min(1, 1 + pan))
        lock.lock()
        if voices.count >= Self.maxVoices {
            voices.removeFirst()
        }
        voices.append(voice)
        lock.unlock()
    }

    func stopAll() {
        lock.lock()
        voices.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// Fills the two channels with `frames` samples of the mix.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
        lock.lock()
        for index in voices.indices {
            let source = samples[voices[index].effect]
            var voice = voices[index]
            for frame in 0..<frames {
                let at = Int(voice.position)
                if at + 1 >= source.count {
                    voice.position = Double(source.count)
                    break
                }
                let fraction = Float(voice.position - Double(at))
                let sample = source[at] + (source[at + 1] - source[at]) * fraction
                left[frame] += sample * voice.left
                right[frame] += sample * voice.right
                voice.position += voice.rate
            }
            voices[index] = voice
        }
        voices.removeAll { $0.position + 1 >= Double(samples[$0.effect].count) }
        lock.unlock()
        // A gentle limit, so that a crowd of clicks at the break does not crackle.
        for frame in 0..<frames {
            left[frame] = Self.limited(left[frame])
            right[frame] = Self.limited(right[frame])
        }
    }

    private static func limited(_ x: Float) -> Float {
        min(max(x / (1 + abs(x) * 0.35), -1), 1) * (30_000 / 32_768)
    }
}
