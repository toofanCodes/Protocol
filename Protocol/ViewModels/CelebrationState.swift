import SwiftUI

class CelebrationState: ObservableObject {
    /// Counter to trigger confetti bursts. Incrementing this causes the ConfettiView to fire.
    @Published var confettiCounter: Int = 0
    
    /// Theme color for the current celebration (used by ConfettiView)
    @Published var celebrationColor: Color = .accentColor
    
    /// Perfect Day celebration states
    @Published var showPerfectDayBomb: Bool = false
    @Published var showGreetingCard: Bool = false
    
    /// Cooldown tracking to prevent rapid-fire triggers
    private var lastTriggerTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 0.3 // 300ms
    
    /// Check if we're within cooldown period
    private var isInCooldown: Bool {
        Date().timeIntervalSince(lastTriggerTime) < cooldownInterval
    }
    
    // MARK: - Celebration Triggers
    
    /// Trigger celebration for completing a molecule
    /// - Parameter themeColor: The molecule's theme color (optional, defaults to accent)
    /// - Parameter delay: Optional delay in seconds (useful for waiting for sheet dismissal)
    func triggerMoleculeCompletion(themeColor: Color? = nil, delay: Double = 0) {
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.performMoleculeTrigger(themeColor: themeColor)
            }
        } else {
            performMoleculeTrigger(themeColor: themeColor)
        }
    }
    
    private func performMoleculeTrigger(themeColor: Color?) {
        guard !isInCooldown else { return }
        lastTriggerTime = Date()
        
        print("🎉 Triggering molecule celebration!")
        celebrationColor = themeColor ?? .accentColor
        
        // Play Sound
        SoundManager.shared.playSound(.claps)
        
        // Fire Confetti
        DispatchQueue.main.async {
            self.confettiCounter += 1
        }
    }
    
    /// Trigger Perfect Day celebration (all molecules completed for today)
    func triggerPerfectDay() {
        print("🏆 PERFECT DAY! Triggering Color Bomb celebration!")
        
        // Play success chime
        SoundManager.shared.playSound(.successChime)
        
        // Trigger Color Bomb and Greeting Card
        DispatchQueue.main.async {
            self.showPerfectDayBomb = true
            self.showGreetingCard = true
        }
    }
    
    /// Check if all molecules for today are completed and trigger Perfect Day if so
    /// - Parameter todayInstances: All MoleculeInstances scheduled for today
    func checkPerfectDay(todayInstances: [MoleculeInstance], delay: Double = 0) {
        // Must have at least one molecule scheduled
        guard !todayInstances.isEmpty else { return }
        
        // Check if ALL are completed
        let allCompleted = todayInstances.allSatisfy { $0.isCompleted }
        
        if allCompleted {
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.triggerPerfectDay()
                }
            } else {
                triggerPerfectDay()
            }
        }
    }
}

