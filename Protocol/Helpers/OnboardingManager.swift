//
//  OnboardingManager.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData

/// Manages first-launch onboarding and database seeding
@MainActor
final class OnboardingManager {
    
    // MARK: - UserDefaults Keys
    
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    
    // MARK: - Properties
    
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Checks if this is the first launch and seeds data if needed
    func seedDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey) else {
            return
        }
        
        seedAllProtocols()
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
    }
    
    /// Force re-seeds the database (for testing/development)
    func forceSeedData() {
        seedAllProtocols()
    }
    
    /// Resets onboarding state (will seed again on next launch)
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
    }
    
    // MARK: - Private Seeding Methods
    
    private func seedAllProtocols() {
        seedSkincareProtocol()
        seedWorkoutProtocol()
        seedMedicalProtocol()
        
        try? modelContext.save()
    }
    
    // MARK: - Skincare Protocol
    
    private func seedSkincareProtocol() {
        // Morning Routine - 8:00 AM Daily
        let morningTime = createTime(hour: 8, minute: 0)
        let morningRoutine = MoleculeTemplate(
            title: "Morning Routine",
            baseTime: morningTime,
            recurrenceFreq: .daily,
            notes: "Skincare Protocol - AM"
        )
        modelContext.insert(morningRoutine)
        
        addAtom(to: morningRoutine, title: "Cleanse (10s Short Contact)", inputType: .binary, order: 0)
        addAtom(to: morningRoutine, title: "Azelaic Acid (Apply to damp skin)", inputType: .binary, order: 1)
        addAtom(to: morningRoutine, title: "Spot Repair (Madeca on flaky spots)", inputType: .binary, order: 2)
        addAtom(to: morningRoutine, title: "SPF 60+", inputType: .binary, order: 3)
        addAtom(to: morningRoutine, title: "Log Resting Heart Rate", inputType: .value, targetValue: 65, unit: "BPM", order: 4)
        
        // Evening Routine - 9:00 PM Daily
        let eveningTime = createTime(hour: 21, minute: 0)
        let eveningRoutine = MoleculeTemplate(
            title: "Evening Routine",
            baseTime: eveningTime,
            recurrenceFreq: .daily,
            notes: "Skincare Protocol - PM"
        )
        modelContext.insert(eveningRoutine)
        
        addAtom(to: eveningRoutine, title: "Cleanse", inputType: .binary, order: 0)
        addAtom(to: eveningRoutine, title: "Vaseline Shield (Nose/Lips)", inputType: .binary, order: 1)
        addAtom(to: eveningRoutine, title: "Pimple Patches (If needed)", inputType: .binary, order: 2)
        addAtom(to: eveningRoutine, title: "Buffer Layer (Madeca)", inputType: .binary, order: 3)
        addAtom(to: eveningRoutine, title: "Active Layer (Differin)", inputType: .binary, order: 4)
        addAtom(to: eveningRoutine, title: "Seal Layer (Vanicream)", inputType: .binary, order: 5)
        
        // Sunday Peel Protocol (Unscheduled, manual swap)
        let peelProtocol = MoleculeTemplate(
            title: "Sunday Peel Protocol",
            baseTime: eveningTime,
            recurrenceFreq: .weekly, // Changed to weekly (Sunday) but disabled via end rule
            recurrenceDays: [0], // Sunday
            endRuleType: .afterOccurrences, // Prevent generation by default
            endRuleCount: 0, // 0 occurrences = unscheduled
            notes: "Weekly Acid Exfoliation"
        )
        // Note: We insert it but don't generate instances automatically unless frequency set. 
        // User requested: "do not schedule it, just save it". 
        // We set freq to something but days empty so it generates nothing? 
        // Or just don't call generateInstances in seed.
        
        modelContext.insert(peelProtocol)
        
        addAtom(to: peelProtocol, title: "Cleanse", inputType: .binary, order: 0)
        addAtom(to: peelProtocol, title: "Vaseline Shield", inputType: .binary, order: 1)
        addAtom(to: peelProtocol, title: "Pimple Patches", inputType: .binary, order: 2)
        addAtom(to: peelProtocol, title: "Glycolic Acid (The Peel)", inputType: .binary, order: 3)
        addAtom(to: peelProtocol, title: "Heavy Moisturize", inputType: .binary, order: 4)
    }
    
    // MARK: - Workout Protocol
    
    private func seedWorkoutProtocol() {
        // Metabolic Lift - Monday (1) and Friday (5)
        // 45 second rest for metabolic days
        let metabolicRestTime: TimeInterval = 45
        
        let workoutTime = createTime(hour: 7, minute: 0)
        let metabolicLift = MoleculeTemplate(
            title: "Metabolic Lift",
            baseTime: workoutTime,
            recurrenceFreq: .custom,
            recurrenceDays: [1, 5], // Monday, Friday
            notes: "Zone 3 Heart Rate • Compound movements • Minimal rest"
        )
        modelContext.insert(metabolicLift)
        
        // Metabolic exercises - 4 sets × 15 reps with 45s rest
        addWorkoutAtom(to: metabolicLift, title: "DB Goblet Squats", targetValue: 30, unit: "lbs", 
                       targetSets: 4, targetReps: 15, restTime: metabolicRestTime, order: 0)
        addWorkoutAtom(to: metabolicLift, title: "KB Swings", targetValue: 25, unit: "lbs", 
                       targetSets: 4, targetReps: 15, restTime: metabolicRestTime, order: 1)
        addWorkoutAtom(to: metabolicLift, title: "DB Thrusters", targetValue: nil, unit: "lbs", 
                       targetSets: 4, targetReps: 12, restTime: metabolicRestTime, order: 2)
        addWorkoutAtom(to: metabolicLift, title: "Cable Rows", targetValue: nil, unit: "lbs", 
                       targetSets: 4, targetReps: 15, restTime: metabolicRestTime, order: 3)
        addAtom(to: metabolicLift, title: "Smith Pushups", inputType: .binary, order: 4)
        addAtom(to: metabolicLift, title: "Plank (45s)", inputType: .binary, order: 5)
        addAtom(to: metabolicLift, title: "Stairmaster Finisher (15 mins)", inputType: .binary, order: 6)
        
        // Structural Lift - Tuesday (2) and Thursday (4)
        // 90 second rest for structural/strength days
        let structuralRestTime: TimeInterval = 90
        
        let structuralLift = MoleculeTemplate(
            title: "Structural Lift",
            baseTime: workoutTime,
            recurrenceFreq: .custom,
            recurrenceDays: [2, 4], // Tuesday, Thursday
            notes: "Strength focus • Machine-based • Controlled tempo"
        )
        modelContext.insert(structuralLift)
        
        // Structural exercises - 4 sets × 10-12 reps with 90s rest
        addWorkoutAtom(to: structuralLift, title: "Leg Press", targetValue: 180, unit: "lbs", 
                       targetSets: 4, targetReps: 12, restTime: structuralRestTime, order: 0)
        addWorkoutAtom(to: structuralLift, title: "Chest Press", targetValue: nil, unit: "lbs", 
                       targetSets: 4, targetReps: 10, restTime: structuralRestTime, order: 1)
        addWorkoutAtom(to: structuralLift, title: "Lat Pulldowns", targetValue: nil, unit: "lbs", 
                       targetSets: 4, targetReps: 12, restTime: structuralRestTime, order: 2)
        addWorkoutAtom(to: structuralLift, title: "Shoulder Press", targetValue: nil, unit: "lbs", 
                       targetSets: 4, targetReps: 10, restTime: structuralRestTime, order: 3)
        addWorkoutAtom(to: structuralLift, title: "Lateral Raises", targetValue: nil, unit: "lbs", 
                       targetSets: 3, targetReps: 15, restTime: 60, order: 4)
        addWorkoutAtom(to: structuralLift, title: "Face Pulls", targetValue: nil, unit: "lbs", 
                       targetSets: 3, targetReps: 15, restTime: 60, order: 5)
        addAtom(to: structuralLift, title: "Stairmaster Finisher (15 mins)", inputType: .binary, order: 6)
    }
    
    // MARK: - Medical Protocol
    
    private func seedMedicalProtocol() {
        // Thyroid Management - Morning Daily
        let medicationTime = createTime(hour: 6, minute: 30)
        let thyroidManagement = MoleculeTemplate(
            title: "Thyroid Management",
            baseTime: medicationTime,
            recurrenceFreq: .daily,
            notes: "Take on empty stomach • Wait before food/coffee"
        )
        modelContext.insert(thyroidManagement)
        
        addAtom(to: thyroidManagement, title: "Take Medication (Empty Stomach)", inputType: .binary, order: 0)
        addAtom(to: thyroidManagement, title: "Wait 30 Mins (Before food/coffee)", inputType: .counter, targetValue: 30, order: 1)
    }
    
    // MARK: - Helper Methods
    
    private func createTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
    
    private func addAtom(
        to template: MoleculeTemplate,
        title: String,
        inputType: AtomInputType,
        targetValue: Double? = nil,
        unit: String? = nil,
        order: Int
    ) {
        let atom = AtomTemplate(
            title: title,
            inputType: inputType,
            targetValue: targetValue,
            unit: unit,
            order: order,
            parentMoleculeTemplate: template
        )
        modelContext.insert(atom)
        template.atomTemplates.append(atom)
    }
    
    /// Adds a workout exercise atom with sets, reps, and rest time
    private func addWorkoutAtom(
        to template: MoleculeTemplate,
        title: String,
        targetValue: Double?,
        unit: String,
        targetSets: Int,
        targetReps: Int,
        restTime: TimeInterval,
        order: Int
    ) {
        let atom = AtomTemplate(
            title: title,
            inputType: .value,
            targetValue: targetValue,
            unit: unit,
            order: order,
            targetSets: targetSets,
            targetReps: targetReps,
            defaultRestTime: restTime,
            parentMoleculeTemplate: template
        )
        modelContext.insert(atom)
        template.atomTemplates.append(atom)
    }
}

// MARK: - Preview Helper

extension OnboardingManager {
    /// Creates a pre-seeded model container for previews
    static func createPreviewContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MoleculeTemplate.self, MoleculeInstance.self, AtomTemplate.self, AtomInstance.self, WorkoutSet.self,
            configurations: config
        )
        
        let manager = OnboardingManager(modelContext: container.mainContext)
        manager.forceSeedData()
        
        return container
    }
}
