//
//  RecurrenceTypes.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation

// MARK: - Recurrence Frequency
/// Defines how often a MoleculeTemplate repeats
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .daily: return "Every Day"
        case .weekly: return "Every Week"
        case .monthly: return "Every Month"
        case .custom: return "Custom"
        }
    }
    
    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .custom: return .day // Custom uses specific days
        }
    }
}

// MARK: - Recurrence End Rule Type
/// Defines when a recurring MoleculeTemplate should stop generating instances
/// Note: This is a simple enum without associated values for SwiftData compatibility
enum RecurrenceEndRuleType: String, Codable, CaseIterable, Identifiable {
    case never = "never"
    case onDate = "onDate"
    case afterOccurrences = "afterOccurrences"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .never: return "Never"
        case .onDate: return "On Date"
        case .afterOccurrences: return "After Occurrences"
        }
    }
}

// MARK: - Day of Week Helper
/// Helper struct for working with days of the week
struct DayOfWeek: Identifiable, Hashable {
    let rawValue: Int // 0 = Sunday, 1 = Monday, etc.
    
    var id: Int { rawValue }
    
    var shortName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.veryShortWeekdaySymbols[rawValue]
    }
    
    var fullName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.weekdaySymbols[rawValue]
    }
    
    static let allDays: [DayOfWeek] = (0...6).map { DayOfWeek(rawValue: $0) }
    
    static let weekdays: [DayOfWeek] = [1, 2, 3, 4, 5].map { DayOfWeek(rawValue: $0) }
    
    static let weekends: [DayOfWeek] = [0, 6].map { DayOfWeek(rawValue: $0) }
}

// MARK: - Recurrence Rule Utilities
extension Array where Element == Int {
    /// Converts an array of day integers to a readable string
    /// e.g., [1, 3, 5] -> "Mon, Wed, Fri"
    var daysDescription: String {
        let sortedDays = self.sorted()
        let dayNames = sortedDays.compactMap { dayIndex -> String? in
            guard dayIndex >= 0 && dayIndex <= 6 else { return nil }
            return DayOfWeek(rawValue: dayIndex).shortName
        }
        return dayNames.joined(separator: ", ")
    }
}
