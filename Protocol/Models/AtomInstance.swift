//
//  AtomInstance.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData

/// The "Daily Task" model for Atoms - represents a specific task for a specific day.
/// Created by cloning an AtomTemplate when a MoleculeInstance is generated.
@Model
final class AtomInstance {
    // MARK: - Properties
    
    /// Unique identifier
    var id: UUID
    
    /// Task title (copied from template)
    var title: String
    
    /// Input type (copied from template)
    var inputType: AtomInputType
    
    /// Whether this task is completed
    var isCompleted: Bool
    
    /// Current progress value for counter/value types
    /// For binary: nil (use isCompleted instead)
    /// For counter: current count (e.g., 3 out of 5)
    /// For value: entered value (e.g., 91.5 kg)
    var currentValue: Double?
    
    /// Target value (copied from template)
    var targetValue: Double?
    
    /// Unit of measurement (copied from template)
    var unit: String?
    
    /// Sort order within the MoleculeInstance
    var order: Int
    
    /// Reference to the source template ID (for tracking)
    var sourceTemplateId: UUID?
    
    /// Completion timestamp
    var completedAt: Date?
    
    /// Creation timestamp
    var createdAt: Date
    
    // MARK: - Workout-Specific Properties
    
    /// Target number of sets (copied from template)
    var targetSets: Int?
    
    /// Target number of reps per set (copied from template)
    var targetReps: Int?
    
    /// Default rest time between sets in seconds
    var defaultRestTime: TimeInterval?
    
    /// User notes for this instance (e.g., "Knee felt weird today")
    var notes: String?
    
    /// URL for instructional video
    var videoURL: String?
    
    /// Whether this instance has been soft-deleted (archived)
    var isArchived: Bool = false
    
    // MARK: - Relationships
    
    /// Belongs to one MoleculeInstance
    var parentMoleculeInstance: MoleculeInstance?
    
    /// One-to-Many relationship with WorkoutSet
    /// When an atom is deleted, all its sets are also deleted
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.parentAtomInstance)
    var sets: [WorkoutSet] = []
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        title: String,
        inputType: AtomInputType = .binary,
        isCompleted: Bool = false,
        currentValue: Double? = nil,
        targetValue: Double? = nil,
        unit: String? = nil,
        order: Int = 0,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        defaultRestTime: TimeInterval? = nil,
        notes: String? = nil,
        videoURL: String? = nil,
        parentMoleculeInstance: MoleculeInstance? = nil,
        sourceTemplateId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.inputType = inputType
        self.isCompleted = isCompleted
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.unit = unit
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.defaultRestTime = defaultRestTime
        self.notes = notes
        self.videoURL = videoURL
        self.parentMoleculeInstance = parentMoleculeInstance
        self.sourceTemplateId = sourceTemplateId
        self.createdAt = createdAt
    }
    
    // MARK: - Computed Properties
    
    /// Progress as a percentage (0.0 to 1.0)
    var progress: Double {
        switch inputType {
        case .binary:
            return isCompleted ? 1.0 : 0.0
            
        case .counter, .value:
            // For workout exercises, use sets progress
            if isWorkoutExercise {
                guard let target = targetSets, target > 0 else { return 0.0 }
                let completed = sets.filter(\.isCompleted).count
                return min(Double(completed) / Double(target), 1.0)
            }
            
            guard let target = targetValue, target > 0 else { return 0.0 }
            let current = currentValue ?? 0
            return min(current / target, 1.0)
        }
    }
    
    /// Display string for current progress
    var progressDisplayString: String {
        switch inputType {
        case .binary:
            return isCompleted ? "Done" : "Not Done"
            
        case .counter:
            let current = Int(currentValue ?? 0)
            let target = Int(targetValue ?? 0)
            return "\(current)/\(target)"
            
        case .value:
            // For workout exercises, show sets progress
            if isWorkoutExercise {
                let completed = sets.filter(\.isCompleted).count
                let target = targetSets ?? 0
                return "\(completed)/\(target) sets"
            }
            
            guard let current = currentValue else { return "—" }
            let formattedValue = current.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", current)
                : String(format: "%.1f", current)
            
            if let unit = unit, !unit.isEmpty {
                return "\(formattedValue) \(unit)"
            }
            return formattedValue
        }
    }
    
    /// Whether this is a workout exercise (has sets/reps)
    var isWorkoutExercise: Bool {
        inputType == .value && (targetSets != nil || targetReps != nil)
    }
    
    /// Display string for workout target (e.g., "4 Sets × 15 Reps")
    var workoutTargetString: String? {
        guard isWorkoutExercise else { return nil }
        
        var parts: [String] = []
        
        if let sets = targetSets {
            parts.append("\(sets) Sets")
        }
        
        if let reps = targetReps {
            parts.append("\(reps) Reps")
        }
        
        if parts.isEmpty { return nil }
        return parts.joined(separator: " × ")
    }
    
    /// Sorted sets by order
    var sortedSets: [WorkoutSet] {
        sets.sorted { $0.order < $1.order }
    }
    
    /// Number of completed sets
    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }
    
    // MARK: - Actions
    
    /// Marks the atom as complete and syncs parent completion status
    func markComplete() {
        isCompleted = true
        completedAt = Date()
        
        // For counter type, set current to target if completing
        if inputType == .counter, let target = targetValue {
            currentValue = target
        }
        
        // Sync parent completion status
        parentMoleculeInstance?.checkAtomCompletionAndSync()
    }
    
    /// Marks the atom as incomplete and syncs parent completion status
    func markIncomplete() {
        isCompleted = false
        completedAt = nil
        
        // Sync parent completion status
        parentMoleculeInstance?.checkAtomCompletionAndSync()
    }
    
    /// Toggles completion status
    func toggleComplete() {
        if isCompleted {
            markIncomplete()
        } else {
            markComplete()
        }
    }
    
    /// Increments counter value by 1 (for counter type)
    func increment() {
        guard inputType == .counter else { return }
        
        let current = currentValue ?? 0
        currentValue = current + 1
        
        // Auto-complete if target reached
        if let target = targetValue, currentValue ?? 0 >= target {
            isCompleted = true
            completedAt = Date()
        }
    }
    
    /// Decrements counter value by 1 (for counter type)
    func decrement() {
        guard inputType == .counter else { return }
        
        let current = currentValue ?? 0
        currentValue = max(0, current - 1)
        
        // Uncomplete if below target
        if let target = targetValue, currentValue ?? 0 < target {
            isCompleted = false
            completedAt = nil
        }
    }
    
    /// Sets the value (for value type)
    func setValue(_ value: Double) {
        guard inputType == .value else { return }
        
        currentValue = value
        
        // Auto-complete when value is entered
        if value > 0 {
            isCompleted = true
            completedAt = Date()
        }
    }
    
    /// Adds a new workout set
    func addSet(weight: Double? = nil, reps: Int? = nil) -> WorkoutSet {
        let nextOrder = (sets.map(\.order).max() ?? 0) + 1
        let newSet = WorkoutSet(
            order: nextOrder,
            weight: weight,
            reps: reps,
            parentAtomInstance: self
        )
        sets.append(newSet)
        return newSet
    }
    
    /// Checks if all target sets are completed and marks atom complete
    func updateCompletionFromSets() {
        guard isWorkoutExercise else { return }
        
        let completedCount = sets.filter(\.isCompleted).count
        let targetCount = targetSets ?? 0
        
        if completedCount >= targetCount && targetCount > 0 {
            isCompleted = true
            completedAt = Date()
        } else {
            isCompleted = false
            completedAt = nil
        }
    }
}

// MARK: - Hashable Conformance
extension AtomInstance: Hashable {
    static func == (lhs: AtomInstance, rhs: AtomInstance) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Comparable (for sorting by order)
extension AtomInstance: Comparable {
    static func < (lhs: AtomInstance, rhs: AtomInstance) -> Bool {
        lhs.order < rhs.order
    }
}
