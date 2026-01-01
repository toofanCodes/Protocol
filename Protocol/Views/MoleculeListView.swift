//
//  MoleculeListView.swift
//  Protocol
//
//  Created on 2025-12-30.
//

import SwiftUI
import SwiftData

struct MoleculeListView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Query private var allInstances: [MoleculeInstance]
    @Environment(\.modelContext) private var modelContext
    
    // Selection for Bulk Actions
    @State private var selectedInstanceIds = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var showNukeConfirmation = false
    @State private var showDeleteConfirmation = false
    
    // Filtered and Grouped Data
    private var groupedInstances: [(Date, [MoleculeInstance])] {
        let filtered = allInstances.filter { viewModel.matchesFilter($0) }
        let grouped = Dictionary(grouping: filtered) { instance in
            Calendar.current.startOfDay(for: instance.scheduledDate)
        }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        List(selection: $selectedInstanceIds) {
            // "Nuke" Option (Debug Helper)
            if editMode == .active {
                Section {
                    Button(role: .destructive) {
                        showNukeConfirmation = true
                    } label: {
                        Label("Delete All Future Events", systemImage: "flame.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Debug Tools")
                }
            }
            
            ForEach(groupedInstances, id: \.0) { date, instances in
                Section(header: Text(date.formatted(date: .complete, time: .omitted))) {
                    ForEach(instances) { instance in
                        MoleculeListRow(instance: instance)
                            .tag(instance.id) // Essential for selection
                    }
                    .onDelete { indexSet in
                        deleteItems(at: indexSet, in: instances)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if editMode == .active {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedInstanceIds.isEmpty)
                    }
                    
                    EditButton()
                }
            }
        }
        .alert("Nuke Future Events?", isPresented: $showNukeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                nukeFutureEvents()
            }
        } message: {
            Text("This will permanently delete ALL instances scheduled after right now. This is useful for resetting bad data.")
        }
        .alert("Delete \(selectedInstanceIds.count) instance\(selectedInstanceIds.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
    
    // MARK: - Actions
    
    private func deleteItems(at offsets: IndexSet, in instances: [MoleculeInstance]) {
        for index in offsets {
            let instance = instances[index]
            modelContext.delete(instance)
        }
        try? modelContext.save()
    }
    
    private func deleteSelected() {
        // Fetch items to delete since we only have IDs
        // Or filter allInstances
        let toDelete = allInstances.filter { selectedInstanceIds.contains($0.id) }
        
        for instance in toDelete {
            modelContext.delete(instance)
        }
        
        try? modelContext.save()
        selectedInstanceIds.removeAll()
        editMode = .inactive
    }
    
    private func nukeFutureEvents() {
        let now = Date()
        let futureEvents = allInstances.filter { $0.scheduledDate > now }
        
        for instance in futureEvents {
            modelContext.delete(instance)
        }
        
        try? modelContext.save()
        editMode = .inactive
    }
}

// MARK: - Row View
struct MoleculeListRow: View {
    let instance: MoleculeInstance
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(instance.displayTitle)
                    .font(.body)
                    .strikethrough(instance.isCompleted)
                    .foregroundStyle(instance.isCompleted ? .secondary : .primary)
                
                if let notes = instance.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text(instance.scheduledDate.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if instance.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
