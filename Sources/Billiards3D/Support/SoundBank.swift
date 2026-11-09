import AVFoundation

/// The sound effects, made up at start and mixed as they play, on the default output. Without an output device, there
/// is no sound.
@MainActor
final class SoundBank {
    private let engine = AVAudioEngine()
    private let mixer: SoundMixer
    private var source: AVAudioSourceNode?
    private var observer: NSObjectProtocol?

    var isEnabled = true {
        didSet {
            if !isEnabled {
                mixer.stopAll()
            }
        }
    }

    init() {
        mixer = SoundMixer(samples: SoundEffect.allCases.map { SoundSynth.samples($0) })
        guard let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.rate, channels: 2) else { return }
        let source = Self.makeSource(mixer, format: format)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        self.source = source
        // The engine stops when the output device changes, such as when headphones are plugged in.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.start()
            }
        }
        start()
    }

    /// `volume` 0 to 1, `pan` from -1 (left) to 1 (right), `pitch` as a rate of playback.
    func play(_ effect: SoundEffect, volume: Float = 1, pan: Float = 0, pitch: Float = 1) {
        guard isEnabled, source != nil, volume > 0.001 else { return }
        if !engine.isRunning {
            start()
        }
        guard engine.isRunning else { return }
        mixer.play(effect, volume: volume, pan: pan, pitch: pitch)
    }

    private func start() {
        guard source != nil, !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            FileHandle.standardError.write(Data("3D Billiards: no sound: \(error.localizedDescription)\n".utf8))
        }
    }

    /// The node that asks the mixer for the samples. Made outside the main actor, so that its block, which the audio
    /// thread calls, does not belong to it.
    private nonisolated static func makeSource(_ mixer: SoundMixer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            mixer.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
    }
}
