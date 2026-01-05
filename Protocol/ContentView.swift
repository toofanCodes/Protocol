//
//  ContentView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
            
            TemplateListView()
                .tabItem {
                    Label("Protocols", systemImage: "list.bullet")
                }
            
            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
            
            SettingsView()
                .tabItem {
                    Label("HQ", systemImage: "building.columns")
                }
        }
    }
}

// MARK: - Sort Option
enum TemplateSortOption: String, CaseIterable {
    case manual = "Manual"
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
}

// MARK: - Template List View
struct TemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [MoleculeTemplate]
    
    @State private var selectedMoleculeIDs: Set<PersistentIdentifier> = []
    @State private var isSelecting = false
    @State private var sortOption: TemplateSortOption = .manual
    
    // Dialogs
    @State private var showingBulkActionSheet = false
    @State private var showingGenerateSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingCustomDurationAlert = false
    @State private var customDurationInput: String = ""
    
    // Sorted/organized templates
    private var sortedTemplates: [MoleculeTemplate] {
        let pinned = templates.filter { $0.isPinned }.sorted { $0.sortOrder < $1.sortOrder }
        let unpinned = templates.filter { !$0.isPinned }
        
        let sortedUnpinned: [MoleculeTemplate]
        switch sortOption {
        case .manual:
            sortedUnpinned = unpinned.sorted { $0.sortOrder < $1.sortOrder }
        case .nameAsc:
            sortedUnpinned = unpinned.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc:
            sortedUnpinned = unpinned.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
        
        return pinned + sortedUnpinned
    }
    
    private var pinnedCount: Int {
        templates.filter { $0.isPinned }.count
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Molecules",
                        systemImage: "atom",
                        description: Text("Tap + to create your first recurring molecule.")
                    )
                } else {
                    List {
                        // Pinned Section
                        if !sortedTemplates.filter({ $0.isPinned }).isEmpty {
                            Section {
                                ForEach(sortedTemplates.filter { $0.isPinned }) { template in
                                    templateRow(for: template)
                                }
                                .onMove(perform: movePinnedTemplates)
                            } header: {
                                Label("Pinned", systemImage: "pin.fill")
                            }
                        }
                        
                        // All Templates Section
                        Section {
                            ForEach(sortedTemplates.filter { !$0.isPinned }) { template in
                                templateRow(for: template)
                            }
                            .onMove(perform: sortOption == .manual ? moveUnpinnedTemplates : nil)
                        } header: {
                            if !sortedTemplates.filter({ $0.isPinned }).isEmpty {
                                Text("All Protocols")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Protocols")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        // Sort Menu
                        Menu {
                            ForEach(TemplateSortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        
                        // Add Button
                        Button {
                            addTemplate()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "Done" : "Select") {
                        withAnimation {
                            isSelecting.toggle()
                            if !isSelecting {
                                selectedMoleculeIDs.removeAll()
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selectedMoleculeIDs.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            showingGenerateSheet = true
                        } label: {
                            Label("Generate", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button {
                            showingBulkActionSheet = true
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationDestination(for: MoleculeTemplate.self) { template in
                MoleculeTemplateDetailView(template: template)
            }
            // MARK: - Dialogs
            .confirmationDialog("Actions", isPresented: $showingBulkActionSheet) {
                let selectedTemplates = templates.filter { selectedMoleculeIDs.contains($0.persistentModelID) }
                let allPinned = selectedTemplates.allSatisfy { $0.isPinned }
                let canPin = pinnedCount + selectedTemplates.filter { !$0.isPinned }.count <= 3
                
                if allPinned {
                    Button("Unpin Selected") {
                        bulkUnpin()
                    }
                } else if canPin {
                    Button("Pin Selected") {
                        bulkPin()
                    }
                }
                
                Button("Delete Selected", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog("Generate Instances", isPresented: $showingGenerateSheet, titleVisibility: .visible) {
                Button("21 Days (Get the habit going)") { bulkGenerate(days: 21) }
                Button("66 Days (Solidify the habit)") { bulkGenerate(days: 66) }
                Button("Custom Duration...") {
                    customDurationInput = ""
                    showingCustomDurationAlert = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Generate instances for \(selectedMoleculeIDs.count) selected molecule(s)")
            }
            .alert("Delete \(selectedMoleculeIDs.count) Molecules?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { bulkDelete() }
            } message: {
                Text("This will delete the selected molecules and all their instances. This cannot be undone.")
            }
            .alert("Custom Duration", isPresented: $showingCustomDurationAlert) {
                TextField("Number of days", text: $customDurationInput)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { }
                Button("Generate") {
                    if let days = Int(customDurationInput), days > 0 {
                        bulkGenerate(days: days)
                    }
                }
            } message: {
                Text("Enter the number of days to generate instances for.")
            }
        }
    }
    
    // MARK: - Row View
    @ViewBuilder
    private func templateRow(for template: MoleculeTemplate) -> some View {
        HStack(spacing: 12) {
            // Selection checkbox (left side)
            if isSelecting {
                Button {
                    toggleSelection(for: template)
                } label: {
                    Image(systemName: selectedMoleculeIDs.contains(template.persistentModelID) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selectedMoleculeIDs.contains(template.persistentModelID) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Avatar (44x44 - Messages/Mail style)
            AvatarView(
                molecule: template,
                size: 44
            )
            
            // Content
            NavigationLink(value: template) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if template.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text(template.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if !template.atomTemplates.isEmpty {
                            Text("\(template.atomTemplates.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(template.recurrenceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if let notes = template.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .disabled(isSelecting)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTemplate(template)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                togglePin(for: template)
            } label: {
                Label(template.isPinned ? "Unpin" : "Pin", systemImage: template.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .tag(template.persistentModelID)
    }
    
    // MARK: - Actions
    private func toggleSelection(for template: MoleculeTemplate) {
        if selectedMoleculeIDs.contains(template.persistentModelID) {
            selectedMoleculeIDs.remove(template.persistentModelID)
        } else {
            selectedMoleculeIDs.insert(template.persistentModelID)
        }
    }
    
    private func togglePin(for template: MoleculeTemplate) {
        if template.isPinned {
            template.isPinned = false
        } else if pinnedCount < 3 {
            template.isPinned = true
            template.sortOrder = pinnedCount
        }
        try? modelContext.save()
    }
    
    private func addTemplate() {
        withAnimation {
            let maxOrder = templates.map(\.sortOrder).max() ?? 0
            let newTemplate = MoleculeTemplate(
                title: "New Molecule",
                baseTime: Date(),
                recurrenceFreq: .daily
            )
            newTemplate.sortOrder = maxOrder + 1
            modelContext.insert(newTemplate)
        }
    }
    
    private func deleteTemplate(_ template: MoleculeTemplate) {
        withAnimation {
            modelContext.delete(template)
        }
    }
    
    private func movePinnedTemplates(from source: IndexSet, to destination: Int) {
        var pinned = sortedTemplates.filter { $0.isPinned }
        pinned.move(fromOffsets: source, toOffset: destination)
        for (index, template) in pinned.enumerated() {
            template.sortOrder = index
        }
        try? modelContext.save()
    }
    
    private func moveUnpinnedTemplates(from source: IndexSet, to destination: Int) {
        var unpinned = sortedTemplates.filter { !$0.isPinned }
        unpinned.move(fromOffsets: source, toOffset: destination)
        let pinnedCount = sortedTemplates.filter { $0.isPinned }.count
        for (index, template) in unpinned.enumerated() {
            template.sortOrder = pinnedCount + index
        }
        try? modelContext.save()
    }
    
    private func bulkGenerate(days: Int) {
        let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        var allNewInstances: [MoleculeInstance] = []
        
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                let newInstances = template.generateInstances(until: targetDate, in: modelContext)
                for instance in newInstances {
                    modelContext.insert(instance)
                }
                allNewInstances.append(contentsOf: newInstances)
            }
        }
        
        try? modelContext.save()
        
        Task {
            await NotificationManager.shared.scheduleNotifications(for: allNewInstances)
        }
        
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    private func bulkDelete() {
        withAnimation {
            for id in selectedMoleculeIDs {
                if let template = templates.first(where: { $0.persistentModelID == id }) {
                    modelContext.delete(template)
                }
            }
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    private func bulkPin() {
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }), !template.isPinned {
                if pinnedCount < 3 {
                    template.isPinned = true
                    template.sortOrder = pinnedCount
                }
            }
        }
        try? modelContext.save()
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    private func bulkUnpin() {
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                template.isPinned = false
            }
        }
        try? modelContext.save()
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
}


// MARK: - Template Detail View
struct MoleculeTemplateDetailView: View {
    @Bindable var template: MoleculeTemplate
    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [MoleculeTemplate]
    
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
    
    private var sortedAtomTemplates: [AtomTemplate] {
        template.atomTemplates.sorted { $0.order < $1.order }
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
                        AtomTemplateRow(atom: atom)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                atomToEdit = atom
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    duplicateAtom(atom)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                    }
                    .onDelete(perform: deleteAtoms)
                    .onMove(perform: moveAtoms)
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
        .navigationTitle("Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
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
        .navigationDestination(for: MoleculeInstance.self) { instance in
            MoleculeInstanceDetailView(instance: instance)
        }
    }
    
    // MARK: - Actions
    
    private func deleteAtoms(at offsets: IndexSet) {
        let atomsToDelete = offsets.map { sortedAtomTemplates[$0] }
        for atom in atomsToDelete {
            modelContext.delete(atom)
        }
        try? modelContext.save()
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

// MARK: - Atom Template Row

struct AtomTemplateRow: View {
    let atom: AtomTemplate
    
    var body: some View {
        HStack(spacing: 10) {
            // Avatar (32x32 - smaller than molecule to show hierarchy)
            AvatarView(
                atom: atom,
                size: 32
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(atom.title)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: atom.inputType.iconName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(atom.inputType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let target = atom.targetDisplayString {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(target)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Molecule Instance Detail View

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
                instance.scheduledDate >= startOfDay && instance.scheduledDate < endOfDay
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

// MARK: - Day of Week Picker (Keeping for existing references, unrelated to new one)
struct DayOfWeekPicker: View {
    @Binding var selectedDays: [Int]
    
    private let days = [
        (0, "S"), (1, "M"), (2, "T"), (3, "W"),
        (4, "T"), (5, "F"), (6, "S")
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.0) { day in
                let isSelected = selectedDays.contains(day.0)
                
                Button {
                    toggleDay(day.0)
                } label: {
                    Text(day.1)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
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

#Preview {
    ContentView()
        .modelContainer(for: [MoleculeTemplate.self, MoleculeInstance.self, AtomTemplate.self, AtomInstance.self, WorkoutSet.self], inMemory: true)
}
