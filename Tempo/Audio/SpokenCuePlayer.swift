import AVFoundation
import CryptoKit

@MainActor
final class SpokenCuePlayer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

/// Notification sounds are played by iOS, so speech doesn't depend on background execution.
@MainActor
final class SpokenCueFiles {
    private let synthesizer = AVSpeechSynthesizer()
    private let directory: URL

    init() {
        directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds")
    }

    func prepare(_ phrases: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for phrase in Set(phrases).sorted() {
            guard !Task.isCancelled else { break }
            let digest = SHA256.hash(data: Data(("v1-en-US-" + phrase).utf8)).map { String(format: "%02x", $0) }.joined()
            let name = "tempo-\(digest).caf"
            let url = directory.appendingPathComponent(name)
            let ready: Bool
            if FileManager.default.fileExists(atPath: url.path) { ready = true }
            else { ready = await render(phrase, to: url) }
            if ready {
                result[phrase] = name
            }
        }
        // Bound the cache; never remove files used by this workout's pending alerts.
        let used = Set(result.values)
        let cached = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let old = cached.filter { $0.lastPathComponent.hasPrefix("tempo-") && !used.contains($0.lastPathComponent) }
        if old.count > 128 {
            for url in old { try? FileManager.default.removeItem(at: url) }
        }
        return result
    }

    private func render(_ text: String, to url: URL) async -> Bool {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return await withCheckedContinuation { continuation in
            let writer = SpeechFileWriter(url: url, continuation: continuation)
            synthesizer.write(utterance) { buffer in writer.append(buffer) }
            Task { [synthesizer] in
                try? await Task.sleep(for: .seconds(5))
                if writer.timeout() { synthesizer.stopSpeaking(at: .immediate) }
            }
        }
    }
}

/// AVSpeechSynthesizer invokes its buffer callback on a private queue.
private final class SpeechFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let temporaryURL: URL
    private var file: AVAudioFile?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var frames: AVAudioFramePosition = 0
    private var failed = false

    init(url: URL, continuation: CheckedContinuation<Bool, Never>) {
        self.url = url
        self.temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".tempo-\(UUID()).caf")
        self.continuation = continuation
    }

    func append(_ buffer: AVAudioBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard continuation != nil else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            finish(!failed && frames > 0)
            return
        }
        do {
            if file == nil {
                var settings = pcm.format.settings
                settings[AVLinearPCMBitDepthKey] = 16
                settings[AVLinearPCMIsFloatKey] = false
                file = try AVAudioFile(forWriting: temporaryURL, settings: settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            frames += AVAudioFramePosition(pcm.frameLength)
            // iOS requires custom notification sounds to be shorter than 30 seconds.
            guard Double(frames) / pcm.format.sampleRate < 29 else { failed = true; return }
            try file?.write(from: pcm)
        } catch { failed = true }
    }

    func timeout() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard continuation != nil else { return false }
        finish(false)
        return true
    }

    private func finish(_ success: Bool) {
        file = nil
        var saved = success
        if saved {
            do { try FileManager.default.moveItem(at: temporaryURL, to: url) }
            catch { saved = false }
        }
        if !saved { try? FileManager.default.removeItem(at: temporaryURL) }
        let callback = continuation
        continuation = nil
        callback?.resume(returning: saved)
    }
}
