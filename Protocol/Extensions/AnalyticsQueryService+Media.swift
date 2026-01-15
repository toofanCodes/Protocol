//
//  AnalyticsQueryService+Media.swift
//  Protocol
//
//  Extension for snoring and media capture analytics queries.
//

import Foundation
import SwiftData

// MARK: - Snoring Day Data

/// Data for a single day's snoring analysis
struct SnoringDayData: Identifiable {
    var id: Date { date }
    let date: Date
    let score: Double
    let eventCount: Int
    let totalDuration: TimeInterval?
}

// MARK: - Analytics Extension

extension AnalyticsQueryService {
    
    // MARK: - Snoring Trends
    
    /// Returns snoring data for each day in the date range
    func snoringTrends(from: Date, to: Date) -> [SnoringDayData] {
        let calendar = Calendar.current
        let startOfFrom = calendar.startOfDay(for: from)
        let endOfTo = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))!
        
        // Fetch all atom instances with audio media captures in range
        let descriptor = FetchDescriptor<AtomInstance>(
            predicate: #Predicate<AtomInstance> { instance in
                instance.completedAt != nil &&
                instance.mediaCapture != nil
            },
            sortBy: [SortDescriptor(\AtomInstance.completedAt)]
        )
        
        guard let instances = try? modelContext.fetch(descriptor) else {
            return []
        }
        
        // Filter for audio captures in date range and group by date
        let filteredInstances = instances.filter { instance in
            guard let completedAt = instance.completedAt else { return false }
            return completedAt >= startOfFrom && completedAt < endOfTo
        }
        
        // Filter for audio captures and group by date
        var dayData: [Date: (scores: [Double], events: [Int], durations: [TimeInterval?])] = [:]
        
        for instance in filteredInstances {
            guard let capture = instance.mediaCapture,
                  capture.captureType == "audio",
                  let completedAt = instance.completedAt else {
                continue
            }
            
            let date = calendar.startOfDay(for: completedAt)
            var data = dayData[date] ?? ([], [], [])
            
            if let score = capture.snoringScore {
                data.scores.append(score)
            }
            if let events = capture.snoringEventCount {
                data.events.append(events)
            }
            data.durations.append(capture.totalSnoringDuration)
            
            dayData[date] = data
        }
        
        // Convert to SnoringDayData
        return dayData.map { date, data in
            let avgScore = data.scores.isEmpty ? 0 : data.scores.reduce(0, +) / Double(data.scores.count)
            let totalEvents = data.events.reduce(0, +)
            let totalDuration = data.durations.compactMap { $0 }.reduce(0, +)
            
            return SnoringDayData(
                date: date,
                score: avgScore,
                eventCount: totalEvents,
                totalDuration: totalDuration > 0 ? totalDuration : nil
            )
        }
        .sorted { $0.date < $1.date }
    }
    
    // MARK: - Aggregate Queries
    
    /// Returns the average snoring score for a date range
    func averageSnoringScore(from: Date, to: Date) -> Double {
        let trends = snoringTrends(from: from, to: to)
        guard !trends.isEmpty else { return 0 }
        return trends.map(\.score).reduce(0, +) / Double(trends.count)
    }
    
    /// Returns the total snoring time in the date range
    func totalSnoringTime(from: Date, to: Date) -> TimeInterval {
        let trends = snoringTrends(from: from, to: to)
        return trends.compactMap(\.totalDuration).reduce(0, +)
    }
    
    /// Returns the total number of snoring events in the date range
    func totalSnoringEvents(from: Date, to: Date) -> Int {
        let trends = snoringTrends(from: from, to: to)
        return trends.map(\.eventCount).reduce(0, +)
    }
    
    /// Returns the number of nights tracked in the date range
    func trackedNightsCount(from: Date, to: Date) -> Int {
        snoringTrends(from: from, to: to).count
    }
    
    // MARK: - Heatmap Data
    
    /// Returns snoring scores for calendar heatmap (score per day)
    func snoringHeatmap(from: Date, to: Date) -> [Date: Double] {
        let trends = snoringTrends(from: from, to: to)
        var result: [Date: Double] = [:]
        
        for data in trends {
            result[data.date] = data.score
        }
        
        return result
    }
    
    // MARK: - Media Capture Stats
    
    /// Returns count of each media capture type
    func mediaCaptureStats() -> (photos: Int, videos: Int, audioSessions: Int) {
        let descriptor = FetchDescriptor<MediaCapture>()
        
        guard let captures = try? modelContext.fetch(descriptor) else {
            return (0, 0, 0)
        }
        
        var photos = 0
        var videos = 0
        var audio = 0
        
        for capture in captures {
            switch capture.captureType {
            case "photo": photos += 1
            case "video": videos += 1
            case "audio": audio += 1
            default: break
            }
        }
        
        return (photos, videos, audio)
    }
}
