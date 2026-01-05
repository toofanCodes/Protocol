//
//  InsightsView.swift
//  Protocol
//
//  Rebuilt V2.1 - 2025-12-31
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    
    @Query(sort: \MoleculeInstance.scheduledDate) private var allInstances: [MoleculeInstance]
    @Query(sort: \MoleculeTemplate.title) private var templates: [MoleculeTemplate]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - Summary Card
                    SummaryCard(stats: viewModel.summaryStats(instances: allInstances))
                    
                    // MARK: - Filters
                    FilterSection(
                        viewModel: viewModel,
                        templates: templates
                    )
                    
                    // MARK: - Chart
                    ChartSection(
                        data: viewModel.chartData(instances: allInstances),
                        timeRange: viewModel.selectedTimeRange
                    )
                    
                    // MARK: - Habit Analysis
                    HabitAnalysisSection(
                        topHabits: viewModel.topHabits(instances: allInstances),
                        bottomHabits: viewModel.bottomHabits(instances: allInstances),
                        allHabitsBest: viewModel.allHabitsSortedBest(instances: allInstances),
                        allHabitsWorst: viewModel.allHabitsSortedWorst(instances: allInstances)
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .navigationTitle("Insights")
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let stats: SummaryStats
    
    var body: some View {
        VStack(spacing: 16) {
            // Main Stat
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(stats.overallCompletion))%")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(statColor)
                    
                    Text("Overall Completion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Delta Badge
                if let delta = stats.comparisonDelta {
                    DeltaBadge(delta: delta)
                }
            }
            
            Divider()
            
            // Secondary Stats Row
            HStack(spacing: 24) {
                // Streak
                StatPill(
                    icon: "flame.fill",
                    value: "\(stats.currentStreak)",
                    label: "Day Streak",
                    color: stats.currentStreak > 0 ? .empireGold : .gray
                )
                
                Spacer()
                
                // Completed/Total
                StatPill(
                    icon: "checkmark.circle.fill",
                    value: "\(stats.totalCompleted)/\(stats.totalScheduled)",
                    label: "Completed",
                    color: .green
                )
                
                Spacer()
                
                // Consistency
                VStack(spacing: 4) {
                    Text(stats.consistencyRating.icon)
                        .font(.title2)
                    Text(stats.consistencyRating.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusLarge)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
        .padding(.horizontal, DesignTokens.paddingStandard)
    }
    
    private var statColor: Color {
        if stats.overallCompletion >= 80 { return .green }
        else if stats.overallCompletion >= 50 { return .orange }
        else { return .red }
    }
}

struct DeltaBadge: View {
    let delta: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.bold())
            Text("\(abs(Int(delta)))%")
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(delta >= 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        )
        .foregroundStyle(delta >= 0 ? .green : .red)
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(value)
                    .font(.headline)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Filter Section

struct FilterSection: View {
    @ObservedObject var viewModel: InsightsViewModel
    let templates: [MoleculeTemplate]
    
    private var compounds: [String] {
        viewModel.availableCompounds(from: templates)
    }
    
    private var moleculesInScope: [MoleculeTemplate] {
        viewModel.moleculesInCompound(viewModel.selectedCompound, from: templates)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Selected Molecule Header (when filtering by specific molecule)
            if let molecule = viewModel.selectedMolecule {
                HStack(spacing: 16) {
                    // Large Avatar (60x60)
                    AvatarView(
                        molecule: molecule,
                        size: 60
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(molecule.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        
                        Text(molecule.recurrenceDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if let compound = molecule.compound {
                            Text(compound)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Clear filter button
                    Button {
                        viewModel.selectedMolecule = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
            
            // Two-tier filter row
            HStack(spacing: 12) {
                // Compound Filter
                Menu {
                    Button("All Categories") {
                        viewModel.selectedCompound = nil
                        viewModel.selectedMolecule = nil
                    }
                    
                    if !compounds.isEmpty {
                        Divider()
                        ForEach(compounds, id: \.self) { compound in
                            Button(compound) {
                                viewModel.selectedCompound = compound
                                viewModel.selectedMolecule = nil
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        label: viewModel.selectedCompound ?? "All Categories",
                        icon: "folder.fill"
                    )
                }
                
                // Molecule Filter (only if compound selected)
                if viewModel.selectedCompound != nil {
                    Menu {
                        Button("All in \(viewModel.selectedCompound!)") {
                            viewModel.selectedMolecule = nil
                        }
                        
                        Divider()
                        
                        ForEach(moleculesInScope) { molecule in
                            Button(molecule.title) {
                                viewModel.selectedMolecule = molecule
                            }
                        }
                    } label: {
                        FilterChip(
                            label: viewModel.selectedMolecule?.title ?? "All Protocols",
                            icon: "atom"
                        )
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Time Range Picker
            Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    let label: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(Capsule())
    }
}

// MARK: - Chart Section

struct ChartSection: View {
    let data: [ChartDataPoint]
    let timeRange: TimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Completion Trend")
                .font(.headline)
                .padding(.horizontal)
            
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No records found for this period.")
                )
                .frame(height: 220)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("Period", point.label),
                        y: .value("Rate", point.completionRate)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.empireGold, .empireBronze],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if point.completionRate > 0 {
                            Text("\(Int(point.completionRate))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)%")
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .padding(.horizontal, DesignTokens.paddingStandard)
    }
}

// MARK: - Habit Analysis Section

struct HabitAnalysisSection: View {
    let topHabits: [HabitStat]
    let bottomHabits: [HabitStat]
    let allHabitsBest: [HabitStat]
    let allHabitsWorst: [HabitStat]
    
    @State private var showingAllTop = false
    @State private var showingAllBottom = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Top Performers
            HabitListCard(
                title: "Strongest Habits",
                icon: "trophy.fill",
                color: .green,
                habits: topHabits,
                allHabits: allHabitsBest,
                emptyMessage: "Complete more habits to see your top performers",
                showingAll: $showingAllTop
            )
            
            // Needs Improvement
            HabitListCard(
                title: "Room for Improvement",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                habits: bottomHabits,
                allHabits: allHabitsWorst,
                emptyMessage: "All habits at 100%! Nothing needs improvement 🎉",
                showingAll: $showingAllBottom
            )
        }
        .padding(.horizontal)
    }
}

struct HabitListCard: View {
    let title: String
    let icon: String
    let color: Color
    let habits: [HabitStat]
    let allHabits: [HabitStat]
    let emptyMessage: String
    @Binding var showingAll: Bool
    
    private var hasMore: Bool {
        allHabits.count > habits.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            
            if habits.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(habits) { habit in
                    HabitStatRow(habit: habit, accentColor: color)
                }
                
                // Show More Button
                if hasMore {
                    Button {
                        showingAll = true
                    } label: {
                        HStack {
                            Text("Show All (\(allHabits.count))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(color)
                }
            }
        }
        .padding(DesignTokens.paddingStandard)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .sheet(isPresented: $showingAll) {
            AllHabitsSheet(
                title: title,
                icon: icon,
                color: color,
                habits: allHabits
            )
        }
    }
}

struct AllHabitsSheet: View {
    let title: String
    let icon: String
    let color: Color
    let habits: [HabitStat]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(habits) { habit in
                        HabitStatRow(habit: habit, accentColor: color)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}



struct HabitStatRow: View {
    let habit: HabitStat
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Consistency Badge in circular container (40x40)
            ZStack {
                Circle()
                    .fill(habit.consistencyRating.color.opacity(0.15))
                Text(habit.consistencyRating.icon)
                    .font(.title3)
            }
            .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("\(habit.completed)/\(habit.total) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Completion Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: habit.completionRate / 100)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(habit.completionRate))%")
                    .font(.caption2.bold())
            }
            .frame(width: 44, height: 44)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
