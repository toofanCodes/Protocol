//
//  InstanceManagementView.swift
//  Protocol
//
//  Created on 2025-12-31.
//

import SwiftUI
import SwiftData

struct InstanceManagementView: View {
    @Bindable var template: MoleculeTemplate
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedInstanceIds = Set<UUID>()
    @State private var isSelecting = false
    @State private var showDeleteConfirmation = false
    
    var sortedInstances: [MoleculeInstance] {
        template.instances.sorted { $0.scheduledDate < $1.scheduledDate }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Selection Toolbar (visible when selecting)
            if isSelecting {
                HStack {
                    Button(selectedInstanceIds.count == sortedInstances.count ? "Deselect All" : "Select All") {
                        if selectedInstanceIds.count == sortedInstances.count {
                            selectedInstanceIds.removeAll()
                        } else {
                            selectedInstanceIds = Set(sortedInstances.map(\.id))
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(selectedInstanceIds.count) of \(sortedInstances.count)")
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(selectedInstanceIds.isEmpty)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
            }
            
            // Instance List
            List {
                ForEach(sortedInstances) { instance in
                    HStack {
                        // Selection Circle
                        if isSelecting {
                            Image(systemName: selectedInstanceIds.contains(instance.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedInstanceIds.contains(instance.id) ? .blue : .gray)
                                .font(.title2)
                                .onTapGesture {
                                    toggleSelection(instance.id)
                                }
                        }
                        
                        VStack(alignment: .leading) {
                            Text(instance.scheduledDate.formatted(date: .complete, time: .shortened))
                                .font(.body)
                            
                            Text(instance.isCompleted ? "Completed" : "Pending")
                                .font(.caption)
                                .foregroundStyle(instance.isCompleted ? .green : .secondary)
                        }
                        
                        Spacer()
                        
                        if instance.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelecting {
                            toggleSelection(instance.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage Instances")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedInstanceIds.removeAll()
                        }
                    }
                }
            }
        }
        .alert("Delete \(selectedInstanceIds.count) instances?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("These instances will be permanently removed. This cannot be undone.")
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedInstanceIds.contains(id) {
            selectedInstanceIds.remove(id)
        } else {
            selectedInstanceIds.insert(id)
        }
    }
    
    private func deleteSelected() {
        let instancesToDelete = template.instances.filter { selectedInstanceIds.contains($0.id) }
        
        for instance in instancesToDelete {
            modelContext.delete(instance)
        }
        
        try? modelContext.save()
        selectedInstanceIds.removeAll()
        
        if template.instances.isEmpty {
            isSelecting = false
            dismiss()
        }
    }
}
