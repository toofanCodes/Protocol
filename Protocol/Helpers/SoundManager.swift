//
//  SoundManager.swift
//  Protocol
//
//  Created on 2026-01-04.
//

import Foundation
import AVFoundation
import UIKit

enum SoundType: String, CaseIterable {
    case claps = "claps"           // Molecule completion
    case successChime = "successChime" // Perfect Day
    
    var filename: String {
        return self.rawValue
    }
    
    var fileExtension: String {
        return "wav"
    }
}

class SoundManager: NSObject {
    static let shared = SoundManager()
    
    private var players: [SoundType: AVAudioPlayer] = [:]
    
    // MARK: - User Settings Keys
    private let soundEnabledKey = "celebrationSoundEnabled"
    private let volumeKey = "celebrationVolume"
    private let hapticEnabledKey = "celebrationHapticEnabled"
    
    /// Whether sound effects are enabled (default: true)
    var isSoundEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: soundEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: soundEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: soundEnabledKey)
        }
    }
    
    /// Volume level 0.0 - 1.0 (default: 0.7)
    var volume: Float {
        get {
            let stored = UserDefaults.standard.float(forKey: volumeKey)
            return stored == 0 && UserDefaults.standard.object(forKey: volumeKey) == nil ? 0.7 : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: volumeKey)
        }
    }
    
    /// Whether haptic feedback is enabled (default: true)
    var isHapticEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: hapticEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: hapticEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hapticEnabledKey)
        }
    }
    
    private override init() {
        super.init()
        configureAudioSession()
        preloadSounds()
    }
    
    private func configureAudioSession() {
        // Use playback category to play sound even in Silent Mode
        // .mixWithOthers allows music to keep playing
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func preloadSounds() {
        for type in SoundType.allCases {
            guard let url = Bundle.main.url(forResource: type.filename, withExtension: type.fileExtension) else {
                print("Sound file not found: \(type.filename).\(type.fileExtension)")
                continue
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[type] = player
            } catch {
                print("Failed to load sound \(type): \(error)")
            }
        }
    }
    
    func playSound(_ type: SoundType) {
        // Check if sound is enabled
        guard isSoundEnabled else {
            // Still provide haptic if enabled
            if isHapticEnabled {
                triggerHaptic(for: type)
            }
            return
        }
        
        // Stop any existing player to prevent overlap
        if let existingPlayer = players[type], existingPlayer.isPlaying {
            existingPlayer.stop()
            existingPlayer.currentTime = 0
        }
        
        // Get or Create Player
        guard let player = players[type] ?? createPlayer(for: type) else { return }
        
        // Play
        player.volume = volume
        player.play()
        players[type] = player
        
        // Trigger haptic feedback
        if isHapticEnabled {
            triggerHaptic(for: type)
        }
        
        // Enforce 5s limit
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self, weak player] in
            // Only stop if this specific player is still playing (avoids cutting off next sound if spamming)
            if let p = player, p.isPlaying {
                p.setVolume(0, fadeDuration: 0.5)
                // Stop completely after fade
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    p.stop()
                    p.currentTime = 0
                    p.volume = self?.volume ?? 0.7
                }
            }
        }
    }
    
    private func createPlayer(for type: SoundType) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: type.filename, withExtension: type.fileExtension) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }
    
    private func triggerHaptic(for type: SoundType) {
        switch type {
        case .claps:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .successChime:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            // Double haptic for milestone
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                generator.notificationOccurred(.success)
            }
        }
    }
}
