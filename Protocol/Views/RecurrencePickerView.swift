//
//  RecurrencePickerView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI

/// A comprehensive picker for configuring recurrence settings
struct RecurrencePickerView: View {
    @Binding var frequency: RecurrenceFrequency
    @Binding var customDays: [Int]
    @Binding var endRuleType: RecurrenceEndRuleType
    @Binding var endDate: Date?
    @Binding var endCount: Int?
    
    @Environment(\.dismiss) private var dismiss
    
    // Local state for editing
    @State private var localFrequency: RecurrenceFrequency
    @State private var localDays: [Int]
    @State private var localEndRuleType: RecurrenceEndRuleType
    @State private var localEndDate: Date
    @State private var localEndCount: Int
    
    init(
        frequency: Binding<RecurrenceFrequency>,
        customDays: Binding<[Int]>,
        endRuleType: Binding<RecurrenceEndRuleType>,
        endDate: Binding<Date?>,
        endCount: Binding<Int?>
    ) {
        self._frequency = frequency
        self._customDays = customDays
        self._endRuleType = endRuleType
        self._endDate = endDate
        self._endCount = endCount
        
        self._localFrequency = State(initialValue: frequency.wrappedValue)
        self._localDays = State(initialValue: customDays.wrappedValue)
        self._localEndRuleType = State(initialValue: endRuleType.wrappedValue)
        self._localEndDate = State(initialValue: endDate.wrappedValue ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())!)
        self._localEndCount = State(initialValue: endCount.wrappedValue ?? 10)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Frequency Section
                Section {
                    frequencyPresetPicker
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(frequencyDescription)
                }
                
                // Custom Days Section
                if localFrequency == .custom {
                    Section("Select Days") {
                        CustomDayPickerView(selectedDays: $localDays)
                    }
                }
                
                // End Rule Section
                Section {
                    Picker("Ends", selection: $localEndRuleType) {
                        Text("Never").tag(RecurrenceEndRuleType.never)
                        Text("On Date").tag(RecurrenceEndRuleType.onDate)
                        Text("After Occurrences").tag(RecurrenceEndRuleType.afterOccurrences)
                    }
                    .pickerStyle(.segmented)
                    
                    switch localEndRuleType {
                    case .never:
                        EmptyView()
                        
                    case .onDate:
                        DatePicker(
                            "End Date",
                            selection: $localEndDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        
                    case .afterOccurrences:
                        Stepper(value: $localEndCount, in: 1...365) {
                            Text("After \(localEndCount) times")
                        }
                    }
                } header: {
                    Text("End Rule")
                }
                
                // Summary Section
                Section("Summary") {
                    Text(summaryText)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Frequency Preset Picker
    
    private var frequencyPresetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(RecurrenceFrequency.allCases) { freq in
                Button {
                    localFrequency = freq
                    if freq != .custom {
                        localDays = []
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(freq.displayName)
                                .foregroundStyle(.primary)
                            Text(freq.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if localFrequency == freq {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                if freq != .custom {
                    Divider()
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var frequencyDescription: String {
        switch localFrequency {
        case .daily:
            return "This molecule will appear every day."
        case .weekly:
            return "This molecule will appear once a week."
        case .monthly:
            return "This molecule will appear once a month."
        case .custom:
            if localDays.isEmpty {
                return "Select which days of the week to repeat."
            } else {
                return "Repeats on: \(localDays.daysDescription)"
            }
        }
    }
    
    private var summaryText: String {
        var parts: [String] = []
        
        // Frequency
        switch localFrequency {
        case .daily:
            parts.append("Repeats every day")
        case .weekly:
            parts.append("Repeats every week")
        case .monthly:
            parts.append("Repeats every month")
        case .custom:
            if localDays.isEmpty {
                parts.append("Select days to repeat")
            } else {
                let dayNames = localDays.sorted().map { DayOfWeek(rawValue: $0).fullName }
                parts.append("Repeats on \(dayNames.joined(separator: ", "))")
            }
        }
        
        // End rule
        switch localEndRuleType {
        case .never:
            parts.append("with no end date")
        case .onDate:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append("until \(formatter.string(from: localEndDate))")
        case .afterOccurrences:
            parts.append("for \(localEndCount) occurrences")
        }
        
        return parts.joined(separator: " ")
    }
    
    // MARK: - Actions
    
    private func saveAndDismiss() {
        frequency = localFrequency
        customDays = localDays
        endRuleType = localEndRuleType
        
        switch localEndRuleType {
        case .never:
            endDate = nil
            endCount = nil
        case .onDate:
            endDate = localEndDate
            endCount = nil
        case .afterOccurrences:
            endDate = nil
            endCount = localEndCount
        }
        
        dismiss()
    }
}

// MARK: - Custom Day Picker View

struct CustomDayPickerView: View {
    @Binding var selectedDays: [Int]
    
    private let days = DayOfWeek.allDays
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(days) { day in
                let isSelected = selectedDays.contains(day.rawValue)
                
                Button {
                    toggleDay(day.rawValue)
                } label: {
                    Text(day.shortName)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(width: 36, height: 36)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func toggleDay(_ day: Int) {
        if let index = selectedDays.firstIndex(of: day) {
            selectedDays.remove(at: index)
        } else {
            selectedDays.append(day)
            selectedDays.sort()
        }
    }
}

// MARK: - RecurrenceFrequency Extension

extension RecurrenceFrequency {
    var subtitle: String {
        switch self {
        case .daily:
            return "Every day"
        case .weekly:
            return "Once a week"
        case .monthly:
            return "Once a month"
        case .custom:
            return "Choose specific days"
        }
    }
}

// MARK: - Preview

#Preview {
    RecurrencePickerView(
        frequency: .constant(.daily),
        customDays: .constant([]),
        endRuleType: .constant(.never),
        endDate: .constant(nil),
        endCount: .constant(nil)
    )
}
