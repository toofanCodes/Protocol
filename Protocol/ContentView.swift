//
//  ContentView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    
    @State private var deepLinkedInstance: MoleculeInstance?
    
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
            
            SettingsHubView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onChange(of: deepLinkManager.pendingInstanceId) { _, newId in
            guard let instanceId = newId else { return }
            
            // Fetch the instance from the database
            let descriptor = FetchDescriptor<MoleculeInstance>(
                predicate: #Predicate<MoleculeInstance> { $0.id == instanceId }
            )
            
            if let instance = try? modelContext.fetch(descriptor).first {
                deepLinkedInstance = instance
            }
            
            // Clear the pending navigation
            deepLinkManager.clearPendingNavigation()
        }
        .sheet(item: $deepLinkedInstance) { instance in
            NavigationStack {
                MoleculeInstanceDetailView(instance: instance)
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
    @Query(filter: #Predicate<MoleculeTemplate> { !$0.isArchived }) private var templates: [MoleculeTemplate]
    
    @State private var selectedMoleculeIDs: Set<PersistentIdentifier> = []
    @State private var isSelecting = false
    @State private var sortOption: TemplateSortOption = .manual
    
    // Navigation
    @State private var navigationPath = NavigationPath()
    
    // Dialogs
    @State private var showingBulkActionSheet = false
    @State private var showingGenerateSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingCustomDurationAlert = false
    @State private var customDurationInput: String = ""
    @State private var showingSingleDeleteAlert = false // NEW
    @State private var templateToDelete: MoleculeTemplate? // NEW

    
    // Bulk Backfill State
    @State private var showingBulkBackfillSheet = false
    @State private var backfillStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var backfillEndDate = Date()
    @State private var showingBulkBackfillSuccess = false
    @State private var bulkBackfillMessage = ""
    
    // Template Creation Flow State
    @State private var newlyCreatedTemplate: MoleculeTemplate?
    @State private var highlightedMoleculeID: PersistentIdentifier?
    @State private var showingCreationOptions = false
    @State private var showingCreationSuccess = false
    @State private var creationCustomDays: String = ""
    @State private var showingCreationCustomAlert = false
    
    // Undo Toast State
    @State private var showingUndoToast = false
    @State private var undoTemplateId: UUID?
    @State private var undoTemplateName: String = ""
    @State private var undoBulkTemplateIds: [UUID] = [] // NEW
    
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
    
    /// Extracted message to reduce body complexity for type-checker
    private var creationSuccessMessage: String {
        if let template = newlyCreatedTemplate {
            let instanceCount = template.instances.count
            if instanceCount > 0 {
                return "'\(template.title)' is ready. \(instanceCount) instances generated."
            } else {
                return "'\(template.title)' is ready."
            }
        }
        return "Your molecule is ready."
    }

    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            templateListContent
                .navigationTitle("Protocols")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { bottomBarContent }
                .navigationDestination(for: MoleculeTemplate.self) { template in
                    MoleculeTemplateDetailView(
                        template: template,
                        isNewlyCreated: newlyCreatedTemplate?.id == template.id,
                        onDismissShowOptions: {
                            // Only show options if still newly created and has no instances
                            if newlyCreatedTemplate?.id == template.id && template.instances.isEmpty {
                                showingCreationOptions = true
                            } else {
                                newlyCreatedTemplate = nil
                            }
                        },
                        onCancel: {
                            if newlyCreatedTemplate?.id == template.id {
                                modelContext.delete(template)
                                try? modelContext.save()
                                newlyCreatedTemplate = nil
                                navigationPath.removeLast()
                            }
                        }
                    )
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .blueprintImport:
                        BlueprintImportView()
                    }
                }
                .modifier(TemplateListDialogsModifier(
                    showingBulkActionSheet: $showingBulkActionSheet,
                    showingGenerateSheet: $showingGenerateSheet,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    showingCustomDurationAlert: $showingCustomDurationAlert,
                    showingBulkBackfillSheet: $showingBulkBackfillSheet,
                    showingBulkBackfillSuccess: $showingBulkBackfillSuccess,
                    showingCreationOptions: $showingCreationOptions,
                    showingCreationCustomAlert: $showingCreationCustomAlert,
                    showingCreationSuccess: $showingCreationSuccess,
                    showingUndoToast: $showingUndoToast,
                    customDurationInput: $customDurationInput,
                    creationCustomDays: $creationCustomDays,
                    backfillStartDate: $backfillStartDate,
                    backfillEndDate: $backfillEndDate,
                    newlyCreatedTemplate: $newlyCreatedTemplate,
                    undoTemplateId: $undoTemplateId,
                    undoBulkTemplateIds: $undoBulkTemplateIds,
                    undoTemplateName: $undoTemplateName,
                    templates: templates,
                    selectedMoleculeIDs: selectedMoleculeIDs,
                    pinnedCount: pinnedCount,
                    bulkBackfillMessage: bulkBackfillMessage,
                    creationSuccessMessage: creationSuccessMessage,
                    bulkPin: bulkPin,
                    bulkUnpin: bulkUnpin,
                    bulkDelete: bulkDelete,
                    bulkGenerate: bulkGenerate,
                    bulkBackfill: bulkBackfill,
                    deleteTemplate: deleteTemplate,
                    generateForNewTemplate: generateForNewTemplate,
                    onSkipCreation: onSkipCreation,
                    undoArchive: undoArchive,
                    undoBulkArchive: undoBulkArchive
                ))
        }
    }
    
    // Navigation Routes
    enum Route: Hashable {
        case blueprintImport
    }

    // MARK: - Extracted View Components
    
    @ViewBuilder
    private var templateListContent: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No Molecules", systemImage: "atom")
                } description: {
                    Text("Start building your protocol.")
                } actions: {
                    VStack(spacing: 12) {
                        Button {
                            addTemplate()
                        } label: {
                            Text("Create New Molecule")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        
                        Button {
                            navigationPath.append(Route.blueprintImport)
                        } label: {
                            Label("Import from Blueprint", systemImage: "doc.text")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: 250)
                    .padding(.top, 12)
                }
            } else {
                ScrollViewReader { proxy in
                    List {
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
                    .onChange(of: highlightedMoleculeID) { _, newId in
                        if let id = newId {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
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
                
                Menu {
                    Button {
                        addTemplate()
                    } label: {
                        Label("New Molecule", systemImage: "plus")
                    }
                    
                    Button {
                        navigationPath.append(Route.blueprintImport)
                    } label: {
                        Label("Import Blueprint", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        
        ToolbarItem(placement: .topBarLeading) {
            if !templates.isEmpty {
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
        
        if isSelecting {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Text("\(selectedMoleculeIDs.count) Selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Done") {
                         withAnimation {
                             isSelecting = false
                             selectedMoleculeIDs.removeAll()
                         }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var bottomBarContent: some View {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                // Capture template info
                let templateId = template.id
                let templateName = template.title
                
                // SOFT DELETE: Archive instead of delete
                template.isArchived = true
                try? modelContext.save()
                
                // Log the archive
                Task {
                    await AuditLogger.shared.logDelete(
                        entityType: .moleculeTemplate,
                        entityId: templateId.uuidString,
                        entityName: templateName
                    )
                }
                
                // Show undo toast
                undoTemplateId = templateId
                undoTemplateName = templateName
                withAnimation {
                    showingUndoToast = true
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                duplicateMolecule(template)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .tint(.blue)
            
            Button {
                togglePin(for: template)
            } label: {
                Label(template.isPinned ? "Unpin" : "Pin", systemImage: template.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .tag(template.persistentModelID)
        .id(template.persistentModelID)
        .listRowBackground(
            highlightedMoleculeID == template.persistentModelID ? Color.yellow.opacity(0.2) : nil
        )
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
        let maxOrder = templates.map(\.sortOrder).max() ?? 0
        let newTemplate = MoleculeTemplate(
            title: "New Molecule",
            baseTime: Date(),
            recurrenceFreq: .daily
        )
        newTemplate.sortOrder = maxOrder + 1
        modelContext.insert(newTemplate)
        try? modelContext.save()
        
        // Audit log
        Task {
            await AuditLogger.shared.logCreate(
                entityType: .moleculeTemplate,
                entityId: newTemplate.id.uuidString,
                entityName: newTemplate.title
            )
        }
        
        // Store as newly created and navigate to detail view
        newlyCreatedTemplate = newTemplate
        navigationPath.append(newTemplate)
    }
    
    private func deleteTemplate(_ template: MoleculeTemplate) {
        // Log BEFORE deleting
        let entityId = template.id.uuidString
        let entityName = template.title
        
        Task {
            await AuditLogger.shared.logDelete(
                entityType: .moleculeTemplate,
                entityId: entityId,
                entityName: entityName
            )
        }
        
        // Direct delete - same as bulk delete
        modelContext.delete(template)
        try? modelContext.save()
        print("✅ DELETE COMPLETED")
    }
    
    private func generateForNewTemplate(days: Int) {
        guard let template = newlyCreatedTemplate else { return }
        
        // Highlight the new molecule
        highlightedMoleculeID = template.persistentModelID
        
        let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let newInstances = template.generateInstances(until: targetDate, in: modelContext)
        for instance in newInstances {
            modelContext.insert(instance)
        }
        try? modelContext.save()
        
        // Schedule notifications
        Task {
            await NotificationManager.shared.scheduleNotifications(for: newInstances)
        }
        
        // Return to list view
        navigationPath = NavigationPath()
        
        // Close sheet and show success alert
        showingCreationOptions = false
        showingCreationSuccess = true
        // Note: newlyCreatedTemplate is kept for the success message, then cleared on dismiss
        
        // Clear highlight after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                highlightedMoleculeID = nil
            }
        }
    }
    
    private func onSkipCreation() {
        if let template = newlyCreatedTemplate {
            highlightedMoleculeID = template.persistentModelID
        }
        
        showingCreationOptions = false
        newlyCreatedTemplate = nil
        
        // Return to list view
        navigationPath = NavigationPath()
        
        // Clear highlight after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                highlightedMoleculeID = nil
            }
        }
    }
    
    private func undoArchive() {
        guard let templateId = undoTemplateId else { return }
        
        // Find the archived template and unarchive it
        let descriptor = FetchDescriptor<MoleculeTemplate>(
            predicate: #Predicate<MoleculeTemplate> { $0.id == templateId }
        )
        
        if let template = try? modelContext.fetch(descriptor).first {
            template.isArchived = false
            try? modelContext.save()
            
            // Audit log
            Task {
                await AuditLogger.shared.logUpdate(
                    entityType: .moleculeTemplate,
                    entityId: template.id.uuidString,
                    entityName: template.title,
                    changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                    additionalInfo: "Unarchived via Undo"
                )
            }
        }
        
        withAnimation {
            showingUndoToast = false
            undoTemplateId = nil
        }
    }
    
    private func undoBulkArchive() {
        guard !undoBulkTemplateIds.isEmpty else { return }
        
        // Find and unarchive all templates
        for templateId in undoBulkTemplateIds {
            let descriptor = FetchDescriptor<MoleculeTemplate>(
                predicate: #Predicate<MoleculeTemplate> { $0.id == templateId }
            )
            
            if let template = try? modelContext.fetch(descriptor).first {
                template.isArchived = false
                
                // Audit log each unarchive
                Task {
                    await AuditLogger.shared.logUpdate(
                        entityType: .moleculeTemplate,
                        entityId: template.id.uuidString,
                        entityName: template.title,
                        changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                        additionalInfo: "Unarchived via Bulk Undo"
                    )
                }
            }
        }
        
        try? modelContext.save()
        
        withAnimation {
            showingUndoToast = false
            undoBulkTemplateIds.removeAll()
            undoTemplateId = nil
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
    
    private func duplicateMolecule(_ sourceMolecule: MoleculeTemplate) {
        withAnimation {
            let maxOrder = templates.map(\.sortOrder).max() ?? 0
            
            // Create new molecule with copied properties
            let newMolecule = MoleculeTemplate(
                title: "\(sourceMolecule.title) (Copy)",
                baseTime: sourceMolecule.baseTime,
                recurrenceFreq: sourceMolecule.recurrenceFreq
            )
            
            // Copy all properties
            newMolecule.sortOrder = maxOrder + 1
            newMolecule.isAllDay = sourceMolecule.isAllDay
            newMolecule.recurrenceDays = sourceMolecule.recurrenceDays
            newMolecule.endRuleType = sourceMolecule.endRuleType
            newMolecule.endRuleDate = sourceMolecule.endRuleDate
            newMolecule.endRuleCount = sourceMolecule.endRuleCount
            newMolecule.notes = sourceMolecule.notes
            newMolecule.compound = sourceMolecule.compound
            newMolecule.iconSymbol = sourceMolecule.iconSymbol
            newMolecule.iconFrame = sourceMolecule.iconFrame
            newMolecule.themeColorHex = sourceMolecule.themeColorHex
            
            modelContext.insert(newMolecule)
            
            // Duplicate all atoms
            for (index, sourceAtom) in sourceMolecule.atomTemplates.sorted(by: { $0.order < $1.order }).enumerated() {
                let newAtom = AtomTemplate(
                    id: UUID(),
                    title: sourceAtom.title,
                    inputType: sourceAtom.inputType,
                    targetValue: sourceAtom.targetValue,
                    unit: sourceAtom.unit,
                    order: index,
                    targetSets: sourceAtom.targetSets,
                    targetReps: sourceAtom.targetReps,
                    defaultRestTime: sourceAtom.defaultRestTime,
                    videoURL: sourceAtom.videoURL,
                    parentMoleculeTemplate: newMolecule
                )
                modelContext.insert(newAtom)
            }
            
            try? modelContext.save()
            
            // Audit log
            Task {
                await AuditLogger.shared.logCreate(
                    entityType: .moleculeTemplate,
                    entityId: newMolecule.id.uuidString,
                    entityName: newMolecule.title,
                    additionalInfo: "Duplicated from '\(sourceMolecule.title)'"
                )
            }
            
            // Highlight the new molecule
            highlightedMoleculeID = newMolecule.persistentModelID
            
            // Clear highlight after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation {
                    highlightedMoleculeID = nil
                }
            }
        }
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
        // Capture info for logging AND undo
        var archivedTemplates: [(id: UUID, idString: String, name: String)] = []
        
        withAnimation {
            for id in selectedMoleculeIDs {
                if let template = templates.first(where: { $0.persistentModelID == id }) {
                    archivedTemplates.append((
                        template.id,
                        template.id.uuidString,
                        template.title
                    ))
                    
                    // SOFT DELETE: Archive instead of delete
                    template.isArchived = true
                }
            }
            try? modelContext.save()
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
        
        // Log after successful archive
        Task {
            for item in archivedTemplates {
                await AuditLogger.shared.logDelete(
                    entityType: .moleculeTemplate,
                    entityId: item.idString,
                    entityName: item.name
                )
            }
        }
        
        // Show undo toast for bulk operation
        undoBulkTemplateIds = archivedTemplates.map { $0.id }
        undoTemplateName = "\(archivedTemplates.count) molecules"
        withAnimation {
            showingUndoToast = true
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
    
    private func bulkBackfill(from startDate: Date, to endDate: Date) {
        let service = MoleculeService(modelContext: modelContext)
        var totalGenerated = 0
        
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                let newInstances = service.backfillInstances(
                    for: template,
                    from: startDate,
                    to: endDate
                )
                totalGenerated += newInstances.count
            }
        }
        
        bulkBackfillMessage = "Successfully generated \(totalGenerated) past instances."
        showingBulkBackfillSuccess = true
        showingBulkBackfillSheet = false
        
        withAnimation {
             selectedMoleculeIDs.removeAll()
             isSelecting = false
        }
    }
}

// MARK: - Dialogs ViewModifier (Extracted to reduce body complexity)

struct TemplateListDialogsModifier: ViewModifier {
    @Binding var showingBulkActionSheet: Bool
    @Binding var showingGenerateSheet: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var showingCustomDurationAlert: Bool
    @Binding var showingBulkBackfillSheet: Bool
    @Binding var showingBulkBackfillSuccess: Bool
    @Binding var showingCreationOptions: Bool
    @Binding var showingCreationCustomAlert: Bool
    @Binding var showingCreationSuccess: Bool
    @Binding var showingUndoToast: Bool
    @Binding var customDurationInput: String
    @Binding var creationCustomDays: String
    @Binding var backfillStartDate: Date
    @Binding var backfillEndDate: Date
    @Binding var newlyCreatedTemplate: MoleculeTemplate?
    @Binding var undoTemplateId: UUID?
    @Binding var undoBulkTemplateIds: [UUID]
    @Binding var undoTemplateName: String
    
    let templates: [MoleculeTemplate]
    let selectedMoleculeIDs: Set<PersistentIdentifier>
    let pinnedCount: Int
    let bulkBackfillMessage: String
    let creationSuccessMessage: String
    
    let bulkPin: () -> Void
    let bulkUnpin: () -> Void
    let bulkDelete: () -> Void
    let bulkGenerate: (Int) -> Void
    let bulkBackfill: (Date, Date) -> Void
    let deleteTemplate: (MoleculeTemplate) -> Void
    let generateForNewTemplate: (Int) -> Void
    let onSkipCreation: () -> Void
    let undoArchive: () -> Void
    let undoBulkArchive: () -> Void // NEW
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Actions", isPresented: $showingBulkActionSheet) {
                bulkActionsButtons
            }
            .confirmationDialog("Generate Instances", isPresented: $showingGenerateSheet, titleVisibility: .visible) {
                generateButtons
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
                        bulkGenerate(days)
                    }
                }
            } message: {
                Text("Enter the number of days to generate instances for.")
            }


            .sheet(isPresented: $showingBulkBackfillSheet) {
                backfillSheet
            }
            .alert("Backfill Complete", isPresented: $showingBulkBackfillSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(bulkBackfillMessage)
            }
            .sheet(isPresented: $showingCreationOptions) {
                creationOptionsSheet
            }
            .alert("Custom Duration", isPresented: $showingCreationCustomAlert) {
                TextField("Number of days", text: $creationCustomDays)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { }
                Button("Generate") {
                    if let days = Int(creationCustomDays), days > 0 {
                        generateForNewTemplate(days)
                    }
                }
            } message: {
                Text("Enter the number of days to generate instances for.")
            }
            .alert("Schedule Created!", isPresented: $showingCreationSuccess) {
                Button("OK") {
                    newlyCreatedTemplate = nil
                }
            } message: {
                Text(creationSuccessMessage)
            }
            .overlay(alignment: .bottom) { undoToastOverlay }
            .onChange(of: showingUndoToast) { _, isShowing in
                if isShowing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showingUndoToast = false
                            undoTemplateId = nil
                        }
                    }
                }
            }
    }
    
    @ViewBuilder
    private var bulkActionsButtons: some View {
        let selectedTemplates = templates.filter { selectedMoleculeIDs.contains($0.persistentModelID) }
        let allPinned = selectedTemplates.allSatisfy { $0.isPinned }
        let canPin = pinnedCount + selectedTemplates.filter { !$0.isPinned }.count <= 3
        
        if allPinned {
            Button("Unpin Selected") { bulkUnpin() }
        } else if canPin {
            Button("Pin Selected") { bulkPin() }
        }
        
        Button("Delete Selected", role: .destructive) { showingDeleteConfirmation = true }
        Button("Cancel", role: .cancel) { }
    }
    
    @ViewBuilder
    private var generateButtons: some View {
        Button("21 Days (Get the habit going)") { bulkGenerate(21) }
        Button("66 Days (Solidify the habit)") { bulkGenerate(66) }
        Button("Custom Duration...") {
            customDurationInput = ""
            showingCustomDurationAlert = true
        }
        Button("Time Machine (Backfill)...") { showingBulkBackfillSheet = true }
        Button("Cancel", role: .cancel) { }
    }
    
    private var backfillSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start Date", selection: $backfillStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $backfillEndDate, displayedComponents: .date)
                } footer: {
                    Text("Instances will be generated for every day in this range that matches the schedule of the \(selectedMoleculeIDs.count) selected protocols.")
                }
                
                Section {
                    Button("Generate Instances") {
                        bulkBackfill(backfillStartDate, backfillEndDate)
                    }
                    .bold()
                }
            }
            .navigationTitle("Time Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingBulkBackfillSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var creationOptionsSheet: some View {
        NavigationStack {
            List {
                Section {
                    if let template = newlyCreatedTemplate {
                        Text("'\(template.title)' is set up! Would you like to generate scheduled instances now?")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Would you like to generate scheduled instances now?")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Generate Instances") {
                    Button { generateForNewTemplate(21) } label: {
                        Label("21 Days (Get the habit going)", systemImage: "flame")
                    }
                    Button { generateForNewTemplate(66) } label: {
                        Label("66 Days (Solidify the habit)", systemImage: "star.fill")
                    }
                    Button {
                        creationCustomDays = ""
                        showingCreationOptions = false
                        // Delay alert to allow sheet to dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showingCreationCustomAlert = true
                        }
                    } label: {
                        Label("Custom Duration...", systemImage: "number")
                    }
                }
                
                Section {
                    Button {
                        onSkipCreation()
                    } label: {
                        Label("Skip for Now", systemImage: "arrow.right.circle")
                    }
                    .foregroundStyle(.secondary)
                } footer: {
                    Text("You can always generate instances later from the molecule detail view.")
                }
            }
            .navigationTitle("Generate Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCreationOptions = false
                        newlyCreatedTemplate = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    @ViewBuilder
    private var undoToastOverlay: some View {
        if showingUndoToast {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archived")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !undoBulkTemplateIds.isEmpty {
                        Text("\(undoBulkTemplateIds.count) molecules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(undoTemplateName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    if !undoBulkTemplateIds.isEmpty {
                        undoBulkArchive()
                    } else {
                        undoArchive()
                    }
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
}


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
            
            // Series Section

            
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
