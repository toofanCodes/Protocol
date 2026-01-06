//
//  InsightsViewModel.swift
//  Protocol
//
//  Rebuilt V2.1 - 2025-12-31
//  Refactored for AnalyticsQueryService - 2026-01-05
//  Refined V2.2 - 2026-01-05 (User Feedback)
//

import SwiftUI
import SwiftData

// MARK: - Enums

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case mtd = "MTD"
    // Removed Year, YTD, All per user feedback
    
    var id: String { rawValue }
    
    // Always use day buckets for the main chart now
    var chartBucketType: ChartBucketType {
        return .day
    }
}

enum ChartBucketType {
    case day
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
    
    static let empty = SummaryStats(
        overallCompletion: 0,
        comparisonDelta: nil,
        currentStreak: 0,
        totalCompleted: 0,
        totalScheduled: 0,
        consistencyRating: .needsWork
    )
}

struct ChartDataPoint: Identifiable, Equatable {
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
    
    @Published var selectedTimeRange: TimeRange = .mtd {
        didSet {
            periodOffset = 0 // Reset offset when changing range type
            Task { await loadData() }
        }
    }
    
    // 0 = Current period, -1 = Previous, 1 = Next (future)
    @Published var periodOffset: Int = 0 {
        didSet { Task { await loadData() } }
    }
    
    @Published var selectedCompound: String? = nil { // nil = All Compounds
        didSet { Task { await loadData() } }
    }
    @Published var selectedMolecule: MoleculeTemplate? = nil { // nil = All in Compound
        didSet { Task { await loadData() } }
    }
    
    // Chart Selection
    @Published var selectedChartDate: Date? = nil
    
    @Published private(set) var stats: SummaryStats = .empty
    @Published private(set) var chartPoints: [ChartDataPoint] = []
    @Published private(set) var topHabitsData: [HabitStat] = []
    @Published private(set) var bottomHabitsData: [HabitStat] = []
    @Published private(set) var allHabitsBest: [HabitStat] = []
    @Published private(set) var allHabitsWorst: [HabitStat] = []
    
    @Published private(set) var heatmapData: [Date: Double] = [:]
    @Published private(set) var timeOfDayData: [TimeSlot: Int] = [:]
    
    @Published private(set) var isLoading = false
    
    // MARK: - Dependencies
    private var analyticsService: AnalyticsQueryService?
    
    // MARK: - Initialization
    
    func configure(modelContext: ModelContext) {
        self.analyticsService = AnalyticsQueryService(modelContext: modelContext)
        Task { await loadData() }
    }
    
    // MARK: - Period Navigation
    
    func nextPeriod() {
        periodOffset += 1
    }
    
    func previousPeriod() {
        periodOffset -= 1
    }
    
    var currentPeriodLabel: String {
        let (start, end) = calculateDateRange()
        let formatter = DateFormatter()
        
        switch selectedTimeRange {
        case .week:
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        case .month, .mtd:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        }
    }
    
    // MARK: - Date Logic
    
    private func calculateDateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Base logic for 0 offset
        let baseStart: Date
        let baseEnd: Date
        
        switch selectedTimeRange {
        case .week:
            // "Week" roughly means last 7 days including today? OR standard calendar week?
            // "Week" in apps usually means "This Week" (Mon-Sun) or "Last 7 Days". 
            // Previous code was "last 6 days + today". Let's stick to "Last 7 Days" type rolling window 
            // or standard week. Standard week is easier for "Month" comparison.
            // Let's use clean calendar weeks based on feedback for "scrolling".
            // Actually, if I offset by 1, I expect the previous Week.
            // Let's anchor to Start of Week.
            
            // Anchor: Today
            // If offset is 0, we want the current week containing today.
            // If we use "rolling", navigation is weird (-7 days).
            // Let's use Calendar Week (Monday start).
            
            // Find start of current week
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            let startOfWeek = calendar.date(from: components)!
            
            baseStart = calendar.date(byAdding: .weekOfYear, value: periodOffset, to: startOfWeek)!
            baseEnd = calendar.date(byAdding: .day, value: 6, to: baseStart)!
            
        case .month:
            // Whole Month
            let components = calendar.dateComponents([.year, .month], from: today)
            let startOfMonth = calendar.date(from: components)!
            
            baseStart = calendar.date(byAdding: .month, value: periodOffset, to: startOfMonth)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: baseStart)!
            baseEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth)!
            
        case .mtd:
            // Month to Date. Same as Month, but end cap is Today if offset is 0.
            // If offset < 0, it behaves like full Month.
            
            let components = calendar.dateComponents([.year, .month], from: today)
            let startOfMonth = calendar.date(from: components)!
            baseStart = calendar.date(byAdding: .month, value: periodOffset, to: startOfMonth)!
            
            if periodOffset == 0 {
                // Today
                baseEnd = today
            } else {
                // Full past month
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: baseStart)!
                baseEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth)!
            }
        }
        
        return (baseStart, baseEnd)
    }
    
    private func previousPeriodRange(currentStart: Date, currentEnd: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let duration = currentEnd.timeIntervalSince(currentStart)
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart)!
        // Approximate start
        let previousStart = calendar.date(byAdding: .day, value: 1, to: previousEnd.addingTimeInterval(-duration))!
        // Re-align if needed for months
        if selectedTimeRange == .month || selectedTimeRange == .mtd {
             if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: currentStart) {
                 return (prevMonthStart, previousEnd)
             }
        }
        return (previousStart, previousEnd)
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        guard let service = analyticsService else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let range = calculateDateRange()
        
        // 1. Summary Stats
        let completionRate = service.completionRate(from: range.start, to: range.end, molecule: selectedMolecule)
        let scheduled = service.scheduledCount(from: range.start, to: range.end, molecule: selectedMolecule)
        let completed = service.completedCount(from: range.start, to: range.end, molecule: selectedMolecule)
        let streak = service.currentStreak(for: selectedMolecule)
        
        // Comparison
        var delta: Double? = nil
        let prevRange = previousPeriodRange(currentStart: range.start, currentEnd: range.end)
        let comparison = service.periodComparison(
            current: (range.start, range.end),
            previous: (prevRange.start, prevRange.end)
        )
        delta = comparison.delta
        
        // Consistency Logic
        let consistency: ConsistencyRating
        if completionRate >= 95 { consistency = .perfect }
        else if completionRate >= 75 { consistency = .good }
        else if completionRate >= 50 { consistency = .spotty }
        else { consistency = .needsWork }
        
        self.stats = SummaryStats(
            overallCompletion: completionRate,
            comparisonDelta: delta,
            currentStreak: streak,
            totalCompleted: completed,
            totalScheduled: scheduled,
            consistencyRating: consistency
        )
        
        // 2. Chart Data (ALWAYS DAILY NOW)
        var points: [ChartDataPoint] = []
        let calendar = Calendar.current
        var currentDate = range.start
        
        while currentDate <= range.end {
            // For Day bucket, start == end
            let rate = service.completionRate(from: currentDate, to: currentDate, molecule: selectedMolecule)
            let total = service.scheduledCount(from: currentDate, to: currentDate, molecule: selectedMolecule)
            let compl = service.completedCount(from: currentDate, to: currentDate, molecule: selectedMolecule)
            
            let label = bucketLabel(for: currentDate)
            
            points.append(ChartDataPoint(
                label: label,
                date: currentDate,
                completionRate: rate,
                total: total,
                completed: compl
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        self.chartPoints = points
        
        // 3. Habit Stats (Using service for the range)
        let allHabits = service.topPerformingHabits(limit: 1000, from: range.start, to: range.end)
        
        // Simple client side filter if needed (skipping strict compound filter for perf per previous logic, 
        // can refine if we fetch templates)
        let filteredHabits = allHabits // Placeholder: Assumes service returned what we want for now
        
        // Compute Weighted Scores
        let enrichedHabits = filteredHabits.map { stat -> HabitStat in
            let weight = stat.completionRate * log(Double(stat.totalCount + 1))
            
            let consistency: ConsistencyRating
            if stat.completionRate >= 95 { consistency = .perfect }
            else if stat.completionRate >= 75 { consistency = .good }
            else if stat.completionRate >= 50 { consistency = .spotty }
            else { consistency = .needsWork }
            
            return HabitStat(
                name: stat.title,
                completionRate: stat.completionRate,
                total: stat.totalCount,
                completed: stat.completedCount,
                weightedScore: weight,
                consistencyRating: consistency
            )
        }.sorted { $0.weightedScore > $1.weightedScore }
        
        self.allHabitsBest = enrichedHabits
        self.allHabitsWorst = enrichedHabits.filter { $0.completionRate < 100 }.sorted { $0.weightedScore < $1.weightedScore }
        
        self.topHabitsData = Array(enrichedHabits.prefix(3))
        self.bottomHabitsData = Array(allHabitsWorst.prefix(3))
        
        // 4. Heatmap
        self.heatmapData = service.dailyCompletionRates(from: range.start, to: range.end)
        
        // 5. Time of Day
        self.timeOfDayData = service.completionsByTimeOfDay(from: range.start, to: range.end)
    }

    
    // MARK: - Available Compounds
    
    func availableCompounds(from templates: [MoleculeTemplate]) -> [String] {
        Array(Set(templates.compactMap { $0.compound })).sorted()
    }
    
    func moleculesInCompound(_ compound: String?, from templates: [MoleculeTemplate]) -> [MoleculeTemplate] {
        guard let compound = compound else { return templates }
        return templates.filter { $0.compound == compound }
    }
    
    // MARK: - Helpers
    
    private func bucketLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d" // Just the day number
        return formatter.string(from: date)
    }
}
