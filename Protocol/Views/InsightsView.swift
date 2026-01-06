//
//  InsightsView.swift
//  Protocol
//
//  Rebuilt V2.1 - 2025-12-31
//  Refined V2.2 - 2026-01-05 (User Feedback + UI Polish)
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = InsightsViewModel()
    
    // We only need templates for the filters
    @Query(sort: \MoleculeTemplate.title) private var templates: [MoleculeTemplate]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Crunching numbers...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // MARK: - Filters & Navigation (Moved to Top)
                        FilterAndNavSection(
                            viewModel: viewModel,
                            templates: templates
                        )
                        .padding(.top, 8) 
                        
                        // MARK: - Aesthetic Summary Card
                        AestheticSummaryCard(stats: viewModel.stats)
                        
                        // MARK: - Heatmap
                        if !viewModel.heatmapData.isEmpty {
                            HeatmapSection(
                                data: viewModel.heatmapData,
                                range: viewModel.selectedTimeRange
                            )
                        }
                        
                        // MARK: - Chart
                        ChartSection(
                            data: viewModel.chartPoints,
                            selectedDate: $viewModel.selectedChartDate
                        )
                        
                        // MARK: - Time of Day
                        if !viewModel.timeOfDayData.isEmpty {
                            TimeOfDaySection(data: viewModel.timeOfDayData)
                        }
                        
                        // MARK: - Habit Analysis
                        HabitAnalysisSection(
                            topHabits: viewModel.topHabitsData,
                            bottomHabits: viewModel.bottomHabitsData,
                            allHabitsBest: viewModel.allHabitsBest,
                            allHabitsWorst: viewModel.allHabitsWorst
                        )
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .navigationTitle("Insights")
            .background(Color(uiColor: .systemGroupedBackground))
            .task {
                viewModel.configure(modelContext: modelContext)
            }
            .refreshable {
                await viewModel.loadData()
            }
        }
    }
}

// MARK: - Aesthetic Summary Card
struct AestheticSummaryCard: View {
    let stats: SummaryStats
    
    // Premium Colors
    private var gradientColors: [Color] {
        if stats.overallCompletion >= 80 { return [.green, .mint] }
        else if stats.overallCompletion >= 50 { return [.orange, .yellow] }
        else { return [.red, .pink] }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Hero Section (Glass effect)
            HStack(spacing: 20) {
                // Circular Progress
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.1), lineWidth: 12)
                    
                    Circle()
                        .trim(from: 0, to: stats.overallCompletion / 100)
                        .stroke(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: gradientColors.first!.opacity(0.3), radius: 5)
                    
                    VStack(spacing: 2) {
                        Text("\(Int(stats.overallCompletion))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Rate")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)
                
                // Context Text
                VStack(alignment: .leading, spacing: 6) {
                    Text("Performance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(stats.consistencyRating.rawValue)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(gradientColors.first!)
                    
                    if let delta = stats.comparisonDelta {
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            Text("\(abs(Int(delta)))% vs last period")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(delta >= 0 ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(delta >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        )
                    }
                }
                
                Spacer()
            }
            .padding(20)
            
            Divider()
                .padding(.horizontal)
            
            // Stats Grid (Bottom)
            HStack(spacing: 0) {
                // Streak
                AestheticStatBox(
                    label: "Streak",
                    value: "\(stats.currentStreak)",
                    unit: "Days",
                    icon: "flame.fill",
                    color: .orange
                )
                
                Divider()
                    .frame(height: 40)
                
                // Completed
                AestheticStatBox(
                    label: "Done",
                    value: "\(stats.totalCompleted)",
                    unit: "Habits",
                    icon: "checkmark.circle.fill",
                    color: .blue
                )
                
                Divider()
                    .frame(height: 40)
                
                // Scheduled
                AestheticStatBox(
                    label: "Total",
                    value: "\(stats.totalScheduled)",
                    unit: "Habits",
                    icon: "list.bullet",
                    color: .secondary
                )
            }
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .padding(.horizontal, DesignTokens.paddingStandard)
    }
}

struct AestheticStatBox: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            VStack(spacing: 0) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Header & Filters & Navigation
struct FilterAndNavSection: View {
    @ObservedObject var viewModel: InsightsViewModel
    let templates: [MoleculeTemplate]
    
    private var compounds: [String] { viewModel.availableCompounds(from: templates) }
    private var moleculesInScope: [MoleculeTemplate] { viewModel.moleculesInCompound(viewModel.selectedCompound, from: templates) }
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. Filters (Top)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Time Range Picker
                    Menu {
                        ForEach(TimeRange.allCases) { range in
                            Button {
                                viewModel.selectedTimeRange = range
                            } label: {
                                if viewModel.selectedTimeRange == range {
                                    Label(range.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(range.rawValue)
                                }
                            }
                        }
                    } label: {
                        FilterChip(label: viewModel.selectedTimeRange.rawValue, icon: "calendar")
                    }
                    
                    // Compound
                    Menu {
                        Button("All Categories") { viewModel.selectedCompound = nil; viewModel.selectedMolecule = nil }
                        if !compounds.isEmpty {
                            Divider()
                            ForEach(compounds, id: \.self) { compound in
                                Button(compound) { viewModel.selectedCompound = compound; viewModel.selectedMolecule = nil }
                            }
                        }
                    } label: {
                        FilterChip(label: viewModel.selectedCompound ?? "All Categories", icon: "folder.fill")
                    }
                    
                    // Molecule
                    Menu {
                        Button("All Protocols") { viewModel.selectedMolecule = nil }
                        Divider()
                        ForEach(moleculesInScope) { molecule in
                            Button(molecule.title) { viewModel.selectedMolecule = molecule }
                        }
                    } label: {
                        FilterChip(label: viewModel.selectedMolecule?.title ?? "All Protocols", icon: "atom")
                    }
                }
                .padding(.horizontal)
            }
            
            // 2. Navigation Header (Date Picker - Bottom)
            HStack {
                Button {
                    withAnimation { viewModel.previousPeriod() }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(viewModel.currentPeriodLabel)
                    .font(.headline)
                    .fontWeight(.heavy)
                    .fontDesign(.rounded)
                
                Spacer()
                
                Button {
                    withAnimation { viewModel.nextPeriod() }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

struct FilterChip: View {
    let label: String; let icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(label).font(.subheadline).fontWeight(.medium)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(Capsule())
    }
}

// MARK: - Heatmap Section (Refined: Fixed Size)
struct HeatmapSection: View {
    let data: [Date: Double]
    let range: TimeRange
    
    private var displayData: [(Date, Double)] {
        let keys = data.keys.sorted()
        guard let start = keys.first, let end = keys.last else { return [] }
        
        var result: [(Date, Double)] = []
        let calendar = Calendar.current
        var current = start
        while current <= end {
            let rate = data[calendar.startOfDay(for: current)] ?? 0
            result.append((current, rate))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Consistency Heatmap")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(displayData, id: \.0) { item in
                    Rectangle()
                        .fill(color(for: item.1))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                             Text("\(Calendar.current.component(.day, from: item.0))")
                                .font(.system(size: 6))
                                .foregroundStyle(item.1 > 50 ? .white.opacity(0.8) : .secondary.opacity(0.4))
                        )
                        .cornerRadius(2)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .padding(.horizontal, DesignTokens.paddingStandard)
    }
    
    private func color(for rate: Double) -> Color {
        if rate == 0 { return Color(uiColor: .secondarySystemBackground) }
        let opacity: Double
        if rate < 25 { opacity = 0.3 }
        else if rate < 50 { opacity = 0.5 }
        else if rate < 75 { opacity = 0.7 }
        else { opacity = 1.0 }
        return Color.green.opacity(opacity)
    }
}

// MARK: - Chart Section (Refined: Hover & Daily Bars)
struct ChartSection: View {
    let data: [ChartDataPoint]
    @Binding var selectedDate: Date? // For interaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Completion Trend")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let selected = selectedDate, 
                   let point = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                    HStack(spacing: 4) {
                        Text(point.date.formatted(.dateTime.day().month()))
                            .foregroundStyle(.secondary)
                        Text("\(Int(point.completionRate))%")
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                    .padding(4)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal)
            
            if data.isEmpty {
                ContentUnavailableView("No Data", systemImage: "chart.bar.xaxis")
                    .frame(height: 180)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Rate", point.completionRate)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.empireGold, .empireBronze], startPoint: .bottom, endPoint: .top)
                    )
                    .cornerRadius(4)
                    
                    if let selected = selectedDate, Calendar.current.isDate(point.date, inSameDayAs: selected) {
                        RuleMark(x: .value("Date", point.date, unit: .day))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .zIndex(-1)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) { Text("\(intValue)%").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let x = value.location.x
                                        if let date: Date = proxy.value(atX: x) {
                                            selectedDate = date
                                        }
                                    }
                                    .onEnded { _ in selectedDate = nil }
                            )
                    }
                }
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .padding(.horizontal, DesignTokens.paddingStandard)
    }
}

// MARK: - Time of Day & Habits
struct TimeOfDaySection: View {
    let data: [TimeSlot: Int]
    var sortedData: [(TimeSlot, Int)] { TimeSlot.allCases.map { ($0, data[$0] ?? 0) } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When You Complete Habits").font(.headline).fontWeight(.bold).padding(.horizontal)
            Chart(sortedData, id: \.0) { item in
                SectorMark(angle: .value("Count", item.1), innerRadius: .ratio(0.5), angularInset: 1.5)
                    .cornerRadius(5)
                    .foregroundStyle(by: .value("Time", item.0.rawValue))
            }
            .frame(height: 180)
            .chartLegend(position: .bottom, spacing: 20)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .padding(.horizontal, DesignTokens.paddingStandard)
    }
}

struct HabitAnalysisSection: View {
    let topHabits: [HabitStat]; let bottomHabits: [HabitStat]; let allHabitsBest: [HabitStat]; let allHabitsWorst: [HabitStat]
    @State private var showingAllTop = false; @State private var showingAllBottom = false
    
    var body: some View {
        VStack(spacing: 20) {
            HabitListCard(title: "Strongest Habits", icon: "trophy.fill", color: .green, habits: topHabits, allHabits: allHabitsBest, emptyMessage: "Complete more habits to see your top performers", showingAll: $showingAllTop)
            HabitListCard(title: "Room for Improvement", icon: "exclamationmark.triangle.fill", color: .orange, habits: bottomHabits, allHabits: allHabitsWorst, emptyMessage: "All habits at 100%! Nothing needs improvement 🎉", showingAll: $showingAllBottom)
        }
        .padding(.horizontal)
    }
}

struct HabitListCard: View {
    let title: String; let icon: String; let color: Color; let habits: [HabitStat]; let allHabits: [HabitStat]; let emptyMessage: String; @Binding var showingAll: Bool
    private var hasMore: Bool { allHabits.count > habits.count }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            if habits.isEmpty {
                Text(emptyMessage).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(habits) { habit in HabitStatRow(habit: habit, accentColor: color) }
                if hasMore {
                    Button { showingAll = true } label: { HStack { Text("Show All (\(allHabits.count))").font(.subheadline).fontWeight(.medium); Image(systemName: "chevron.right").font(.caption) }.frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(uiColor: .tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12)) }.foregroundStyle(color)
                }
            }
        }
        .padding(DesignTokens.paddingStandard).background(Color(uiColor: .systemBackground)).clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .sheet(isPresented: $showingAll) { AllHabitsSheet(title: title, icon: icon, color: color, habits: allHabits) }
    }
}

struct AllHabitsSheet: View {
    let title: String; let icon: String; let color: Color; let habits: [HabitStat]; @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView { VStack(spacing: 8) { ForEach(habits) { habit in HabitStatRow(habit: habit, accentColor: color) } }.padding() }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } } }
    }
}

struct HabitStatRow: View {
    let habit: HabitStat; let accentColor: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(habit.consistencyRating.color.opacity(0.15)); Text(habit.consistencyRating.icon).font(.title3) }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) { Text(habit.name).font(.subheadline).fontWeight(.medium).lineLimit(1); Text("\(habit.completed)/\(habit.total) completed").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            ZStack { Circle().stroke(Color.gray.opacity(0.2), lineWidth: 4); Circle().trim(from: 0, to: habit.completionRate / 100).stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)); Text("\(Int(habit.completionRate))%").font(.caption2.bold()) }.frame(width: 44, height: 44)
        }
        .padding(.vertical, 8).padding(.horizontal, 12).background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
