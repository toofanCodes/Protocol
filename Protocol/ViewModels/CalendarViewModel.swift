//
//  CalendarViewModel.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    
    var id: String { rawValue }
}

enum FilterOption: Equatable, Hashable, Identifiable {
    case all
    case uncategorized
    case compound(String)
    
    var id: String {
        switch self {
        case .all: return "all"
        case .uncategorized: return "uncategorized"
        case .compound(let name): return "compound-\(name)"
        }
    }
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .uncategorized: return "Uncategorized"
        case .compound(let name): return name
        }
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentDate: Date = Date()
    @Published var viewMode: CalendarViewMode = .day
    @Published var selectedFilter: FilterOption = .all
    @Published var selectedInstance: MoleculeInstance? // For sheet presentation
    
    // MARK: - Computed Properties
    
    var title: String {
        let formatter = DateFormatter()
        switch viewMode {
        case .day:
            return currentDate.formatted(date: .complete, time: .omitted)
        case .week:
            // "Dec 28 - Jan 3"
            let startOfWeek = currentDate.startOfWeek
            let endOfWeek = Calendar.current.date(byAdding: .day, value: 6, to: startOfWeek) ?? currentDate
            
            let startFormatter = DateFormatter()
            startFormatter.dateFormat = "MMM d"
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "MMM d"
            
            return "\(startFormatter.string(from: startOfWeek)) - \(endFormatter.string(from: endOfWeek))"
            
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: currentDate)
        }
    }
    
    // MARK: - Actions
    
    func moveDate(by value: Int) {
        let calendar = Calendar.current
        switch viewMode {
        case .day:
            if let newDate = calendar.date(byAdding: .day, value: value, to: currentDate) {
                currentDate = newDate
            }
        case .week:
            if let newDate = calendar.date(byAdding: .day, value: value * 7, to: currentDate) {
                currentDate = newDate
            }
        case .month:
            if let newDate = calendar.date(byAdding: .month, value: value, to: currentDate) {
                currentDate = newDate
            }
        }
    }
    
    func isSameDay(date1: Date, date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    // MARK: - Filter Logic
    
    func shouldShow(instance: MoleculeInstance) -> Bool {
        guard isSameDay(date1: instance.scheduledDate, date2: currentDate) else { return false }
        return matchesFilter(instance)
    }
    
    func matchesFilter(_ instance: MoleculeInstance) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .uncategorized:
            // Show items with no template OR no compound assigned
            return instance.parentTemplate == nil || instance.parentTemplate?.compound == nil
        case .compound(let name):
            // Case insensitive comparison
            return instance.parentTemplate?.compound?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}

// MARK: - Date Helper
extension Date {
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
    
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
    
    var daysInMonth: [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: self) else { return [] }
        
        var dates: [Date] = []
        var date = monthInterval.start
        while date < monthInterval.end {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return dates
    }
    
    /// Returns days in month padded with previous/next month days to fill grid
    var calendarGridDays: [Date] {
        let calendar = Calendar.current
        let startOfMonth = self.startOfMonth
        
        // Find start of week for the 1st of month
        let startOfWeek = startOfMonth.startOfWeek
        
        // Generate 42 days (6 weeks) to cover any month
        var dates: [Date] = []
        var date = startOfWeek
        for _ in 0..<42 {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return dates
    }
}
