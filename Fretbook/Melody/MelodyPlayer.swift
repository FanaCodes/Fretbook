import AVFoundation
import SwiftUI

/// Plays a melody with the built-in sampler sound and reports which note is sounding.
final class MelodyPlayer: ObservableObject {
    @Published private(set) var playing: UUID?
    @Published private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var task: Task<Void, Never>?

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    private func startEngine() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            return true
        } catch {
            print("Audio failed: \(error)")
            return false
        }
    }

    /// Plays one note briefly, e.g. when it's entered.
    func preview(_ note: MelodyNote, keySignature: Int) {
        guard !note.isRest, !isPlaying, startEngine() else { return }
        let midi = UInt8(clamping: note.midi(keySignature: keySignature))
        sampler.startNote(midi, withVelocity: 80, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.sampler.stopNote(midi, onChannel: 0)
        }
    }

    func play(_ melody: Melody, from startIndex: Int = 0) {
        stop()
        guard startEngine(), !melody.notes.isEmpty else { return }
        let notes = Array(melody.notes.dropFirst(min(startIndex, melody.notes.count)))
        let secondsPerQuarter = 60.0 / Double(max(20, melody.tempo))
        let key = melody.keySignature
        isPlaying = true

        task = Task { @MainActor [weak self] in
            for note in notes {
                guard let self, !Task.isCancelled else { return }
                self.playing = note.id
                let length = note.quarters * secondsPerQuarter
                if note.isRest {
                    try? await Task.sleep(nanoseconds: UInt64(length * 1_000_000_000))
                } else {
                    let midi = UInt8(clamping: note.midi(keySignature: key))
                    self.sampler.startNote(midi, withVelocity: 90, onChannel: 0)
                    try? await Task.sleep(nanoseconds: UInt64(length * 0.9 * 1_000_000_000))
                    self.sampler.stopNote(midi, onChannel: 0)
                    try? await Task.sleep(nanoseconds: UInt64(length * 0.1 * 1_000_000_000))
                }
            }
            self?.playing = nil
            self?.isPlaying = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        for midi in 0..<128 {
            sampler.stopNote(UInt8(midi), onChannel: 0)
        }
        playing = nil
        isPlaying = false
    }
}
