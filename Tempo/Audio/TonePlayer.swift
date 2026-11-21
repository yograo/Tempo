import AVFoundation
import UIKit

@MainActor
final class TonePlayer {
    private var players: [String: AVAudioPlayer] = [:]
    private(set) var unavailable = false

    func prepare() {
        unavailable = false
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            for name in ["countdown", "transition", "complete"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                    unavailable = true
                    continue
                }
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[name] = player
            }
        } catch {
            unavailable = true
        }
    }

    func play(_ event: WorkoutTimeline.Event) {
        let name: String
        switch event {
        case .countdown: name = "countdown"
        case .stepStarted: name = "transition"
        case .completed: name = "complete"
        }
        stop()
        players[name]?.currentTime = 0
        if players[name]?.play() != true { unavailable = true }
    }

    func stop() { players.values.forEach { $0.stop() } }

    func releaseSession() {
        stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
