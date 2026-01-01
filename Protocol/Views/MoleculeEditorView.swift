//
//  MoleculeEditorView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

/// Editor view for MoleculeInstance with "Series vs. Instance" modification logic.
/// Implements the Apple Calendar standard: when editing a recurring event,
/// the user is prompted to choose between "This Event Only" or "All Future Events".
struct MoleculeEditorView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    @Bindable var instance: MoleculeInstance
    
    // MARK: - State
    
    @State private var editedTitle: String = ""
    @State private var editedTime: Date = Date()
    @State private var editedNotes: String = ""
    
    @State private var showingSaveActionSheet = false
    @State private var showingDeleteActionSheet = false
    @State private var hasChanges = false
    
    // MARK: - Computed Properties
    
    private var isPartOfSeries: Bool {
        instance.parentTemplate != nil
    }
    
    private var service: MoleculeService {
        MoleculeService(modelContext: modelContext)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // Instance Info Section
                Section("Event Details") {
                    TextField("Title", text: $editedTitle)
                        .onChange(of: editedTitle) { _, _ in
                            checkForChanges()
                        }
                    
                    DatePicker(
                        "Time",
                        selection: $editedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: editedTime) { _, _ in
                        checkForChanges()
                    }
                    
                    DatePicker(
                        "Date",
                        selection: $editedTime,
                        displayedComponents: .date
                    )
                    .disabled(true) // Date is fixed for instances
                }
                
                // Notes Section
                Section("Notes") {
                    TextEditor(text: $editedNotes)
                        .frame(minHeight: 100)
                        .onChange(of: editedNotes) { _, _ in
                            checkForChanges()
                        }
                }
                
                // Series Info (if part of a series)
                if let template = instance.parentTemplate {
                    Section("Series Info") {
                        LabeledContent("Series Title", value: template.title)
                        LabeledContent("Recurrence", value: template.recurrenceDescription)
                        
                        if instance.isException {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("This event has been modified from the series")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Completion Status
                Section {
                    Toggle("Completed", isOn: Binding(
                        get: { instance.isCompleted },
                        set: { newValue in
                            if newValue {
                                instance.markComplete()
                            } else {
                                instance.markIncomplete()
                            }
                        }
                    ))
                }
                
                // Delete Section
                Section {
                    Button(role: .destructive) {
                        if isPartOfSeries {
                            showingDeleteActionSheet = true
                        } else {
                            deleteAndDismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Event")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSave()
                    }
                    .disabled(!hasChanges)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            
            // MARK: - Save Action Sheet (Series vs Instance)
            .confirmationDialog(
                "Save Changes",
                isPresented: $showingSaveActionSheet,
                titleVisibility: .visible
            ) {
                Button("Save for This Event Only") {
                    saveThisEventOnly()
                }
                
                Button("Save for All Future Events") {
                    saveAllFutureEvents()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This event is part of a repeating series. Do you want to save changes for just this event, or for all future events?")
            }
            
            // MARK: - Delete Action Sheet
            .confirmationDialog(
                "Delete Event",
                isPresented: $showingDeleteActionSheet,
                titleVisibility: .visible
            ) {
                Button("Delete This Event Only", role: .destructive) {
                    deleteThisEventOnly()
                }
                
                Button("Delete All Future Events", role: .destructive) {
                    deleteAllFutureEvents()
                }
                
                Button("Delete All Events", role: .destructive) {
                    deleteAllEvents()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This event is part of a repeating series. What would you like to delete?")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCurrentValues() {
        editedTitle = instance.displayTitle
        editedTime = instance.effectiveTime
        editedNotes = instance.notes ?? ""
    }
    
    private func checkForChanges() {
        let titleChanged = editedTitle != instance.displayTitle
        let timeChanged = !Calendar.current.isDate(editedTime, equalTo: instance.effectiveTime, toGranularity: .minute)
        let notesChanged = editedNotes != (instance.notes ?? "")
        
        hasChanges = titleChanged || timeChanged || notesChanged
    }
    
    private func handleSave() {
        if isPartOfSeries {
            // Show action sheet to choose scope
            showingSaveActionSheet = true
        } else {
            // No series, just save directly
            saveThisEventOnly()
        }
    }
    
    private func saveThisEventOnly() {
        let changes = MoleculeService.InstanceChanges(
            title: editedTitle != instance.displayTitle ? editedTitle : nil,
            scheduledTime: !Calendar.current.isDate(editedTime, equalTo: instance.effectiveTime, toGranularity: .minute) ? editedTime : nil,
            notes: editedNotes != (instance.notes ?? "") ? editedNotes : nil
        )
        
        service.updateThisEventOnly(instance, with: changes)
        dismiss()
    }
    
    private func saveAllFutureEvents() {
        let changes = MoleculeService.InstanceChanges(
            title: editedTitle != instance.displayTitle ? editedTitle : nil,
            scheduledTime: !Calendar.current.isDate(editedTime, equalTo: instance.effectiveTime, toGranularity: .minute) ? editedTime : nil,
            notes: nil // Notes are instance-specific
        )
        
        service.updateAllFutureEvents(from: instance, with: changes)
        dismiss()
    }
    
    private func deleteAndDismiss() {
        modelContext.delete(instance)
        try? modelContext.save()
        dismiss()
    }
    
    private func deleteThisEventOnly() {
        service.deleteEvents(instance, scope: .thisEventOnly)
        dismiss()
    }
    
    private func deleteAllFutureEvents() {
        service.deleteEvents(instance, scope: .allFutureEvents)
        dismiss()
    }
    
    private func deleteAllEvents() {
        service.deleteEvents(instance, scope: .allEvents)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MoleculeTemplate.self, MoleculeInstance.self, configurations: config)
    
    let template = MoleculeTemplate(
        title: "Morning Routine",
        baseTime: Date(),
        recurrenceFreq: .daily
    )
    container.mainContext.insert(template)
    
    let instance = MoleculeInstance(
        scheduledDate: Date(),
        parentTemplate: template
    )
    container.mainContext.insert(instance)
    
    return MoleculeEditorView(instance: instance)
        .modelContainer(container)
}
