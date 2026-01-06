//
//  ArchivedMoleculesView.swift
//  Protocol
//
//  View for managing archived (soft-deleted) molecules.
//

import SwiftUI
import SwiftData

struct ArchivedMoleculesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MoleculeTemplate> { $0.isArchived }) 
    private var archivedTemplates: [MoleculeTemplate]
    
    @State private var selectedForDeletion: Set<PersistentIdentifier> = []
    @State private var showingDeleteConfirmation = false
    @State private var isEditing = false
    
    private var sortedTemplates: [MoleculeTemplate] {
        archivedTemplates.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var body: some View {
        List {
            if archivedTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No Archived Molecules", systemImage: "archivebox")
                } description: {
                    Text("Archived molecules will appear here")
                }
            } else {
                ForEach(sortedTemplates) { template in
                    HStack(spacing: 12) {
                        // Selection checkbox when editing
                        if isEditing {
                            Button {
                                toggleSelection(template)
                            } label: {
                                Image(systemName: selectedForDeletion.contains(template.persistentModelID) 
                                      ? "checkmark.circle.fill" 
                                      : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selectedForDeletion.contains(template.persistentModelID) 
                                                     ? .blue 
                                                     : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        AvatarView(molecule: template, size: 44)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title)
                                .font(.headline)
                            Text("Archived \(template.updatedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditing {
                            toggleSelection(template)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !isEditing {
                            Button {
                                restoreTemplate(template)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !isEditing {
                            Button(role: .destructive) {
                                permanentlyDeleteTemplate(template)
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Archived Molecules")
        .toolbar {
            if !archivedTemplates.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Done" : "Select") {
                        withAnimation {
                            isEditing.toggle()
                            if !isEditing {
                                selectedForDeletion.removeAll()
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing && !selectedForDeletion.isEmpty {
                HStack {
                    Text("\(selectedForDeletion.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        bulkRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .alert("Permanently Delete?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Forever", role: .destructive) {
                bulkPermanentDelete()
            }
        } message: {
            Text("This will permanently delete \(selectedForDeletion.count) molecule(s). This cannot be undone.")
        }
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ template: MoleculeTemplate) {
        if selectedForDeletion.contains(template.persistentModelID) {
            selectedForDeletion.remove(template.persistentModelID)
        } else {
            selectedForDeletion.insert(template.persistentModelID)
        }
    }
    
    private func restoreTemplate(_ template: MoleculeTemplate) {
        template.isArchived = false
        template.updatedAt = Date()
        try? modelContext.save()
        
        Task {
            await AuditLogger.shared.logUpdate(
                entityType: .moleculeTemplate,
                entityId: template.id.uuidString,
                entityName: template.title,
                changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                additionalInfo: "Restored from Archive"
            )
        }
    }
    
    private func permanentlyDeleteTemplate(_ template: MoleculeTemplate) {
        Task {
            await AuditLogger.shared.logDelete(
                entityType: .moleculeTemplate,
                entityId: template.id.uuidString,
                entityName: template.title,
                additionalInfo: "Permanently deleted from Archive"
            )
        }
        
        modelContext.delete(template)
        try? modelContext.save()
    }
    
    private func bulkRestore() {
        for id in selectedForDeletion {
            if let template = archivedTemplates.first(where: { $0.persistentModelID == id }) {
                restoreTemplate(template)
            }
        }
        selectedForDeletion.removeAll()
        withAnimation {
            isEditing = false
        }
    }
    
    private func bulkPermanentDelete() {
        for id in selectedForDeletion {
            if let template = archivedTemplates.first(where: { $0.persistentModelID == id }) {
                permanentlyDeleteTemplate(template)
            }
        }
        selectedForDeletion.removeAll()
        withAnimation {
            isEditing = false
        }
    }
}

#Preview {
    NavigationStack {
        ArchivedMoleculesView()
    }
}
