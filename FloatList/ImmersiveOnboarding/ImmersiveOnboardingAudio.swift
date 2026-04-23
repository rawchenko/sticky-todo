import AVFoundation
import SwiftUI

/// Plays the bundled ambient intro track for the Immersive onboarding
/// "first contact" scene. The track is loaded once at init and then
/// scheduled on demand via `playIntro()`.
@MainActor
final class ImmersiveOnboardingAudio: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var buffer: AVAudioPCMBuffer?
    private var isReady = false

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        buffer = Self.loadBundledAudio(named: "intro", extension: "mp3", format: format)
        prepareEngine()
    }

    private func prepareEngine() {
        guard OnboardingAudioPreferences.isEnabled else { return }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.7
        engine.prepare()
        do {
            try engine.start()
            isReady = true
        } catch {
            // Audio is best-effort for the onboarding scene — if the engine
            // fails to start (sandbox, no output device, etc.), the scene
            // plays silently instead of crashing the first-run experience.
            isReady = false
        }
    }

    func playIntro() {
        guard isReady, OnboardingAudioPreferences.isEnabled, let buffer else { return }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    func stopAll() {
        player.stop()
        if engine.isRunning { engine.stop() }
    }

    deinit {
        // Allowed on deinit even under @MainActor — engine.stop is thread-safe.
        player.stop()
        if engine.isRunning { engine.stop() }
    }

    // MARK: - Bundled audio loading

    /// Loads an audio file from the app bundle, decodes it into a PCM
    /// buffer, and converts it to the engine's working format so it can
    /// be scheduled on the player node without format-mismatch issues.
    /// `gain` attenuates the whole buffer — useful for balancing a
    /// mastered asset against the engine's mixer level.
    private static func loadBundledAudio(
        named name: String,
        extension ext: String,
        format target: AVAudioFormat,
        gain: Float = 0.55
    ) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }

        let sourceFormat = file.processingFormat
        let sourceFrameCount = AVAudioFrameCount(file.length)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: sourceFrameCount
        ) else { return nil }

        do {
            try file.read(into: sourceBuffer)
        } catch {
            return nil
        }

        // If formats already match, skip the converter and just apply gain.
        let output: AVAudioPCMBuffer
        if sourceFormat == target {
            output = sourceBuffer
        } else {
            guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
                return nil
            }
            let ratio = target.sampleRate / sourceFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(sourceFrameCount) * ratio) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputCapacity) else {
                return nil
            }
            // Reference-type flag so the converter's input callback can
            // mutate it without tripping Swift 6 strict-concurrency checks
            // on captured vars in potentially-concurrent closures.
            final class Flag { var value = false }
            let provided = Flag()
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if provided.value {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                provided.value = true
                outStatus.pointee = .haveData
                return sourceBuffer
            }
            var error: NSError?
            let status = converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
            guard status != .error, error == nil else { return nil }
            output = converted
        }

        // Scale the mastered asset down to sit comfortably in the mix.
        if gain != 1.0, let channelData = output.floatChannelData {
            let count = Int(output.frameLength)
            for ch in 0..<Int(target.channelCount) {
                let ptr = channelData[ch]
                for i in 0..<count {
                    ptr[i] *= gain
                }
            }
        }

        return output
    }
}
