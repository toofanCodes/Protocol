//
//  OrphanManagerView.swift
//  Protocol
//
//  Created on 2026-01-05.
//

import SwiftUI
import SwiftData

struct OrphanManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Fetch all instances that have no parent template OR are explicitly marked as orphans
    @Query(filter: #Predicate<MoleculeInstance> { $0.parentTemplate == nil || $0.isOrphan }, sort: \MoleculeInstance.scheduledDate)
    private var orphans: [MoleculeInstance]
    
    @State private var selection = Set<MoleculeInstance>()
    @State private var showingRecreationSheet = false
    @State private var newMoleculeName = ""
    @State private var newMoleculeIcon = "atom" // Default
    @State private var newMoleculeColor = "#007AFF" // Default blue
    
    var body: some View {
        Group {
            if orphans.isEmpty {
                ContentUnavailableView(
                    "No Orphans Found",
                    systemImage: "checkmark.shield.fill",
                    description: Text("Your database is clean. No stranded instances found.")
                )
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(orphans, id: \.self) { instance in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(instance.formattedDate)
                                        .font(.headline)
                                    Text(instance.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if let originalTitle = instance.originalMoleculeTitle {
                                        Text("From: \(originalTitle)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .padding(.top, 1)
                                    }
                                }
                                Spacer()
                                if instance.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .tag(instance)
                        }
                    } header: {
                        Text("\(orphans.count) Orphaned Instances")
                    } footer: {
                        Text("Select instances to assign them to a new molecule, or delete them.")
                            .padding(.bottom, 60) // Space for bottom bar
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            Button(role: .destructive) {
                                deleteSelected()
                            } label: {
                                Text("Delete (\(selection.count))")
                            }
                            .disabled(selection.isEmpty)
                            
                            Spacer()
                            
                            Button {
                                showingRecreationSheet = true
                            } label: {
                                Text("Recover to New Molecule")
                                    .fontWeight(.bold)
                            }
                            .disabled(selection.isEmpty)
                        }
                        .padding()
                        .background(.regularMaterial)
                    }
                }
                .toolbar {
                    // Select All / Deselect All
                    ToolbarItem(placement: .primaryAction) {
                        Button(selection.count == orphans.count ? "Deselect All" : "Select All") {
                            if selection.count == orphans.count {
                                selection.removeAll()
                            } else {
                                selection = Set(orphans)
                            }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active)) // Always in edit mode for selection
        .navigationTitle("Lost & Found")
        .sheet(isPresented: $showingRecreationSheet) {
            NavigationStack {
                Form {
                    Section("New Molecule Details") {
                        TextField("Name (e.g., Morning Workout)", text: $newMoleculeName)
                        
                        // Simple Color Picker (could be expanded)
                        ColorPicker("Theme Color", selection: Binding(
                            get: { Color(hex: newMoleculeColor) },
                            set: { newMoleculeColor = $0.toHex() }
                        ))
                    }
                    
                    Section {
                        Button("Recover & Assign \(selection.count) Events") {
                            recoverSelected()
                        }
                        .disabled(newMoleculeName.isEmpty)
                    } footer: {
                        Text("This will create a new Molecule Template and link the selected instances to it, restoring them to your history.")
                    }
                }
                .navigationTitle("Recover Data")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingRecreationSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    
    // MARK: - Actions
    
    private func deleteSelected() {
        let count = selection.count
        for instance in selection {
            modelContext.delete(instance)
        }
        try? modelContext.save()
        selection.removeAll()
        
        // Audit Log
        Task {
            await AuditLogger.shared.logBulkDelete(
                entityType: .moleculeInstance,
                count: count,
                additionalInfo: "User deleted orphans via Lost & Found"
            )
        }
    }
    
    private func recoverSelected() {
        // 1. Create New Template
        let newTemplate = MoleculeTemplate(
            title: newMoleculeName,
            baseTime: Date(), // Default to now, or infer?
            recurrenceFreq: .daily // Default
        )
        newTemplate.themeColorHex = newMoleculeColor
        newTemplate.iconSymbol = newMoleculeIcon
        
        // Best guess for baseTime: take the time of the first selected instance
        // Sort selection by date to process chronologically
        let sortedSelection = selection.sorted()
        
        if let first = sortedSelection.first {
            // Extract time components
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: first.scheduledDate)
            if let time = calendar.date(bySettingHour: components.hour ?? 9, minute: components.minute ?? 0, second: 0, of: newTemplate.baseTime) {
                newTemplate.baseTime = time
            }
        }
        
        modelContext.insert(newTemplate)
        
        // 2. Infer & Create Atom Structure
        // We want to reconstruct the atoms that this molecule should have.
        // We look at all selected instances, and gather unique atoms by title.
        // We use the "latest" version of the atom (from the most recent instance) to define the template.
        var uniqueAtoms: [String: AtomInstance] = [:]
        
        for instance in sortedSelection {
            for atom in instance.atomInstances {
                // This will overwrite previous entries, effectively keeping the latest version's config
                uniqueAtoms[atom.title] = atom
            }
        }
        
        // Create AtomTemplates for each unique atom found
        var createdAtomTemplates: [String: AtomTemplate] = [:]
        
        // Sort by order found in the instances (using the captured atom's order)
        let sortedAtoms = uniqueAtoms.values.sorted { $0.order < $1.order }
        
        for atomInst in sortedAtoms {
            let atomTemplate = AtomTemplate(
                title: atomInst.title,
                inputType: atomInst.inputType,
                targetValue: atomInst.targetValue,
                unit: atomInst.unit,
                order: atomInst.order,
                targetSets: atomInst.targetSets,
                targetReps: atomInst.targetReps,
                defaultRestTime: atomInst.defaultRestTime,
                videoURL: atomInst.videoURL,
                parentMoleculeTemplate: newTemplate
            )
            // Note: We lose icon/color info for atoms as it's not on AtomInstance, 
            // but we recover the structural data.
            
            modelContext.insert(atomTemplate)
            createdAtomTemplates[atomInst.title] = atomTemplate
        }
        
        // 3. Link Selected Instances & Their Atoms
        for instance in selection {
            instance.parentTemplate = newTemplate
            instance.isOrphan = false
            instance.originalMoleculeTitle = nil
            
            // Link existing atom instances to the new atom templates
            for atom in instance.atomInstances {
                if let template = createdAtomTemplates[atom.title] {
                    atom.sourceTemplateId = template.id
                }
            }
        }
        
        try? modelContext.save()
        
        // Audit Log
        Task {
            await AuditLogger.shared.logCreate(
                entityType: .moleculeTemplate,
                entityId: newTemplate.id.uuidString,
                entityName: newTemplate.title,
                additionalInfo: "Recovered from \(selection.count) orphans with \(createdAtomTemplates.count) atoms"
            )
        }
        
        showingRecreationSheet = false
        selection.removeAll()
        dismiss()
    }
}

#Preview {
    OrphanManagerView()
        .modelContainer(for: [MoleculeInstance.self, MoleculeTemplate.self, AtomInstance.self, AtomTemplate.self, WorkoutSet.self], inMemory: true)
}
