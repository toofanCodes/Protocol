//
//  InsightsViewModel.swift
//  Protocol
//
//  Rebuilt V2.1 - 2025-12-31
//

import SwiftUI
import SwiftData

// MARK: - Enums

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case mtd = "MTD"
    case year = "Year"
    case ytd = "YTD"
    case all = "All"
    
    var id: String { rawValue }
    
    var chartBucketType: ChartBucketType {
        switch self {
        case .week: return .day
        case .month, .mtd: return .week
        case .year, .ytd: return .month
        case .all: return .quarter
        }
    }
    
    func dateRange(relativeTo now: Date = Date()) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        switch self {
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
            return (start, now)
        case .month:
            guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return nil }
            return (start, now)
        case .mtd:
            let components = calendar.dateComponents([.year, .month], from: today)
            guard let start = calendar.date(from: components) else { return nil }
            return (start, now)
        case .year:
            guard let start = calendar.date(byAdding: .year, value: -1, to: today) else { return nil }
            return (start, now)
        case .ytd:
            let components = calendar.dateComponents([.year], from: today)
            guard let start = calendar.date(from: components) else { return nil }
            return (start, now)
        case .all:
            return nil
        }
    }
    
    /// Returns the previous period of the same duration for comparison
    func previousPeriod(relativeTo now: Date = Date()) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let current = dateRange(relativeTo: now) else { return nil }
        
        let duration = current.end.timeIntervalSince(current.start)
        let previousEnd = calendar.date(byAdding: .second, value: -1, to: current.start)!
        let previousStart = previousEnd.addingTimeInterval(-duration)
        
        return (previousStart, previousEnd)
    }
}

enum ChartBucketType {
    case day, week, month, quarter
}

enum ConsistencyRating: String {
    case perfect = "Perfect Rhythm"
    case good = "Solid"
    case spotty = "Spotty"
    case needsWork = "Needs Work"
    
    var icon: String {
        switch self {
        case .perfect: return "🎯"
        case .good: return "✅"
        case .spotty: return "⚡"
        case .needsWork: return "🔴"
        }
    }
    
    var color: Color {
        switch self {
        case .perfect: return .green
        case .good: return .blue
        case .spotty: return .orange
        case .needsWork: return .red
        }
    }
}

// MARK: - Data Models

struct SummaryStats {
    let overallCompletion: Double // 0-100
    let comparisonDelta: Double? // e.g., +12 means 12% better than last period
    let currentStreak: Int // consecutive days with completions
    let totalCompleted: Int
    let totalScheduled: Int
    let consistencyRating: ConsistencyRating
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    let completionRate: Double // 0-100
    let total: Int
    let completed: Int
}

struct HabitStat: Identifiable {
    let id = UUID()
    let name: String
    let completionRate: Double // 0-100
    let total: Int
    let completed: Int
    let weightedScore: Double // Completion% × log(Total + 1)
    let consistencyRating: ConsistencyRating
}

// MARK: - ViewModel

@MainActor
final class InsightsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var selectedTimeRange: TimeRange = .week
    @Published var selectedCompound: String? = nil // nil = All Compounds
    @Published var selectedMolecule: MoleculeTemplate? = nil // nil = All in Compound
    
    // MARK: - Summary Stats
    
    func summaryStats(instances: [MoleculeInstance]) -> SummaryStats {
        let filtered = filterInstances(instances)
        
        let total = filtered.count
        let completed = filtered.filter { $0.isCompleted }.count
        let rate = total > 0 ? (Double(completed) / Double(total)) * 100 : 0
        
        // Comparison to previous period
        var delta: Double? = nil
        if let previousRange = selectedTimeRange.previousPeriod() {
            let previousInstances = instances.filter {
                $0.scheduledDate >= previousRange.start && $0.scheduledDate <= previousRange.end
            }
            let prevFiltered = applyNonTimeFilters(previousInstances)
            let prevTotal = prevFiltered.count
            let prevCompleted = prevFiltered.filter { $0.isCompleted }.count
            let prevRate = prevTotal > 0 ? (Double(prevCompleted) / Double(prevTotal)) * 100 : 0
            
            if prevTotal > 0 {
                delta = rate - prevRate
            }
        }
        
        // Streak calculation
        let streak = calculateStreak(instances: instances)
        
        // Consistency rating
        let consistency = calculateConsistencyRating(instances: filtered)
        
        return SummaryStats(
            overallCompletion: rate,
            comparisonDelta: delta,
            currentStreak: streak,
            totalCompleted: completed,
            totalScheduled: total,
            consistencyRating: consistency
        )
    }
    
    // MARK: - Chart Data
    
    func chartData(instances: [MoleculeInstance]) -> [ChartDataPoint] {
        let filtered = filterInstances(instances)
        guard !filtered.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let bucketType = selectedTimeRange.chartBucketType
        
        // Group by bucket
        let grouped = Dictionary(grouping: filtered) { instance -> Date in
            bucketDate(for: instance.scheduledDate, type: bucketType, calendar: calendar)
        }
        
        var points: [ChartDataPoint] = []
        
        for (date, group) in grouped {
            let total = group.count
            let completed = group.filter { $0.isCompleted }.count
            let rate = total > 0 ? (Double(completed) / Double(total)) * 100 : 0
            
            let label = bucketLabel(for: date, type: bucketType, calendar: calendar)
            
            points.append(ChartDataPoint(
                label: label,
                date: date,
                completionRate: rate,
                total: total,
                completed: completed
            ))
        }
        
        return points.sorted { $0.date < $1.date }
    }
    
    // MARK: - Habit Stats (Weighted)
    
    func habitStats(instances: [MoleculeInstance]) -> [HabitStat] {
        let filtered = filterInstances(instances)
        let allAtoms = filtered.flatMap { $0.atomInstances }
        
        let grouped = Dictionary(grouping: allAtoms) { $0.title }
        
        var stats: [HabitStat] = []
        
        for (name, atoms) in grouped {
            let total = atoms.count
            let completed = atoms.filter { $0.isCompleted }.count
            let rate = total > 0 ? (Double(completed) / Double(total)) * 100 : 0
            
            // Weighted score: Completion% × log(Total + 1)
            let weight = rate * log(Double(total + 1))
            
            // Consistency for this habit
            let consistency = atomConsistencyRating(atoms: atoms)
            
            stats.append(HabitStat(
                name: name,
                completionRate: rate,
                total: total,
                completed: completed,
                weightedScore: weight,
                consistencyRating: consistency
            ))
        }
        
        // Sort by weighted score descending
        return stats.sorted { $0.weightedScore > $1.weightedScore }
    }
    
    func topHabits(instances: [MoleculeInstance], count: Int = 3) -> [HabitStat] {
        Array(habitStats(instances: instances).prefix(count))
    }
    
    func bottomHabits(instances: [MoleculeInstance], count: Int = 3) -> [HabitStat] {
        let stats = habitStats(instances: instances)
        // Filter out 100% completion habits - they don't need improvement
        let needsWork = stats.filter { $0.completionRate < 100 }
        guard !needsWork.isEmpty else { return [] }
        return Array(needsWork.suffix(count).reversed())
    }
    
    /// All habits sorted best to worst (for "Show More")
    func allHabitsSortedBest(instances: [MoleculeInstance]) -> [HabitStat] {
        habitStats(instances: instances)
    }
    
    /// All habits sorted worst to best (for "Show More" on Room for Improvement)
    func allHabitsSortedWorst(instances: [MoleculeInstance]) -> [HabitStat] {
        habitStats(instances: instances)
            .filter { $0.completionRate < 100 }
            .sorted { $0.weightedScore < $1.weightedScore }
    }
    
    // MARK: - Available Compounds
    
    func availableCompounds(from templates: [MoleculeTemplate]) -> [String] {
        Array(Set(templates.compactMap { $0.compound })).sorted()
    }
    
    func moleculesInCompound(_ compound: String?, from templates: [MoleculeTemplate]) -> [MoleculeTemplate] {
        guard let compound = compound else { return templates }
        return templates.filter { $0.compound == compound }
    }
    
    // MARK: - Private Helpers
    
    private func filterInstances(_ instances: [MoleculeInstance]) -> [MoleculeInstance] {
        var result = instances
        
        // Time filter
        if let range = selectedTimeRange.dateRange() {
            result = result.filter { $0.scheduledDate >= range.start && $0.scheduledDate <= range.end }
        }
        
        result = applyNonTimeFilters(result)
        
        return result
    }
    
    private func applyNonTimeFilters(_ instances: [MoleculeInstance]) -> [MoleculeInstance] {
        var result = instances
        
        // Compound filter
        if let compound = selectedCompound {
            result = result.filter { $0.parentTemplate?.compound == compound }
        }
        
        // Molecule filter
        if let molecule = selectedMolecule {
            result = result.filter { $0.parentTemplate?.id == molecule.id }
        }
        
        return result
    }
    
    private func calculateStreak(instances: [MoleculeInstance]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get all unique dates with at least one completion
        let completedDates = Set(
            instances
                .filter { $0.isCompleted }
                .map { calendar.startOfDay(for: $0.scheduledDate) }
        )
        
        var streak = 0
        var checkDate = today
        
        // Count backwards from today
        while completedDates.contains(checkDate) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
        }
        
        return streak
    }
    
    private func calculateConsistencyRating(instances: [MoleculeInstance]) -> ConsistencyRating {
        guard !instances.isEmpty else { return .needsWork }
        
        let total = instances.count
        let completed = instances.filter { $0.isCompleted }.count
        let rate = Double(completed) / Double(total)
        
        // Also check variance in completion pattern
        let calendar = Calendar.current
        let dailyGroups = Dictionary(grouping: instances) { calendar.startOfDay(for: $0.scheduledDate) }
        
        var dailyRates: [Double] = []
        for (_, group) in dailyGroups {
            let dayTotal = group.count
            let dayCompleted = group.filter { $0.isCompleted }.count
            dailyRates.append(Double(dayCompleted) / Double(dayTotal))
        }
        
        // Calculate variance
        let mean = dailyRates.reduce(0, +) / Double(dailyRates.count)
        let variance = dailyRates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(dailyRates.count)
        
        if rate >= 0.95 && variance < 0.05 {
            return .perfect
        } else if rate >= 0.75 && variance < 0.15 {
            return .good
        } else if rate >= 0.50 {
            return .spotty
        } else {
            return .needsWork
        }
    }
    
    private func atomConsistencyRating(atoms: [AtomInstance]) -> ConsistencyRating {
        guard !atoms.isEmpty else { return .needsWork }
        
        let completed = atoms.filter { $0.isCompleted }.count
        let rate = Double(completed) / Double(atoms.count)
        
        if rate >= 0.95 { return .perfect }
        else if rate >= 0.75 { return .good }
        else if rate >= 0.50 { return .spotty }
        else { return .needsWork }
    }
    
    private func bucketDate(for date: Date, type: ChartBucketType, calendar: Calendar) -> Date {
        switch type {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? date
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        case .quarter:
            let month = calendar.component(.month, from: date)
            let quarter = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: date)
            components.month = quarter
            return calendar.date(from: components) ?? date
        }
    }
    
    private func bucketLabel(for date: Date, type: ChartBucketType, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        switch type {
        case .day:
            formatter.dateFormat = "E" // Mon, Tue
        case .week:
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            return "W\(weekOfYear)"
        case .month:
            formatter.dateFormat = "MMM" // Jan, Feb
        case .quarter:
            let month = calendar.component(.month, from: date)
            let quarter = ((month - 1) / 3) + 1
            return "Q\(quarter)"
        }
        return formatter.string(from: date)
    }
}
