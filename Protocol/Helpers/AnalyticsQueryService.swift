//
//  AnalyticsQueryService.swift
//  Protocol
//
//  Created on 2026-01-05.
//

import Foundation
import SwiftData

// MARK: - Supporting Types

/// Represents a time slot for time-of-day analysis
enum TimeSlot: String, CaseIterable {
    case earlyMorning = "Early Morning"  // 5-8 AM
    case morning = "Morning"              // 8-12 PM
    case afternoon = "Afternoon"          // 12-5 PM
    case evening = "Evening"              // 5-9 PM
    case night = "Night"                  // 9 PM - 5 AM
    
    static func from(hour: Int) -> TimeSlot {
        switch hour {
        case 5..<8: return .earlyMorning
        case 8..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

/// Comparison result between two time periods
struct PeriodComparison {
    let currentRate: Double
    let previousRate: Double
    let delta: Double // Percentage point difference
    let trend: Trend
    
    enum Trend {
        case improving, declining, stable
    }
}

/// Habit performance statistics
struct HabitPerformance: Identifiable {
    let id: UUID
    let title: String
    let completionRate: Double
    let completedCount: Int
    let totalCount: Int
}

// MARK: - Analytics Query Service

/// Service providing efficient, predicate-based analytics queries.
/// Uses database-level filtering instead of loading all records into memory.
@MainActor
final class AnalyticsQueryService {
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Completion Rate Queries
    
    /// Calculates completion rate for a date range
    /// - Parameters:
    ///   - from: Start date (inclusive)
    ///   - to: End date (inclusive)
    ///   - molecule: Optional filter for specific molecule
    /// - Returns: Completion percentage (0-100)
    func completionRate(from: Date, to: Date, molecule: MoleculeTemplate? = nil) -> Double {
        let scheduled = scheduledCount(from: from, to: to, molecule: molecule)
        guard scheduled > 0 else { return 0 }
        let completed = completedCount(from: from, to: to, molecule: molecule)
        return (Double(completed) / Double(scheduled)) * 100
    }
    
    /// Counts completed instances in a date range
    func completedCount(from: Date, to: Date, molecule: MoleculeTemplate? = nil) -> Int {
        let startOfFrom = Calendar.current.startOfDay(for: from)
        let endOfTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
        
        var descriptor: FetchDescriptor<MoleculeInstance>
        
        if let moleculeId = molecule?.id {
            descriptor = FetchDescriptor<MoleculeInstance>(
                predicate: #Predicate { instance in
                    instance.isCompleted &&
                    instance.scheduledDate >= startOfFrom &&
                    instance.scheduledDate < endOfTo &&
                    instance.parentTemplate?.id == moleculeId
                }
            )
        } else {
            descriptor = FetchDescriptor<MoleculeInstance>(
                predicate: #Predicate { instance in
                    instance.isCompleted &&
                    instance.scheduledDate >= startOfFrom &&
                    instance.scheduledDate < endOfTo
                }
            )
        }
        
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    /// Counts scheduled instances in a date range
    func scheduledCount(from: Date, to: Date, molecule: MoleculeTemplate? = nil) -> Int {
        let startOfFrom = Calendar.current.startOfDay(for: from)
        let endOfTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
        
        var descriptor: FetchDescriptor<MoleculeInstance>
        
        if let moleculeId = molecule?.id {
            descriptor = FetchDescriptor<MoleculeInstance>(
                predicate: #Predicate { instance in
                    instance.scheduledDate >= startOfFrom &&
                    instance.scheduledDate < endOfTo &&
                    instance.parentTemplate?.id == moleculeId
                }
            )
        } else {
            descriptor = FetchDescriptor<MoleculeInstance>(
                predicate: #Predicate { instance in
                    instance.scheduledDate >= startOfFrom &&
                    instance.scheduledDate < endOfTo
                }
            )
        }
        
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    // MARK: - Streak Calculations
    
    /// Calculates the current streak (consecutive days with at least one completion)
    func currentStreak(for molecule: MoleculeTemplate? = nil) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var checkDate = today
        
        // Check up to 365 days back
        for _ in 0..<365 {
            // Check if there was a completion on this date
            let hasCompletion = completedCount(from: checkDate, to: checkDate, molecule: molecule) > 0
            
            // For today, also check if there are uncompleted scheduled items
            if calendar.isDateInToday(checkDate) {
                let scheduled = scheduledCount(from: checkDate, to: checkDate, molecule: molecule)
                if scheduled > 0 && !hasCompletion {
                    // Today has scheduled items but none completed yet - streak continues from yesterday
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
                    continue
                }
            }
            
            if hasCompletion {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        
        return streak
    }
    
    /// Calculates the longest streak ever achieved
    func longestStreak(for molecule: MoleculeTemplate? = nil) -> Int {
        let calendar = Calendar.current
        
        // Fetch all completed instances, sorted by date
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate { instance in
                instance.isCompleted
            },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        
        guard let instances = try? modelContext.fetch(descriptor) else { return 0 }
        
        // Filter by molecule if needed
        let filtered: [MoleculeInstance]
        if let moleculeId = molecule?.id {
            filtered = instances.filter { $0.parentTemplate?.id == moleculeId }
        } else {
            filtered = instances
        }
        
        guard !filtered.isEmpty else { return 0 }
        
        // Get unique completion dates
        let completionDates = Set(filtered.map { calendar.startOfDay(for: $0.scheduledDate) })
        let sortedDates = completionDates.sorted()
        
        var longestStreak = 1
        var currentStreak = 1
        
        for i in 1..<sortedDates.count {
            let daysBetween = calendar.dateComponents([.day], from: sortedDates[i-1], to: sortedDates[i]).day ?? 0
            
            if daysBetween == 1 {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }
        
        return longestStreak
    }
    
    // MARK: - Habit Rankings
    
    /// Returns top performing habits by completion rate
    func topPerformingHabits(limit: Int = 5, from: Date, to: Date) -> [HabitPerformance] {
        return habitPerformances(from: from, to: to)
            .sorted { $0.completionRate > $1.completionRate }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Returns bottom performing habits by completion rate
    func bottomPerformingHabits(limit: Int = 5, from: Date, to: Date) -> [HabitPerformance] {
        return habitPerformances(from: from, to: to)
            .filter { $0.completionRate < 100 } // Exclude perfect scores
            .sorted { $0.completionRate < $1.completionRate }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Returns performance stats for all habits
    private func habitPerformances(from: Date, to: Date) -> [HabitPerformance] {
        let startOfFrom = Calendar.current.startOfDay(for: from)
        let endOfTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
        
        // Fetch all instances in range
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate { instance in
                instance.scheduledDate >= startOfFrom &&
                instance.scheduledDate < endOfTo
            }
        )
        
        guard let instances = try? modelContext.fetch(descriptor) else { return [] }
        
        // Group by template
        var templateStats: [UUID: (title: String, completed: Int, total: Int)] = [:]
        
        for instance in instances {
            guard let template = instance.parentTemplate else { continue }
            let id = template.id
            
            var stats = templateStats[id] ?? (title: template.title, completed: 0, total: 0)
            stats.total += 1
            if instance.isCompleted {
                stats.completed += 1
            }
            templateStats[id] = stats
        }
        
        return templateStats.map { id, stats in
            HabitPerformance(
                id: id,
                title: stats.title,
                completionRate: stats.total > 0 ? (Double(stats.completed) / Double(stats.total)) * 100 : 0,
                completedCount: stats.completed,
                totalCount: stats.total
            )
        }
    }
    
    // MARK: - Time Analysis
    
    /// Returns completions grouped by time of day
    func completionsByTimeOfDay(from: Date, to: Date) -> [TimeSlot: Int] {
        let startOfFrom = Calendar.current.startOfDay(for: from)
        let endOfTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
        
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate { instance in
                instance.isCompleted &&
                instance.scheduledDate >= startOfFrom &&
                instance.scheduledDate < endOfTo
            }
        )
        
        guard let instances = try? modelContext.fetch(descriptor) else { return [:] }
        
        var results: [TimeSlot: Int] = [:]
        let calendar = Calendar.current
        
        for instance in instances {
            let hour = calendar.component(.hour, from: instance.completedAt ?? instance.scheduledDate)
            let slot = TimeSlot.from(hour: hour)
            results[slot, default: 0] += 1
        }
        
        return results
    }
    
    // MARK: - Heatmap Data
    
    /// Returns daily completion rates for calendar heatmap
    func dailyCompletionRates(from: Date, to: Date) -> [Date: Double] {
        let calendar = Calendar.current
        var results: [Date: Double] = [:]
        var currentDate = calendar.startOfDay(for: from)
        let endDate = calendar.startOfDay(for: to)
        
        while currentDate <= endDate {
            let rate = completionRate(from: currentDate, to: currentDate)
            results[currentDate] = rate
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return results
    }
    
    // MARK: - Period Comparison
    
    /// Compares completion rates between two periods
    func periodComparison(current: (from: Date, to: Date), previous: (from: Date, to: Date)) -> PeriodComparison {
        let currentRate = completionRate(from: current.from, to: current.to)
        let previousRate = completionRate(from: previous.from, to: previous.to)
        let delta = currentRate - previousRate
        
        let trend: PeriodComparison.Trend
        if delta > 2 {
            trend = .improving
        } else if delta < -2 {
            trend = .declining
        } else {
            trend = .stable
        }
        
        return PeriodComparison(
            currentRate: currentRate,
            previousRate: previousRate,
            delta: delta,
            trend: trend
        )
    }
}
