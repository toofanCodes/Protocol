//
//  SleepAnalyticsView.swift
//  Protocol
//
//  Dashboard view for sleep tracking and snoring analysis.
//

import SwiftUI
import SwiftData
import Charts

struct SleepAnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(
        filter: #Predicate<AtomInstance> { instance in
            instance.mediaCapture != nil
        },
        sort: \AtomInstance.completedAt,
        order: .reverse
    ) private var sessionsWithMedia: [AtomInstance]
    
    @State private var selectedTimeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case quarter = "90 Days"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Time range picker
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Summary cards
                    summarySection
                    
                    // Snoring trend chart
                    if !filteredSessions.isEmpty {
                        snoringTrendChart
                    }
                    
                    // Recent sessions list
                    recentSessionsSection
                }
                .padding(.vertical)
            }
            .navigationTitle("Sleep Analytics")
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredSessions: [AtomInstance] {
        let days: Int
        switch selectedTimeRange {
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        }
        
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        
        return sessionsWithMedia.filter { session in
            guard let capture = session.mediaCapture,
                  capture.captureType == "audio",
                  let completedAt = session.completedAt else {
                return false
            }
            return completedAt >= cutoff
        }
    }
    
    private var averageScore: Double {
        let scores = filteredSessions.compactMap { $0.mediaCapture?.snoringScore }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    private var totalEvents: Int {
        filteredSessions.compactMap { $0.mediaCapture?.snoringEventCount }.reduce(0, +)
    }
    
    private var averageEventsPerNight: Double {
        guard !filteredSessions.isEmpty else { return 0 }
        return Double(totalEvents) / Double(filteredSessions.count)
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            summaryCard(
                title: "Avg Score",
                value: "\(Int(averageScore))%",
                icon: "percent",
                color: scoreColor(averageScore)
            )
            
            summaryCard(
                title: "Events/Night",
                value: String(format: "%.1f", averageEventsPerNight),
                icon: "waveform",
                color: .purple
            )
            
            summaryCard(
                title: "Sessions",
                value: "\(filteredSessions.count)",
                icon: "moon.zzz.fill",
                color: .blue
            )
        }
        .padding(.horizontal)
    }
    
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2.bold())
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Trend Chart
    
    private var snoringTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snoring Score Trend")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                ForEach(chartData, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(scoreColor(item.score))
                }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: selectedTimeRange == .week ? 1 : 7)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private var chartData: [(date: Date, score: Double)] {
        filteredSessions.compactMap { session in
            guard let date = session.completedAt,
                  let score = session.mediaCapture?.snoringScore else {
                return nil
            }
            return (date: date, score: score)
        }
        .sorted { $0.date < $1.date }
    }
    
    // MARK: - Recent Sessions
    
    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            if filteredSessions.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSessions.prefix(10)) { session in
                        if let capture = session.mediaCapture {
                            NavigationLink {
                                MediaCaptureDetailView(capture: capture)
                            } label: {
                                sessionRow(session: session, capture: capture)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func sessionRow(session: AtomInstance, capture: MediaCapture) -> some View {
        HStack {
            // Score indicator
            ZStack {
                Circle()
                    .fill(scoreColor(capture.snoringScore ?? 0).opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Text("\(Int(capture.snoringScore ?? 0))")
                    .font(.caption.bold())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline.bold())
                
                if let date = session.completedAt {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let events = capture.snoringEventCount, events > 0 {
                    Text("\(events) events")
                        .font(.caption)
                }
                
                if let duration = capture.durationString {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text("No Sleep Data")
                .font(.headline)
            
            Text("Start tracking your sleep to see analytics here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Helpers
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0..<20: return .green
        case 20..<40: return .mint
        case 40..<60: return .yellow
        case 60..<80: return .orange
        default: return .red
        }
    }
}

#Preview {
    SleepAnalyticsView()
        .modelContainer(for: [AtomInstance.self, MediaCapture.self])
}
