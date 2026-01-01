//
//  WorkoutSet.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData

/// Represents a single set within a workout exercise
/// Each AtomInstance (of type .value for workouts) can have multiple WorkoutSets
@Model
final class WorkoutSet {
    // MARK: - Properties
    
    /// Unique identifier
    var id: UUID
    
    /// Set number (1, 2, 3...)
    var order: Int
    
    /// Weight used for this set (optional, in user's preferred unit)
    var weight: Double?
    
    /// Number of reps completed
    var reps: Int?
    
    /// Duration of the set (for timed exercises or tracking work time)
    var duration: TimeInterval?
    
    /// Rest duration after this set
    var restDuration: TimeInterval?
    
    /// Whether this set has been completed
    var isCompleted: Bool
    
    /// Timestamp when the set was completed
    var completedAt: Date?
    
    /// Creation timestamp
    var createdAt: Date
    
    // MARK: - Relationships
    
    /// Belongs to one AtomInstance
    var parentAtomInstance: AtomInstance?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        order: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        duration: TimeInterval? = nil,
        restDuration: TimeInterval? = nil,
        isCompleted: Bool = false,
        parentAtomInstance: AtomInstance? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.order = order
        self.weight = weight
        self.reps = reps
        self.duration = duration
        self.restDuration = restDuration
        self.isCompleted = isCompleted
        self.parentAtomInstance = parentAtomInstance
        self.createdAt = createdAt
    }
    
    // MARK: - Computed Properties
    
    /// Display string for the set (e.g., "30 lbs × 12 reps")
    var displayString: String {
        var parts: [String] = []
        
        if let weight = weight {
            parts.append("\(Int(weight)) lbs")
        }
        
        if let reps = reps {
            parts.append("\(reps) reps")
        }
        
        if parts.isEmpty {
            return "Set \(order)"
        }
        
        return parts.joined(separator: " × ")
    }
    
    /// Formatted duration string
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
    
    // MARK: - Actions
    
    /// Marks the set as complete
    func complete() {
        isCompleted = true
        completedAt = Date()
    }
}

// MARK: - Hashable & Comparable

extension WorkoutSet: Hashable {
    static func == (lhs: WorkoutSet, rhs: WorkoutSet) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension WorkoutSet: Comparable {
    static func < (lhs: WorkoutSet, rhs: WorkoutSet) -> Bool {
        lhs.order < rhs.order
    }
}
