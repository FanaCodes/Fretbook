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

    /// Plays one pitch briefly, e.g. when a note is entered or dragged.
    func preview(midi: Int) {
        guard !isPlaying, startEngine() else { return }
        let note = UInt8(clamping: midi)
        sampler.startNote(note, withVelocity: 80, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.sampler.stopNote(note, onChannel: 0)
        }
    }

    func play(_ melody: Melody, from startIndex: Int = 0) {
        stop()
        guard startEngine(), !melody.notes.isEmpty else { return }
        let secondsPerQuarter = 60.0 / Double(max(20, melody.tempo))
        let pitches = melody.pitches
        let notes = melody.notes

        // Tied notes sound as one long note.
        var events: [(id: UUID, midi: Int?, seconds: Double)] = []
        var index = min(max(0, startIndex), notes.count)
        while index < notes.count {
            let note = notes[index]
            var quarters = note.quarters
            var last = index
            while !notes[last].isRest && notes[last].tie && last + 1 < notes.count && !notes[last + 1].isRest {
                last += 1
                quarters += notes[last].quarters
            }
            events.append((note.id, note.isRest ? nil : pitches[note.id], quarters * secondsPerQuarter))
            index = last + 1
        }
        isPlaying = true
        let schedule = events

        task = Task { @MainActor [weak self] in
            for event in schedule {
                guard let self, !Task.isCancelled else { return }
                self.playing = event.id
                if let midi = event.midi {
                    let note = UInt8(clamping: midi)
                    self.sampler.startNote(note, withVelocity: 90, onChannel: 0)
                    try? await Task.sleep(nanoseconds: UInt64(event.seconds * 0.92 * 1_000_000_000))
                    self.sampler.stopNote(note, onChannel: 0)
                    try? await Task.sleep(nanoseconds: UInt64(event.seconds * 0.08 * 1_000_000_000))
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(event.seconds * 1_000_000_000))
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
