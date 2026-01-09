//
//  ProtocolWidget.swift
//  ProtocolWidget
//
//  Created on 2025-12-31.
//

import WidgetKit
import SwiftUI
import SQLite3
import AppIntents

// Lightweight molecule struct for widget display (no SwiftData)
struct SimpleMolecule: Identifiable {
    let id: UUID
    let title: String
    let time: Date
    let isCompleted: Bool
    let compound: String?
}

struct Provider: TimelineProvider {
    // App Group for shared database
    private static let appGroupIdentifier = "group.com.Toofan.Toofanprotocol.shared"
    
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), molecules: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let molecules = fetchMoleculesWithSQLite()
        let entry = SimpleEntry(date: Date(), molecules: molecules)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let molecules = fetchMoleculesWithSQLite()
        let entry = SimpleEntry(date: Date(), molecules: molecules)
        // Reload after 15 minutes
        let reloadDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(reloadDate))
        completion(timeline)
    }
    
    // MARK: - Lightweight SQLite Fetch (No SwiftData)
    
    /// Fetches today's molecules directly from SQLite without loading SwiftData stack
    private func fetchMoleculesWithSQLite() -> [SimpleMolecule] {
        guard let dbURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent("Protocol.sqlite") else {
            return []
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }
        
        var molecules: [SimpleMolecule] = []
        
        // Get today's date range as Apple's reference date (seconds since 2001-01-01)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        
        // Convert to Apple's Core Data reference date (2001-01-01)
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        let startInterval = todayStart.timeIntervalSince(referenceDate)
        let endInterval = todayEnd.timeIntervalSince(referenceDate)
        
        // SQL: Join instances with templates to get title and compound
        let sql = """
            SELECT 
                i.ZID,
                COALESCE(t.ZTITLE, 'Unknown') as title,
                i.ZSCHEDULEDDATE,
                i.ZISCOMPLETED,
                t.ZCOMPOUND
            FROM ZMOLECULEINSTANCE i
            LEFT JOIN ZMOLECULETEMPLATE t ON i.ZPARENTTEMPLATE = t.Z_PK
            WHERE i.ZSCHEDULEDDATE >= ? AND i.ZSCHEDULEDDATE < ?
              AND (i.ZISARCHIVED IS NULL OR i.ZISARCHIVED = 0)
            ORDER BY i.ZSCHEDULEDDATE ASC
            LIMIT 10
            """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_double(stmt, 1, startInterval)
        sqlite3_bind_double(stmt, 2, endInterval)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Parse UUID from blob or string
            var uuid: UUID = UUID()
            if let idBlob = sqlite3_column_blob(stmt, 0) {
                let idLength = sqlite3_column_bytes(stmt, 0)
                if idLength == 16 {
                    // UUID stored as 16-byte blob
                    let data = Data(bytes: idBlob, count: Int(idLength))
                    uuid = UUID(uuid: data.withUnsafeBytes { $0.load(as: uuid_t.self) })
                }
            }
            
            // Title
            let title: String
            if let titleCStr = sqlite3_column_text(stmt, 1) {
                title = String(cString: titleCStr)
            } else {
                title = "Unknown"
            }
            
            // Scheduled date (stored as TimeIntervalSinceReferenceDate)
            let scheduledInterval = sqlite3_column_double(stmt, 2)
            let scheduledDate = Date(timeIntervalSinceReferenceDate: scheduledInterval)
            
            // isCompleted (SQLite stores booleans as 0/1)
            let isCompleted = sqlite3_column_int(stmt, 3) != 0
            
            // Compound (optional)
            let compound: String?
            if let compoundCStr = sqlite3_column_text(stmt, 4) {
                compound = String(cString: compoundCStr)
            } else {
                compound = nil
            }
            
            molecules.append(SimpleMolecule(
                id: uuid,
                title: title,
                time: scheduledDate,
                isCompleted: isCompleted,
                compound: compound
            ))
        }
        
        return molecules
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let molecules: [SimpleMolecule]
}

struct ProtocolWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if entry.molecules.isEmpty {
                EmptyStateView()
            } else {
                switch family {
                case .systemSmall:
                    SmallWidgetView(molecules: entry.molecules)
                case .systemMedium:
                    MediumWidgetView(molecules: entry.molecules)
                case .systemLarge:
                    LargeWidgetView(molecules: entry.molecules)
                default:
                    MediumWidgetView(molecules: entry.molecules)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

// MARK: - Views

struct SmallWidgetView: View {
    let molecules: [SimpleMolecule]
    
    // Find next uncompleted, or last completed
    var displayMolecule: SimpleMolecule? {
        molecules.first(where: { !$0.isCompleted }) ?? molecules.last
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let habit = displayMolecule {
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.time.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(habit.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    if let compound = habit.compound {
                        Text(compound)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Toggle(isOn: habit.isCompleted, intent: ToggleHabitIntent(id: habit.id)) {
                    Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(habit.isCompleted ? .green : .gray)
                }
                .toggleStyle(ButtonToggleStyle())
                .tint(habit.isCompleted ? .green : .gray)
            } else {
                Text("All Done!")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumWidgetView: View {
    let molecules: [SimpleMolecule]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Habits")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text("\(molecules.filter { $0.isCompleted }.count)/\(molecules.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 0) {
                // Show up to 4 items
                ForEach(molecules.prefix(3)) { habit in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(habit.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .strikethrough(habit.isCompleted)
                                .foregroundStyle(habit.isCompleted ? .secondary : .primary)
                            
                            if !habit.isCompleted {
                                Text(habit.time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle(isOn: habit.isCompleted, intent: ToggleHabitIntent(id: habit.id)) {
                            Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(habit.isCompleted ? .green : .gray.opacity(0.3))
                        }
                        .toggleStyle(ButtonToggleStyle())
                        .frame(width: 44, height: 44)
                    }
                    if habit.id != molecules.prefix(3).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

struct LargeWidgetView: View {
    let molecules: [SimpleMolecule]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Habits")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(molecules.filter { $0.isCompleted }.count)/\(molecules.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 4) {
                ForEach(molecules.prefix(5)) { habit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .strikethrough(habit.isCompleted)
                                .foregroundStyle(habit.isCompleted ? .secondary : .primary)
                            
                            HStack(spacing: 8) {
                                Text(habit.time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                if let compound = habit.compound {
                                    Text(compound)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Toggle(isOn: habit.isCompleted, intent: ToggleHabitIntent(id: habit.id)) {
                            Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(habit.isCompleted ? .green : .gray.opacity(0.3))
                        }
                        .toggleStyle(ButtonToggleStyle())
                        .frame(width: 44, height: 44)
                    }
                    .padding(.vertical, 4)
                    
                    if habit.id != molecules.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text("No habits scheduled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@main
struct ProtocolWidget: Widget {
    let kind: String = "ProtocolWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ProtocolWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Protocol Today")
        .description("Track your daily habits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
