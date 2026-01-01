//
//  AtomInputType.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation

/// Defines the input type for an Atom (task)
/// This determines how the user interacts with the task
enum AtomInputType: String, Codable, CaseIterable, Identifiable {
    /// Binary = Checkbox (Done/Not Done)
    case binary = "binary"
    
    /// Counter = Incremental (e.g., 0/5 glasses of water)
    case counter = "counter"
    
    /// Value = Numeric Entry (e.g., Weight: 91kg)
    case value = "value"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .binary: return "Checkbox"
        case .counter: return "Counter"
        case .value: return "Value Entry"
        }
    }
    
    var description: String {
        switch self {
        case .binary: return "Simple done/not done"
        case .counter: return "Track progress (e.g., 3/5)"
        case .value: return "Enter a number (e.g., weight)"
        }
    }
    
    var iconName: String {
        switch self {
        case .binary: return "checkmark.circle"
        case .counter: return "number.circle"
        case .value: return "textformat.123"
        }
    }
}
