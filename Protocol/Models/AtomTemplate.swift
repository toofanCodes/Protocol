//
//  AtomTemplate.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData
import SwiftUI

/// The "Blueprint" model for Atoms - defines the default task structure.
/// When a MoleculeInstance is created, AtomTemplates are cloned into AtomInstances.
@Model
final class AtomTemplate {
    // MARK: - Properties
    
    /// Unique identifier
    var id: UUID
    
    /// Whether the atom is archived (soft deleted)
    var isArchived: Bool = false
    
    /// Task title (e.g., "Drink Water")
    var title: String
    
    /// Input type determines how user interacts with this task
    var inputType: AtomInputType
    
    /// Target value for counter/value types (e.g., 5 for "5 glasses of water")
    /// Nil for binary type
    var targetValue: Double?
    
    /// Unit of measurement (e.g., "ml", "kg", "mins", "lbs")
    /// Nil for binary type
    var unit: String?
    
    /// Sort order within the MoleculeTemplate
    var order: Int
    
    // MARK: - Workout-Specific Properties
    
    /// Target number of sets (for workout exercises)
    var targetSets: Int?
    
    /// Target number of reps per set (for workout exercises)
    var targetReps: Int?
    
    /// Default rest time between sets in seconds (e.g., 45 for Metabolic, 90 for Structural)
    var defaultRestTime: TimeInterval?
    
    /// URL for instructional video
    var videoURL: String?
    
    /// Creation timestamp
    var createdAt: Date
    
    // MARK: - Icon Properties
    
    /// Custom icon symbol (1-2 chars/emoji). Nil = use first letter of title
    var iconSymbol: String?
    
    /// Icon frame shape (stored as raw value for SwiftData compatibility)
    var iconFrameRaw: String = "circle"
    
    /// Computed accessor for iconFrame enum (not persisted)
    @Transient var iconFrame: IconFrameStyle {
        get { IconFrameStyle(rawValue: iconFrameRaw) ?? .circle }
        set { iconFrameRaw = newValue.rawValue }
    }
    
    /// Theme color stored as hex string (e.g., "#007AFF")
    var themeColorHex: String = "#007AFF"
    
    /// Computed accessor for theme color (not persisted)
    @Transient var themeColor: Color {
        get { Color(hex: themeColorHex) }
        set { themeColorHex = newValue.toHex() }
    }
    
    // MARK: - Relationships
    
    /// Belongs to one MoleculeTemplate
    var parentMoleculeTemplate: MoleculeTemplate?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        title: String,
        inputType: AtomInputType = .binary,
        targetValue: Double? = nil,
        unit: String? = nil,
        order: Int = 0,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        defaultRestTime: TimeInterval? = nil,
        videoURL: String? = nil,
        parentMoleculeTemplate: MoleculeTemplate? = nil,
        createdAt: Date = Date(),
        iconSymbol: String? = nil,
        iconFrame: IconFrameStyle = .circle
    ) {
        self.id = id
        self.title = title
        self.inputType = inputType
        self.targetValue = targetValue
        self.unit = unit
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.defaultRestTime = defaultRestTime
        self.videoURL = videoURL
        self.parentMoleculeTemplate = parentMoleculeTemplate
        self.createdAt = createdAt
        self.iconSymbol = iconSymbol
        self.iconFrameRaw = iconFrame.rawValue
    }
    
    // MARK: - Computed Properties
    
    /// Display string for target (e.g., "5 glasses" or "91 kg")
    var targetDisplayString: String? {
        guard let target = targetValue else { return nil }
        
        let formattedTarget = target.truncatingRemainder(dividingBy: 1) == 0 
            ? String(format: "%.0f", target) 
            : String(format: "%.1f", target)
        
        if let unit = unit, !unit.isEmpty {
            return "\(formattedTarget) \(unit)"
        }
        return formattedTarget
    }
    
    /// Display string for workout target (e.g., "4 Sets × 15 Reps")
    var workoutTargetString: String? {
        guard inputType == .value else { return nil }
        
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
    
    /// Formatted rest time string
    var restTimeString: String? {
        guard let rest = defaultRestTime else { return nil }
        let seconds = Int(rest)
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s rest"
        }
        return "\(seconds)s rest"
    }
    
    /// Whether this is a workout exercise (has sets/reps)
    var isWorkoutExercise: Bool {
        inputType == .value && (targetSets != nil || targetReps != nil)
    }
    
    // MARK: - Validation
    
    /// Checks if an atom with the given title already exists in the same parent molecule
    /// - Parameters:
    ///   - title: The title to check
    ///   - parentTemplate: The parent MoleculeTemplate to check within
    ///   - excludingId: Optional ID to exclude (for editing existing atom)
    /// - Returns: true if an atom with this title exists in the same parent
    static func titleExistsInParent(_ title: String, parent: MoleculeTemplate, excludingId: UUID? = nil) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        return parent.atomTemplates.contains { atom in
            let existingTitle = atom.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isSameTitle = existingTitle == normalizedTitle
            let isNotExcluded = excludingId == nil || atom.id != excludingId
            return isSameTitle && isNotExcluded
        }
    }
    
    // MARK: - Clone Method
    
    /// Creates an AtomInstance from this template
    /// - Parameter parentInstance: The MoleculeInstance this atom belongs to
    /// - Returns: A new AtomInstance with values copied from this template
    func createInstance(for parentInstance: MoleculeInstance) -> AtomInstance {
        return AtomInstance(
            title: self.title,
            inputType: self.inputType,
            targetValue: self.targetValue,
            unit: self.unit,
            order: self.order,
            targetSets: self.targetSets,
            targetReps: self.targetReps,
            defaultRestTime: self.defaultRestTime,
            videoURL: self.videoURL,
            parentMoleculeInstance: parentInstance,
            sourceTemplateId: self.id
        )
    }
}

// MARK: - Hashable Conformance
extension AtomTemplate: Hashable {
    static func == (lhs: AtomTemplate, rhs: AtomTemplate) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
