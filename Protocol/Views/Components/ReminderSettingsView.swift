//
//  ReminderSettingsView.swift
//  Protocol
//
//  Reusable component for configuring alert offsets (multiple reminders)
//

import SwiftUI

/// View for configuring reminder alerts before an event
struct ReminderSettingsView: View {
    @Binding var alertOffsets: [Int]
    
    // MARK: - Preset Options
    
    private struct AlertOption: Identifiable {
        let id = UUID()
        let minutes: Int
        let label: String
        
        static let presets: [AlertOption] = [
            AlertOption(minutes: 0, label: "At time of event"),
            AlertOption(minutes: 5, label: "5 minutes before"),
            AlertOption(minutes: 10, label: "10 minutes before"),
            AlertOption(minutes: 15, label: "15 minutes before"),
            AlertOption(minutes: 30, label: "30 minutes before"),
            AlertOption(minutes: 60, label: "1 hour before"),
            AlertOption(minutes: 120, label: "2 hours before"),
            AlertOption(minutes: 1440, label: "1 day before")
        ]
    }
    
    // MARK: - Body
    
    var body: some View {
        Section {
            // Current alerts list
            ForEach(sortedOffsets, id: \.self) { offset in
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.orange)
                    Text(displayString(for: offset))
                    Spacer()
                }
            }
            .onDelete(perform: deleteOffsets)
            
            // Add alert menu
            Menu {
                ForEach(availablePresets) { preset in
                    Button {
                        addAlert(minutes: preset.minutes)
                    } label: {
                        Label(preset.label, systemImage: "bell.badge.plus")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text("Add Alert")
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if alertOffsets.isEmpty {
                Text("No reminders set. Tap 'Add Alert' to receive notifications.")
            } else {
                Text("\(alertOffsets.count) reminder\(alertOffsets.count == 1 ? "" : "s") will be sent.")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var sortedOffsets: [Int] {
        alertOffsets.sorted()
    }
    
    private var availablePresets: [AlertOption] {
        AlertOption.presets.filter { !alertOffsets.contains($0.minutes) }
    }
    
    // MARK: - Actions
    
    private func addAlert(minutes: Int) {
        guard !alertOffsets.contains(minutes) else { return }
        alertOffsets.append(minutes)
        alertOffsets.sort()
    }
    
    private func deleteOffsets(at indexSet: IndexSet) {
        let sorted = sortedOffsets
        let toRemove = indexSet.map { sorted[$0] }
        alertOffsets.removeAll { toRemove.contains($0) }
    }
    
    // MARK: - Helpers
    
    private func displayString(for minutes: Int) -> String {
        switch minutes {
        case 0:
            return "At time of event"
        case 1...59:
            return "\(minutes) minute\(minutes == 1 ? "" : "s") before"
        case 60:
            return "1 hour before"
        case 61...1439:
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") before"
            }
            return "\(hours)h \(mins)m before"
        case 1440:
            return "1 day before"
        default:
            let days = minutes / 1440
            return "\(days) day\(days == 1 ? "" : "s") before"
        }
    }
}

// MARK: - Preview

#Preview {
    Form {
        ReminderSettingsView(alertOffsets: .constant([15, 60]))
    }
}
