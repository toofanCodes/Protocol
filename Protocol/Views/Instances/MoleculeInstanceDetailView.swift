//
//  MoleculeInstanceDetailView.swift
//  Protocol
//
//  Extracted from ContentView.swift on 2026-01-08.
//

import SwiftUI
import SwiftData

struct MoleculeInstanceDetailView: View {
    @Bindable var instance: MoleculeInstance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var celebrationState: CelebrationState
    @Query(sort: \MoleculeTemplate.title) private var templates: [MoleculeTemplate]
    
    @State private var atomForValueEntry: AtomInstance?
    @State private var atomForWorkoutLog: AtomInstance?
    @State private var showingRescheduleSheet = false
    @State private var rescheduleDate: Date = Date()
    
    
    
    private var service: MoleculeService {
        MoleculeService(modelContext: modelContext)
    }
    
    private var sortedAtoms: [AtomInstance] {
        instance.atomInstances.sorted { $0.order < $1.order }
    }
    
    private var completedCount: Int {
        instance.atomInstances.filter(\.isCompleted).count
    }
    
    private var progress: Double {
        guard !instance.atomInstances.isEmpty else { return 0 }
        return Double(completedCount) / Double(instance.atomInstances.count)
    }
    
    var body: some View {
        List {
            // Progress Section
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("\(completedCount)/\(instance.atomInstances.count) completed")
                        .font(.headline)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(progress == 1 ? .green : .primary)
                    }
                    
                    ProgressView(value: progress)
                    .tint(progress == 1 ? Color.green : Color.accentColor)
                }
                .padding(.vertical, 4)
            }
            
            // Tasks Section
            Section("Tasks") {
                if sortedAtoms.isEmpty {
                    Text("No tasks")
                    .foregroundStyle(.secondary)
                    .italic()
                } else {
                    ForEach(sortedAtoms) { atom in
                        AtomInstanceRowView(atom: atom)
                        .onTapGesture {
                            handleAtomTap(atom)
                        }
                    }
                }
            }
            
            // Info Section
            Section("Info") {
                Picker("Molecule", selection: $instance.parentTemplate) {
                    Text("Unassigned").tag(nil as MoleculeTemplate?)
                    ForEach(templates) { template in
                        Text(template.title).tag(template as MoleculeTemplate?)
                    }
                }
                
                LabeledContent("Scheduled", value: instance.formattedDate)
                
                if instance.isException {
                    LabeledContent("Status", value: "Modified")
                    .foregroundStyle(.orange)
                }
                
                if let completedAt = instance.completedAt {
                    LabeledContent("Completed At") {
                        Text(completedAt, style: .time)
                    }
                }
            }
            
            // Reschedule Section
            if !instance.isCompleted {
                Section("Reschedule") {
                    Button {
                        postponeToTomorrow()
                    } label: {
                        Label("Postpone to Tomorrow", systemImage: "arrow.forward.circle")
                    }
                    
                    Button {
                        rescheduleDate = instance.scheduledDate
                        showingRescheduleSheet = true
                    } label: {
                        Label("Pick a Different Date", systemImage: "calendar")
                    }
                }
            }
        }
        .navigationTitle(instance.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $atomForValueEntry) { atom in
            AtomValueEntrySheet(atom: atom)
        }
        .sheet(item: $atomForWorkoutLog) { atom in
            AtomDetailSheet(atom: atom)
        }
        .sheet(isPresented: $showingRescheduleSheet) {
            NavigationStack {
                Form {
                    DatePicker(
                        "New Date",
                        selection: $rescheduleDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }
                .navigationTitle("Reschedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingRescheduleSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            rescheduleInstance(to: rescheduleDate)
                            showingRescheduleSheet = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        
        .onChange(of: sortedAtoms.map(\.isCompleted)) { oldValue, newValue in
            // Detect TRANSITION from <100% to 100%
            let wasAllCompleted = !oldValue.isEmpty && oldValue.allSatisfy { $0 }
            let isNowAllCompleted = !newValue.isEmpty && newValue.allSatisfy { $0 }
            
            if !wasAllCompleted && isNowAllCompleted {
                // Mark instance complete if not already
                if !instance.isCompleted {
                    instance.markComplete()
                    try? modelContext.save()
                }
                NotificationManager.shared.cancelNotification(for: instance)
                
                // Dismiss sheet first, then trigger celebration after a short delay
                let themeColor = instance.parentTemplate?.themeColor
                dismiss()
                
                // BOOM! Trigger celebration after sheet dismissal (0.5s delay)
                celebrationState.triggerMoleculeCompletion(themeColor: themeColor, delay: 0.5)
                
                // Check for Perfect Day (wait until molecule celebration is underway ~1.5s total)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let todayInstances = fetchTodayInstances()
                    celebrationState.checkPerfectDay(todayInstances: todayInstances, delay: 0)
                }
            } else if !isNowAllCompleted && instance.isCompleted {
                instance.markIncomplete()
                try? modelContext.save()
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Fetches all MoleculeInstances scheduled for today
    private func fetchTodayInstances() -> [MoleculeInstance] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate<MoleculeInstance> { instance in
                instance.scheduledDate >= startOfDay && instance.scheduledDate < endOfDay && instance.isArchived == false
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Actions
    
    private func handleAtomTap(_ atom: AtomInstance) {
        switch atom.inputType {
        case .binary:
            // Binary atoms toggle directly from the row
            break
            
        case .counter:
            // Counter atoms can use the row controls, but also open detail for notes
            if atom.targetReps != nil || atom.notes != nil {
                atomForWorkoutLog = atom
            }
            
        case .value:
            // Check if this is a workout exercise (has sets/reps)
            if atom.isWorkoutExercise {
                atomForWorkoutLog = atom
            } else {
                atomForValueEntry = atom
            }
        }
    }
    
    private func postponeToTomorrow() {
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: instance.scheduledDate) {
            rescheduleInstance(to: tomorrow)
        }
    }
    
    private func rescheduleInstance(to newDate: Date) {
        // Store original date for tracking
        if instance.originalScheduledDate == nil {
            instance.originalScheduledDate = instance.scheduledDate
        }
        
        instance.scheduledDate = newDate
        instance.isException = true
        instance.exceptionTime = newDate
        instance.updatedAt = Date()
        
        try? modelContext.save()
        
        // Reschedule notifications
        Task {
            await NotificationManager.shared.scheduleNotifications(for: instance)
        }
    }
}
