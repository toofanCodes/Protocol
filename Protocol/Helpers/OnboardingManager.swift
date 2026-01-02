//
//  OnboardingManager.swift
//  Protocol
//
//  Created on 2025-12-29.
//  Updated for V1.0 with generic sample data
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
        
        seedSampleProtocols()
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
    }
    
    /// Force re-seeds the database (for testing/development)
    func forceSeedData() {
        seedSampleProtocols()
    }
    
    /// Resets onboarding state (will seed again on next launch)
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
    }
    
    // MARK: - Sample Data Seeding
    
    private func seedSampleProtocols() {
        seedMorningProtocol()
        seedEveningProtocol()
        seedFitnessProtocol()
        seedLearningProtocol()
        
        // Generate instances for the next 30 days
        generateInitialInstances()
        
        try? modelContext.save()
    }
    
    // MARK: - Morning Protocol
    
    private func seedMorningProtocol() {
        let morningTime = createTime(hour: 7, minute: 0)
        let template = MoleculeTemplate(
            title: "Morning Routine",
            baseTime: morningTime,
            recurrenceFreq: .daily,
            notes: "Start your day with intention",
            compound: "Wellness",
            alertOffsets: [0, 15]
        )
        modelContext.insert(template)
        
        addAtom(to: template, title: "Hydrate (Glass of Water)", inputType: .binary, order: 0)
        addAtom(to: template, title: "5-Minute Stretch", inputType: .binary, order: 1)
        addAtom(to: template, title: "Journal (3 Gratitudes)", inputType: .binary, order: 2)
        addAtom(to: template, title: "Review Today's Goals", inputType: .binary, order: 3)
    }
    
    // MARK: - Evening Protocol
    
    private func seedEveningProtocol() {
        let eveningTime = createTime(hour: 21, minute: 0)
        let template = MoleculeTemplate(
            title: "Evening Wind-Down",
            baseTime: eveningTime,
            recurrenceFreq: .daily,
            notes: "Prepare for restful sleep",
            compound: "Wellness",
            alertOffsets: [15]
        )
        modelContext.insert(template)
        
        addAtom(to: template, title: "No Screens (1 hour before bed)", inputType: .binary, order: 0)
        addAtom(to: template, title: "Light Reading", inputType: .binary, order: 1)
        addAtom(to: template, title: "Prepare Tomorrow's Clothes", inputType: .binary, order: 2)
        addAtom(to: template, title: "Sleep Tracker", inputType: .value, targetValue: 8, unit: "hours", order: 3)
    }
    
    // MARK: - Fitness Protocol
    
    private func seedFitnessProtocol() {
        let workoutTime = createTime(hour: 6, minute: 30)
        let template = MoleculeTemplate(
            title: "Workout Session",
            baseTime: workoutTime,
            recurrenceFreq: .custom,
            recurrenceDays: [1, 3, 5], // Monday, Wednesday, Friday
            notes: "Stay consistent, get stronger",
            compound: "Fitness",
            alertOffsets: [30, 60]
        )
        modelContext.insert(template)
        
        // Sample workout with sets/reps
        addWorkoutAtom(to: template, title: "Push-ups", targetValue: nil, unit: "reps",
                       targetSets: 3, targetReps: 15, restTime: 60, order: 0)
        addWorkoutAtom(to: template, title: "Squats", targetValue: nil, unit: "reps",
                       targetSets: 3, targetReps: 20, restTime: 60, order: 1)
        addWorkoutAtom(to: template, title: "Plank", targetValue: nil, unit: "seconds",
                       targetSets: 3, targetReps: 45, restTime: 30, order: 2)
        addAtom(to: template, title: "Cool-down Stretch", inputType: .binary, order: 3)
        addAtom(to: template, title: "Log Workout Notes", inputType: .binary, order: 4)
    }
    
    // MARK: - Learning Protocol
    
    private func seedLearningProtocol() {
        let studyTime = createTime(hour: 19, minute: 0)
        let template = MoleculeTemplate(
            title: "Daily Learning",
            baseTime: studyTime,
            recurrenceFreq: .daily,
            notes: "Invest in yourself every day",
            compound: "Growth",
            alertOffsets: [15]
        )
        modelContext.insert(template)
        
        addAtom(to: template, title: "Read (20 pages)", inputType: .counter, targetValue: 20, order: 0)
        addAtom(to: template, title: "Practice New Skill (30 min)", inputType: .binary, order: 1)
        addAtom(to: template, title: "Write Key Takeaways", inputType: .binary, order: 2)
    }
    
    // MARK: - Instance Generation
    
    private func generateInitialInstances() {
        let descriptor = FetchDescriptor<MoleculeTemplate>()
        guard let templates = try? modelContext.fetch(descriptor) else { return }
        
        let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        
        for template in templates {
            let instances = template.generateInstances(until: targetDate, in: modelContext)
            for instance in instances {
                modelContext.insert(instance)
            }
        }
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
