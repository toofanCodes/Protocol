//
//  MoleculeInstanceDetailView.swift
//  Protocol
//
//  Extracted from ContentView.swift on 2026-01-08.
//

import SwiftUI
import SwiftData

struct MoleculeInstanceDetailView: View {
    @StateObject private var viewModel: MoleculeInstanceDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var celebrationState: CelebrationState
    @Query(sort: \MoleculeTemplate.title) private var templates: [MoleculeTemplate]
    
    init(instance: MoleculeInstance) {
        _viewModel = StateObject(wrappedValue: MoleculeInstanceDetailViewModel(instance: instance))
    }
    
    var body: some View {
        List {
            // Progress Section
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("\(viewModel.completedCount)/\(viewModel.instance.atomInstances.count) completed")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(viewModel.progress == 1 ? .green : .primary)
                    }
                    
                    ProgressView(value: viewModel.progress)
                        .tint(viewModel.progress == 1 ? Color.green : Color.accentColor)
                }
                .padding(.vertical, 4)
            }
            
            // Tasks Section
            Section("Tasks") {
                if viewModel.sortedAtoms.isEmpty {
                    Text("No tasks")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(viewModel.sortedAtoms) { atom in
                        AtomInstanceRowView(atom: atom)
                            .onTapGesture {
                                viewModel.handleAtomTap(atom, context: modelContext)
                            }
                    }
                }
            }
            
            // Info Section
            Section("Info") {
                Picker("Molecule", selection: $viewModel.instance.parentTemplate) {
                    Text("Unassigned").tag(nil as MoleculeTemplate?)
                    ForEach(templates) { template in
                        Text(template.title).tag(template as MoleculeTemplate?)
                    }
                }
                
                LabeledContent("Scheduled", value: viewModel.instance.formattedDate)
                
                if viewModel.instance.isException {
                    LabeledContent("Status", value: "Modified")
                        .foregroundStyle(.orange)
                }
                
                if let completedAt = viewModel.instance.completedAt {
                    LabeledContent("Completed At") {
                        Text(completedAt, style: .time)
                    }
                }
            }
            
            // Reschedule Section
            if !viewModel.instance.isCompleted {
                Section("Reschedule") {
                    Button {
                        viewModel.postponeToTomorrow(context: modelContext)
                    } label: {
                        Label("Postpone to Tomorrow", systemImage: "arrow.forward.circle")
                    }
                    
                    Button {
                        viewModel.rescheduleDate = viewModel.instance.scheduledDate
                        viewModel.showingRescheduleSheet = true
                    } label: {
                        Label("Pick a Different Date", systemImage: "calendar")
                    }
                }
            }
        }
        .navigationTitle(viewModel.instance.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.atomForValueEntry) { atom in
            AtomValueEntrySheet(atom: atom)
        }
        .sheet(item: $viewModel.atomForWorkoutLog) { atom in
            AtomDetailSheet(atom: atom)
        }
        .sheet(isPresented: $viewModel.showingRescheduleSheet) {
            NavigationStack {
                Form {
                    DatePicker(
                        "New Date",
                        selection: $viewModel.rescheduleDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }
                .navigationTitle("Reschedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.showingRescheduleSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            viewModel.rescheduleInstance(to: viewModel.rescheduleDate, context: modelContext)
                            viewModel.showingRescheduleSheet = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        
        .onChange(of: viewModel.sortedAtoms.map(\.isCompleted)) { oldCompleted, newCompleted in
            // Detect TRANSITION from <100% to 100%
            let wasAllCompleted = !oldCompleted.isEmpty && oldCompleted.allSatisfy { $0 }
            let isNowAllCompleted = !newCompleted.isEmpty && newCompleted.allSatisfy { $0 }
            
            if !wasAllCompleted && isNowAllCompleted {
                // Mark instance complete if not already
                if !viewModel.instance.isCompleted {
                    viewModel.instance.markComplete()
                    try? modelContext.save()
                }
                NotificationManager.shared.cancelNotification(for: viewModel.instance)
                
                // Dismiss and celebrate
                let themeColor = viewModel.instance.parentTemplate?.themeColor
                dismiss()
                celebrationState.triggerMoleculeCompletion(themeColor: themeColor, delay: 0.5)
                
                // Check for Perfect Day
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let todayInstances = fetchTodayInstances()
                    celebrationState.checkPerfectDay(todayInstances: todayInstances, delay: 0)
                }
            } else if !isNowAllCompleted && viewModel.instance.isCompleted {
                viewModel.instance.markIncomplete()
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
}
