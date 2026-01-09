//
//  MoleculeTemplateDetailView.swift
//  Protocol
//
//  Extracted from ContentView.swift on 2026-01-08.
//

import SwiftUI
import SwiftData

struct MoleculeTemplateDetailView: View {
    @Bindable var template: MoleculeTemplate
    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [MoleculeTemplate]
    
    // New template creation flow
    var isNewlyCreated: Bool = false
    var onDismissShowOptions: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddAtom = false
    @State private var showingRecurrencePicker = false
    @State private var atomToEdit: AtomTemplate?
    @State private var showingCustomDurationAlert = false
    @State private var customDurationInput: String = ""
    @State private var showingCustomCompoundAlert = false
    @State private var customCompoundInput: String = ""
    @State private var showingSyncConfirmation = false
    @State private var syncResultMessage: String = ""
    @State private var showingIconEditor = false
    @State private var editingIconSymbol: String = ""
    @State private var editingIconFrame: IconFrameStyle = .circle
    @State private var editingThemeColor: Color = .blue
    
    // Backfill State
    @State private var showingBackfillSheet = false
    @State private var backfillStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var backfillEndDate = Date()
    @State private var showingBackfillSuccess = false
    @State private var backfilledCount = 0
    
    // Atom Undo State
    @State private var showingAtomUndoToast = false
    @State private var undoAtomId: UUID?
    @State private var undoAtomName: String = ""
    
    // Bulk Atom Selection State
    @State private var selectedAtomIDs: Set<PersistentIdentifier> = []
    @State private var isSelectingAtoms = false
    @State private var showingBulkAtomDeleteConfirmation = false
    @State private var undoBulkAtomIds: [UUID] = []
    
    private var sortedAtomTemplates: [AtomTemplate] {
        template.atomTemplates
        .filter { !$0.isArchived }
        .sorted { $0.order < $1.order }
    }
    
    private var uniqueCompounds: [String] {
        Array(Set(allTemplates.compactMap { $0.compound })).sorted()
    }
    
    var body: some View {
        List {
            // Icon Section
            Section {
                HStack {
                    Spacer()
                    Button {
                        editingIconSymbol = template.iconSymbol ?? ""
                        editingIconFrame = template.iconFrame
                        editingThemeColor = template.themeColor
                        showingIconEditor = true
                    } label: {
                        AvatarView(
                            molecule: template,
                            size: 70
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } footer: {
                Text("Tap to customize icon")
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Template Info Section
            Section("Template Info") {
                TextField("Title", text: $template.title)
                
                Toggle("All Day", isOn: $template.isAllDay)
                
                if !template.isAllDay {
                    DatePicker(
                        "Base Time",
                        selection: $template.baseTime,
                        displayedComponents: .hourAndMinute
                    )
                }
                
                Button {
                    showingRecurrencePicker = true
                } label: {
                    HStack {
                        Text("Repeat")
                        .foregroundStyle(.primary)
                        Spacer()
                        Text(template.recurrenceDescription)
                        .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
                
                TextField("Notes (optional)", text: Binding(
                    get: { template.notes ?? "" },
                    set: { template.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
                
                Menu {
                    ForEach(uniqueCompounds, id: \.self) { compound in
                        Button(compound) {
                            template.compound = compound
                        }
                    }
                    
                    Divider()
                    
                    Button("Custom...") {
                        customCompoundInput = ""
                        showingCustomCompoundAlert = true
                    }
                    
                    if template.compound != nil {
                        Divider()
                        Button("Clear Compound", role: .destructive) {
                            template.compound = nil
                        }
                    }
                } label: {
                    HStack {
                        Text("Compound")
                        .foregroundStyle(.primary)
                        Spacer()
                        if let compound = template.compound {
                            Text(compound)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Uncategorized")
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            
            // Atom Templates Section
            Section {
                if sortedAtomTemplates.isEmpty {
                    Text("No atoms yet")
                    .foregroundStyle(.secondary)
                    .italic()
                } else {
                    ForEach(sortedAtomTemplates) { atom in
                        HStack(spacing: 12) {
                            // Selection checkbox (when in edit mode)
                            if isSelectingAtoms {
                                Button {
                                    toggleAtomSelection(atom)
                                } label: {
                                    Image(systemName: selectedAtomIDs.contains(atom.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedAtomIDs.contains(atom.persistentModelID) ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            AtomTemplateRow(atom: atom)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelectingAtoms {
                                    toggleAtomSelection(atom)
                                } else {
                                    atomToEdit = atom
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !isSelectingAtoms {
                                Button {
                                    duplicateAtom(atom)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .onDelete(perform: isSelectingAtoms ? nil : deleteAtoms)
                    .onMove(perform: isSelectingAtoms ? nil : moveAtoms)
                }
                
                Button {
                    showingAddAtom = true
                } label: {
                    Label("Add Atom", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Atoms")
                    Spacer()
                    Text("\(sortedAtomTemplates.count)")
                    .foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Atoms are cloned to each instance when generated.")
                    
                    if !template.instances.isEmpty && !sortedAtomTemplates.isEmpty {
                        Button {
                            syncAtomsToExistingInstances()
                        } label: {
                            Label("Sync to Existing Instances", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        }
                    }
                }
            }
            
            // Generate Instances Section
            Section {
                Menu {
                    Button {
                        generateInstances(until: Calendar.current.date(byAdding: .day, value: 21, to: Date())!)
                    } label: {
                        Label("21 Days (Get the habit going)", systemImage: "flame")
                    }
                    
                    Button {
                        generateInstances(until: Calendar.current.date(byAdding: .day, value: 66, to: Date())!)
                    } label: {
                        Label("66 Days (Solidify the habit)", systemImage: "star.fill")
                    }
                    
                    Divider()
                    
                    Button {
                        customDurationInput = ""
                        showingCustomDurationAlert = true
                    } label: {
                        Label("Custom Duration...", systemImage: "number")
                    }
                    
                    Button {
                        showingBackfillSheet = true
                    } label: {
                        Label("Time Machine (Backfill)...", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Label("Generate Schedule", systemImage: "arrow.clockwise")
                }
                .disabled(template.atomTemplates.isEmpty)
            } footer: {
                if template.atomTemplates.isEmpty {
                    Text("Add at least one task before generating instances.")
                } else {
                    Text("Creates scheduled instances with tasks based on habit research.")
                }
            }
            
            // Instances Section
            if !template.instances.isEmpty {
                Section {
                    ForEach(template.instances.sorted { $0.scheduledDate < $1.scheduledDate }.prefix(10), id: \.id) { instance in
                        NavigationLink(value: instance) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(instance.displayTitle)
                                    .font(.body)
                                    Text(instance.scheduledDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Atom count badge
                                if !instance.atomInstances.isEmpty {
                                    Text("\(instance.atomInstances.filter(\.isCompleted).count)/\(instance.atomInstances.count)")
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                    if template.instances.count > 10 {
                        NavigationLink {
                            InstanceManagementView(template: template)
                        } label: {
                            Text("See all \(template.instances.count) instances...")
                            .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        // Link for small lists too so they can use bulk select
                        NavigationLink {
                            InstanceManagementView(template: template)
                        } label: {
                            Text("Manage Instances")
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                } header: {
                    HStack {
                        Text("Instances (\(template.instances.count))")
                        Spacer()
                        NavigationLink {
                            InstanceManagementView(template: template)
                        } label: {
                            Text("Manage")
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        
        .navigationTitle(isNewlyCreated ? "New Molecule" : "Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNewlyCreated)
        .toolbar {
            if isNewlyCreated {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onDismissShowOptions?()
                    }
                    .fontWeight(.semibold)
                }
            } else {
                if !sortedAtomTemplates.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(isSelectingAtoms ? "Done" : "Select") {
                            withAnimation {
                                isSelectingAtoms.toggle()
                                if !isSelectingAtoms {
                                    selectedAtomIDs.removeAll()
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Custom Duration", isPresented: $showingCustomDurationAlert) {
            TextField("Number of days", text: $customDurationInput)
            .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Generate") {
                if let days = Int(customDurationInput), days > 0 {
                    let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
                    generateInstances(until: targetDate)
                }
            }
        } message: {
            Text("Enter the number of days to generate instances for.")
        }
        .alert("New Compound", isPresented: $showingCustomCompoundAlert) {
            TextField("Compound name", text: $customCompoundInput)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let trimmed = customCompoundInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Check for existing case-insensitive match
                    if let existing = uniqueCompounds.first(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                        template.compound = existing
                    } else {
                        template.compound = trimmed
                    }
                }
            }
        } message: {
            Text("Enter a name for the new Compound.")
        }
        .alert("Sync Complete", isPresented: $showingSyncConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncResultMessage)
        }
        .sheet(isPresented: $showingAddAtom) {
            AtomTemplateEditorView(parentTemplate: template)
        }
        .sheet(item: $atomToEdit) { atom in
            AtomTemplateEditorView(parentTemplate: template, existingAtom: atom)
        }
        .sheet(isPresented: $showingRecurrencePicker) {
            RecurrencePickerView(
                frequency: $template.recurrenceFreq,
                customDays: $template.recurrenceDays,
                endRuleType: $template.endRuleType,
                endDate: $template.endRuleDate,
                endCount: $template.endRuleCount
            )
        }
        .sheet(isPresented: $showingIconEditor) {
            IconEditorSheet(
                iconSymbol: $editingIconSymbol,
                iconFrame: $editingIconFrame,
                themeColor: $editingThemeColor,
                fallbackText: template.title
            )
            .onDisappear {
                // Save to template when sheet closes
                template.iconSymbol = editingIconSymbol.isEmpty ? nil : editingIconSymbol
                template.iconFrame = editingIconFrame
                template.themeColor = editingThemeColor
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showingBackfillSheet) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Start Date", selection: $backfillStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $backfillEndDate, displayedComponents: .date)
                    } footer: {
                        Text("Instances will be generated for every day in this range that matches the molecule's schedule.")
                    }
                    
                    Section {
                        Button("Generate Instances") {
                            let service = MoleculeService(modelContext: modelContext)
                            let newInstances = service.backfillInstances(
                                for: template,
                                from: backfillStartDate,
                                to: backfillEndDate
                            )
                            backfilledCount = newInstances.count
                            showingBackfillSuccess = true
                            showingBackfillSheet = false
                        }
                        .bold()
                    }
                }
                .navigationTitle("Time Machine")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingBackfillSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Backfill Complete", isPresented: $showingBackfillSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Successfully generated \(backfilledCount) past instances.")
        }
        .navigationDestination(for: MoleculeInstance.self) { instance in
            MoleculeInstanceDetailView(instance: instance)
        }
        .overlay(alignment: .bottom) {
            if showingAtomUndoToast {
                HStack(spacing: 12) {
                    Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Archived")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        Text(undoAtomName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        undoAtomArchive()
                    } label: {
                        Text("Undo")
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectingAtoms && !selectedAtomIDs.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedAtomIDs.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        showingBulkAtomDeleteConfirmation = true
                    } label: {
                        Label("Delete \(selectedAtomIDs.count)", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .alert("Delete \(selectedAtomIDs.count) Tasks?", isPresented: $showingBulkAtomDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                bulkDeleteAtoms()
            }
        } message: {
            Text("These tasks will be archived and can be restored from the undo toast.")
        }
        .onChange(of: showingAtomUndoToast) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        showingAtomUndoToast = false
                        undoAtomId = nil
                        undoBulkAtomIds.removeAll()
                    }
                }
            }
        }
    }
    
    private func toggleAtomSelection(_ atom: AtomTemplate) {
        if selectedAtomIDs.contains(atom.persistentModelID) {
            selectedAtomIDs.remove(atom.persistentModelID)
        } else {
            selectedAtomIDs.insert(atom.persistentModelID)
        }
    }
    
    private func bulkDeleteAtoms() {
        var archivedAtoms: [(id: UUID, name: String)] = []
        
        for id in selectedAtomIDs {
            if let atom = sortedAtomTemplates.first(where: { $0.persistentModelID == id }) {
                archivedAtoms.append((atom.id, atom.title))
                atom.isArchived = true
            }
        }
        
        try? modelContext.save()
        
        // Log deletions
        Task {
            for item in archivedAtoms {
                await AuditLogger.shared.logDelete(
                    entityType: .atomTemplate,
                    entityId: item.id.uuidString,
                    entityName: item.name
                )
            }
        }
        
        // Show undo toast
        undoBulkAtomIds = archivedAtoms.map { $0.id }
        undoAtomName = "\(archivedAtoms.count) tasks"
        withAnimation {
            showingAtomUndoToast = true
            isSelectingAtoms = false
            selectedAtomIDs.removeAll()
        }
    }
    
    // MARK: - Actions
    
    private func deleteAtoms(at offsets: IndexSet) {
        let atomsToDelete = offsets.map { sortedAtomTemplates[$0] }
        
        for atom in atomsToDelete {
            // Capture info before archiving
            let atomId = atom.id
            let atomName = atom.title
            
            // Soft delete (archive)
            atom.isArchived = true
            
            // Log the archive
            Task {
                await AuditLogger.shared.logDelete(
                    entityType: .atomTemplate,
                    entityId: atomId.uuidString,
                    entityName: atomName
                )
            }
            
            // For undo: store last deleted atom
            undoAtomId = atomId
            undoAtomName = atomName
        }
        
        try? modelContext.save()
        
        // Show undo toast
        withAnimation {
            showingAtomUndoToast = true
        }
    }
    
    private func undoAtomArchive() {
        // Handle bulk undo first
        if !undoBulkAtomIds.isEmpty {
            for atomId in undoBulkAtomIds {
                if let atom = template.atomTemplates.first(where: { $0.id == atomId }) {
                    atom.isArchived = false
                    
                    Task {
                        await AuditLogger.shared.logUpdate(
                            entityType: .atomTemplate,
                            entityId: atom.id.uuidString,
                            entityName: atom.title,
                            changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                            additionalInfo: "Unarchived via Bulk Undo"
                        )
                    }
                }
            }
            try? modelContext.save()
            
            withAnimation {
                showingAtomUndoToast = false
                undoBulkAtomIds.removeAll()
            }
            return
        }
        
        // Handle single undo
        guard let atomId = undoAtomId else { return }
        
        // Find the archived atom and unarchive it
        if let atom = template.atomTemplates.first(where: { $0.id == atomId }) {
            atom.isArchived = false
            try? modelContext.save()
            
            // Audit log
            Task {
                await AuditLogger.shared.logUpdate(
                    entityType: .atomTemplate,
                    entityId: atom.id.uuidString,
                    entityName: atom.title,
                    changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                    additionalInfo: "Unarchived via Undo"
                )
            }
        }
        
        withAnimation {
            showingAtomUndoToast = false
            undoAtomId = nil
        }
    }
    
    private func moveAtoms(from source: IndexSet, to destination: Int) {
        var atoms = sortedAtomTemplates
        atoms.move(fromOffsets: source, toOffset: destination)
        
        for (index, atom) in atoms.enumerated() {
            atom.order = index
        }
        try? modelContext.save()
    }
    
    private func duplicateAtom(_ sourceAtom: AtomTemplate) {
        withAnimation {
            // Create new atom with fresh UUID and copied properties
            let newAtom = AtomTemplate(
                id: UUID(),
                title: "\(sourceAtom.title) (Copy)",
                inputType: sourceAtom.inputType,
                targetValue: sourceAtom.targetValue,
                unit: sourceAtom.unit,
                order: sourceAtom.order + 1,
                targetSets: sourceAtom.targetSets,
                targetReps: sourceAtom.targetReps,
                defaultRestTime: sourceAtom.defaultRestTime,
                videoURL: sourceAtom.videoURL,
                parentMoleculeTemplate: template
            )
            
            // Shift orders of atoms that come after
            for atom in template.atomTemplates where atom.order > sourceAtom.order {
                atom.order += 1
            }
            
            modelContext.insert(newAtom)
            try? modelContext.save()
        }
    }
    
    private func syncAtomsToExistingInstances() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get future incomplete instances
        let futureInstances = template.instances.filter { instance in
            !instance.isCompleted && calendar.startOfDay(for: instance.scheduledDate) >= today
        }
        
        var addedCount = 0
        var removedCount = 0
        
        for instance in futureInstances {
            // Get current atom template IDs
            let templateAtomIDs = Set(template.atomTemplates.map { $0.id })
            
            // Get existing atom instance source IDs
            let existingSourceIDs = Set(instance.atomInstances.compactMap { $0.sourceTemplateId })
            
            // Find missing atoms (in template but not in instance)
            let missingAtomTemplates = template.atomTemplates.filter {
                !existingSourceIDs.contains($0.id)
            }
            
            // Add missing atoms
            for atomTemplate in missingAtomTemplates {
                let newAtomInstance = atomTemplate.createInstance(for: instance)
                instance.atomInstances.append(newAtomInstance)
                addedCount += 1
            }
            
            // Remove orphaned atoms (in instance but template was deleted)
            let orphanedAtoms = instance.atomInstances.filter {
                guard let sourceId = $0.sourceTemplateId else { return false }
                return !templateAtomIDs.contains(sourceId)
            }
            for orphan in orphanedAtoms {
                if let index = instance.atomInstances.firstIndex(where: { $0.id == orphan.id }) {
                    instance.atomInstances.remove(at: index)
                }
                modelContext.delete(orphan)
                removedCount += 1
            }
        }
        
        try? modelContext.save()
        
        // Show result message
        syncResultMessage = "Updated \(futureInstances.count) instances: \(addedCount) tasks added, \(removedCount) removed."
        showingSyncConfirmation = true
    }
    
    private func deleteInstances(at offsets: IndexSet) {
        let instances = template.instances.sorted { $0.scheduledDate < $1.scheduledDate }
        let instancesToDelete = offsets.map { instances[$0] }
        for instance in instancesToDelete {
            NotificationManager.shared.cancelNotification(for: instance)
            modelContext.delete(instance)
        }
        try? modelContext.save()
    }
    
    private func generateInstances(until targetDate: Date) {
        let newInstances = template.generateInstances(until: targetDate, in: modelContext)
        for instance in newInstances {
            modelContext.insert(instance)
        }
        try? modelContext.save()
        
        Task {
            await NotificationManager.shared.scheduleNotifications(for: newInstances)
        }
    }
}
