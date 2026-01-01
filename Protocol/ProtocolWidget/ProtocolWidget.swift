//
//  ProtocolWidget.swift
//  ProtocolWidget
//
//  Created on 2025-12-31.
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

struct SimpleMolecule: Identifiable {
    let id: UUID
    let title: String
    let time: Date
    let isCompleted: Bool
    let compound: String?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), molecules: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        Task { @MainActor in
            let molecules = fetchKeyMolecules()
            let entry = SimpleEntry(date: Date(), molecules: molecules)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task { @MainActor in
            let molecules = fetchKeyMolecules()
            let entry = SimpleEntry(date: Date(), molecules: molecules)
            // Reload after 15 minutes or when data changes
            let reloadDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(reloadDate))
            completion(timeline)
        }
    }
    
    @MainActor
    private func fetchKeyMolecules() -> [SimpleMolecule] {
        let context = DataController.shared.container.mainContext
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate<MoleculeInstance> {
                $0.scheduledDate >= todayStart && $0.scheduledDate < todayEnd
            },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        
        guard let instances = try? context.fetch(descriptor) else { return [] }
        
        // Filter out completed ones or keep them based on design?
        // Proposal says "Toggle/Button". We should show both but maybe sort uncompleted first.
        
        return instances.map { instance in
            SimpleMolecule(
                id: instance.id,
                title: instance.parentTemplate?.title ?? "Unknown",
                time: instance.scheduledDate,
                isCompleted: instance.isCompleted,
                compound: instance.parentTemplate?.compound
            )
        }
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
                ForEach(molecules.prefix(4)) { habit in
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
                    if habit.id != molecules.prefix(4).last?.id {
                        Divider()
                    }
                }
            }
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
