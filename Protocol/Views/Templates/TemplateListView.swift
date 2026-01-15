//
//  TemplateListView.swift
//  Protocol
//
//  Extracted from ContentView.swift on 2026-01-08.
//

import SwiftUI
import SwiftData

struct TemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    // Fetch all to handle retired/pending states. We filter "just deleted" ones manually.
    @Query private var allTemplates: [MoleculeTemplate]
    
    @StateObject private var viewModel = TemplateListViewModel()
    
    // MARK: - Computed Sections
    
    private var pendingTemplates: [MoleculeTemplate] {
        allTemplates.filter { $0.retirementStatus == "pending" }
            .sorted { ($0.retirementDate ?? Date()) > ($1.retirementDate ?? Date()) }
    }
    
    private var retiredTemplates: [MoleculeTemplate] {
        allTemplates.filter { $0.retirementStatus == "retired" }
            .sorted { ($0.retirementDate ?? Date()) > ($1.retirementDate ?? Date()) }
    }
    
    private var activeTemplates: [MoleculeTemplate] {
        // Active means not archived AND not pending/retired
        // (Pending are technically not archived yet, but checking retirementStatus excludes them)
        allTemplates.filter { !$0.isArchived && $0.retirementStatus == nil }
    }
    
    // Sorted/organized active templates for the main list
    private var sortedActiveTemplates: [MoleculeTemplate] {
        viewModel.sortedTemplates(from: activeTemplates)
    }
    
    private var pinnedCount: Int {
        activeTemplates.filter { $0.isPinned }.count
    }
    
    // State for Retirement
    @State private var templateToRetire: MoleculeTemplate?
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            templateListContent
                .navigationTitle("Protocols")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { bottomBarContent }
                .onAppear {
                    viewModel.configure(modelContext: modelContext)
                }
                .navigationDestination(for: MoleculeTemplate.self) { template in
                    MoleculeTemplateDetailView(
                        template: template,
                        isNewlyCreated: viewModel.newlyCreatedTemplate?.id == template.id,
                        onDismissShowOptions: {
                            // Only show options if still newly created and has no instances
                            if viewModel.newlyCreatedTemplate?.id == template.id && template.instances.isEmpty {
                                viewModel.showingCreationOptions = true
                            } else {
                                viewModel.newlyCreatedTemplate = nil
                            }
                        },
                        onCancel: {
                            if viewModel.newlyCreatedTemplate?.id == template.id {
                                modelContext.delete(template)
                                try? modelContext.save()
                                viewModel.newlyCreatedTemplate = nil
                                viewModel.navigationPath.removeLast()
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
                .modifier(TemplateListDialogsModifierSimplified(
                    viewModel: viewModel,
                    templates: allTemplates,
                    pinnedCount: pinnedCount,
                    templateToRetire: $templateToRetire
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
            if activeTemplates.isEmpty && pendingTemplates.isEmpty && retiredTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No Molecules", systemImage: "atom")
                } description: {
                    Text("Start building your protocol.")
                } actions: {
                    VStack(spacing: 12) {
                        Button {
                            viewModel.addTemplate(allTemplates: activeTemplates)
                        } label: {
                            Text("Create New Molecule")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        
                        Button {
                            viewModel.navigationPath.append(Route.blueprintImport)
                        } label: {
                            Label("Import from Blueprint", systemImage: "doc.text")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: 250)
                    .padding(.top, 12)
                }
            } else {
                // ... (This matches the content structure we already replaced in prev step, so we just need to ensure the condition logic is sound relative to where we cut)
                // Wait, the prev replacement chunk ended at line 144. This chunk starts at 79.
                // So I need to replace the conditional at the top.
                
                ScrollViewReader { proxy in
                    List {
                        // 1. Recently Retired (Pending)
                        if !pendingTemplates.isEmpty {
                            Section(header: Text("Recently Retired")) {
                                ForEach(pendingTemplates) { template in
                                    pendingRetirementRow(for: template)
                                }
                            }
                        }
                        
                        // 2. Active Pinned
                        if !sortedActiveTemplates.filter({ $0.isPinned }).isEmpty {
                            Section {
                                ForEach(sortedActiveTemplates.filter { $0.isPinned }) { template in
                                    templateRow(for: template)
                                }
                                .onMove(perform: { source, destination in
                                    viewModel.movePinnedTemplates(from: source, to: destination, in: sortedActiveTemplates)
                                })
                            } header: {
                                Label("Pinned", systemImage: "pin.fill")
                            }
                        }
                        
                        // 3. Active Unpinned
                        Section {
                            ForEach(sortedActiveTemplates.filter { !$0.isPinned }) { template in
                                templateRow(for: template)
                            }
                            .onMove(perform: viewModel.sortOption == .manual ? { source, destination in
                                viewModel.moveUnpinnedTemplates(from: source, to: destination, in: sortedActiveTemplates)
                            } : nil)
                        } header: {
                            if !sortedActiveTemplates.filter({ $0.isPinned }).isEmpty {
                                Text("All Protocols")
                            }
                        }
                        
                        // 4. Retired
                        if !retiredTemplates.isEmpty {
                            Section(header: Text("Retired")) {
                                ForEach(retiredTemplates) { template in
                                    retiredRow(for: template)
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.highlightedMoleculeID) { _, newId in
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
                            viewModel.sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if viewModel.sortOption == option {
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
                        viewModel.addTemplate(allTemplates: activeTemplates)
                    } label: {
                        Label("New Molecule", systemImage: "plus")
                    }
                    
                    Button {
                        viewModel.navigationPath.append(Route.blueprintImport)
                    } label: {
                        Label("Import Blueprint", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        
        ToolbarItem(placement: .topBarLeading) {
            if !activeTemplates.isEmpty || !pendingTemplates.isEmpty || !retiredTemplates.isEmpty {
                Button(viewModel.isSelecting ? "Done" : "Select") {
                    withAnimation {
                        viewModel.isSelecting.toggle()
                        if !viewModel.isSelecting {
                            viewModel.selectedMoleculeIDs.removeAll()
                        }
                    }
                }
            }
        }
        
        if viewModel.isSelecting {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Text("\(viewModel.selectedMoleculeIDs.count) Selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Done") {
                        withAnimation {
                            viewModel.isSelecting = false
                            viewModel.selectedMoleculeIDs.removeAll()
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var bottomBarContent: some View {
        if viewModel.isSelecting && !viewModel.selectedMoleculeIDs.isEmpty {
            HStack(spacing: 12) {
                Button {
                    viewModel.showingGenerateSheet = true
                } label: {
                    Label("Generate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    viewModel.showingBulkActionSheet = true
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
    
    // MARK: - Row Views
    
    @ViewBuilder
    private func templateRow(for template: MoleculeTemplate) -> some View {
        HStack(spacing: 12) {
            // Selection checkbox (left side)
            if viewModel.isSelecting {
                Button {
                    viewModel.toggleSelection(for: template)
                } label: {
                    Image(systemName: viewModel.selectedMoleculeIDs.contains(template.persistentModelID) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(viewModel.selectedMoleculeIDs.contains(template.persistentModelID) ? .blue : .secondary)
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
            .disabled(viewModel.isSelecting)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                templateToRetire = template
            } label: {
                Label("Retire", systemImage: "archivebox")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                viewModel.duplicateMolecule(template, allTemplates: activeTemplates)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .tint(.blue)
            
            Button {
                viewModel.togglePin(for: template, currentPinnedCount: pinnedCount)
            } label: {
                Label(template.isPinned ? "Unpin" : "Pin", systemImage: template.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .tag(template.persistentModelID)
        .id(template.persistentModelID)
        .listRowBackground(
            viewModel.highlightedMoleculeID == template.persistentModelID ? Color.yellow.opacity(0.2) : nil
        )
    }
    
    @ViewBuilder
    private func pendingRetirementRow(for template: MoleculeTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.title)
                    .font(.headline)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let deadline = template.undoDeadline {
                    Text(deadline, style: .timer)
                        .font(.caption)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .cornerRadius(8)
                }
            }
            
            HStack {
                if let reason = template.retirementReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Undo") {
                    RetirementService.shared.undoRetirement(template: template, context: modelContext)
                }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func retiredRow(for template: MoleculeTemplate) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(template.title)
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                if let date = template.retirementDate {
                    Text("Retired \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Menu {
                Button {
                    viewModel.duplicateMolecule(template, allTemplates: activeTemplates)
                } label: {
                    Label("Duplicate (Restart)", systemImage: "arrow.clockwise")
                }
                
                Button(role: .destructive) {
                    modelContext.delete(template) // Permanent delete
                    try? modelContext.save()
                    Task {
                        await AuditLogger.shared.logDelete(
                            entityType: .moleculeTemplate,
                            entityId: template.id.uuidString,
                            entityName: template.title
                        )
                    }
                } label: {
                    Label("Delete Permanently", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .padding()
            }
        }
    }
    
    
    // MARK: - Sub-Modifiers for Type-Checking
    
    struct DialogsSubModifier: ViewModifier {
        @ObservedObject var viewModel: TemplateListViewModel
        let templates: [MoleculeTemplate]
        
        func body(content: Content) -> some View {
            content
                .confirmationDialog("Actions", isPresented: $viewModel.showingBulkActionSheet) {
                    dialogButtons
                }
                .confirmationDialog("Generate Instances", isPresented: $viewModel.showingGenerateSheet, titleVisibility: .visible) {
                    generateButtons
                } message: {
                    Text("Generate instances for \(viewModel.selectedMoleculeIDs.count) selected molecule(s)")
                }
                .alert("Delete \(viewModel.selectedMoleculeIDs.count) Molecules?", isPresented: $viewModel.showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        viewModel.bulkDelete(templates: templates)
                    }
                } message: {
                    Text("This will delete the selected molecules and all their instances. This cannot be undone.")
                }
                .alert("Custom Duration", isPresented: $viewModel.showingCustomDurationAlert) {
                    TextField("Number of days", text: $viewModel.customDurationInput)
                        .keyboardType(.numberPad)
                    Button("Cancel", role: .cancel) { }
                    Button("Generate") {
                        if let days = Int(viewModel.customDurationInput), days > 0 {
                            viewModel.bulkGenerate(days: days, templates: templates)
                        }
                    }
                } message: {
                    Text("Enter the number of days to generate instances for.")
                }
        }
        
        @ViewBuilder
        private var dialogButtons: some View {
            Button("Delete Selected", role: .destructive) { viewModel.showingDeleteConfirmation = true }
            Button("Cancel", role: .cancel) { }
        }
        
        @ViewBuilder
        private var generateButtons: some View {
            Button("21 Days (Get the habit going)") { viewModel.bulkGenerate(days: 21, templates: templates) }
            Button("66 Days (Solidify the habit)") { viewModel.bulkGenerate(days: 66, templates: templates) }
            Button("Custom Duration...") {
                viewModel.customDurationInput = ""
                viewModel.showingCustomDurationAlert = true
            }
            Button("Time Machine (Backfill)...") { viewModel.showingBulkBackfillSheet = true }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    struct SheetsSubModifier: ViewModifier {
        @ObservedObject var viewModel: TemplateListViewModel
        let templates: [MoleculeTemplate]
        @Binding var templateToRetire: MoleculeTemplate?
        
        func body(content: Content) -> some View {
            content
                .sheet(isPresented: $viewModel.showingBulkBackfillSheet) {
                    backfillSheet
                }
                .alert("Backfill Complete", isPresented: $viewModel.showingBulkBackfillSuccess) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(viewModel.bulkBackfillMessage)
                }
                .sheet(isPresented: $viewModel.showingCreationOptions) {
                    creationOptionsSheet
                }
                .alert("Custom Duration", isPresented: $viewModel.showingCreationCustomAlert) {
                    TextField("Number of days", text: $viewModel.creationCustomDays)
                        .keyboardType(.numberPad)
                    Button("Cancel", role: .cancel) { }
                    Button("Generate") {
                        if let days = Int(viewModel.creationCustomDays), days > 0 {
                            viewModel.generateForNewTemplate(days: days)
                        }
                    }
                } message: {
                    Text("Enter the number of days to generate instances for.")
                }
                .alert("Schedule Created!", isPresented: $viewModel.showingCreationSuccess) {
                    Button("OK") { viewModel.newlyCreatedTemplate = nil }
                } message: {
                    Text(viewModel.creationSuccessMessage)
                }
                .sheet(item: $templateToRetire) { template in
                    RetirementConfigurationSheet(template: template) {
                        templateToRetire = nil
                    }
                }
        }
        
        private var backfillSheet: some View {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Start Date", selection: $viewModel.backfillStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $viewModel.backfillEndDate, displayedComponents: .date)
                    } footer: {
                        Text("Instances will be generated for every day in this range that matches the schedule.")
                    }
                    
                    Section {
                        Button("Generate Instances") {
                            viewModel.bulkBackfill(templates: templates)
                        }
                        .bold()
                    }
                }
                .navigationTitle("Time Machine")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.showingBulkBackfillSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        
        private var creationOptionsSheet: some View {
            NavigationStack {
                List {
                    Section {
                        if let template = viewModel.newlyCreatedTemplate {
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
                        Button { viewModel.generateForNewTemplate(days: 21) } label: {
                            Label("21 Days (Get the habit going)", systemImage: "flame")
                        }
                        Button { viewModel.generateForNewTemplate(days: 66) } label: {
                            Label("66 Days (Solidify the habit)", systemImage: "star.fill")
                        }
                        Button {
                            viewModel.creationCustomDays = ""
                            viewModel.showingCreationOptions = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                viewModel.showingCreationCustomAlert = true
                            }
                        } label: {
                            Label("Custom Duration...", systemImage: "number")
                        }
                    }
                    
                    Section {
                        Button {
                            viewModel.onSkipCreation()
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
                            viewModel.showingCreationOptions = false
                            viewModel.newlyCreatedTemplate = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Dialogs Modifier (Simplified)
    struct TemplateListDialogsModifierSimplified: ViewModifier {
        @ObservedObject var viewModel: TemplateListViewModel
        @ObservedObject private var retirementService = RetirementService.shared
        let templates: [MoleculeTemplate]
        let pinnedCount: Int
        @Binding var templateToRetire: MoleculeTemplate?
        
        func body(content: Content) -> some View {
            content
                .modifier(DialogsSubModifier(viewModel: viewModel, templates: templates))
                .modifier(SheetsSubModifier(viewModel: viewModel, templates: templates, templateToRetire: $templateToRetire))
                .overlay(alignment: .bottom) { undoToastOverlay }
                .overlay(alignment: .bottom) { processingToastOverlay }
                .onChange(of: viewModel.showingUndoToast) { _, isShowing in
                    if isShowing {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation {
                                viewModel.showingUndoToast = false
                                viewModel.undoTemplateId = nil
                            }
                        }
                    }
                }
        }
        
        @ViewBuilder
        private var processingToastOverlay: some View {
            if retirementService.isProcessing {
                HStack(spacing: 12) {
                    ProgressView().progressViewStyle(.circular)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Processing Retirement").font(.subheadline.weight(.semibold))
                        Text(retirementService.processingStatus).font(.caption).foregroundStyle(.secondary)
                        if retirementService.processingProgress > 0 {
                            ProgressView(value: retirementService.processingProgress).progressViewStyle(.linear).frame(width: 150)
                        }
                    }
                    Spacer()
                    Button("Cancel") { retirementService.cancelProcessing() }.font(.caption).foregroundStyle(.red)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding(.horizontal)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        
        @ViewBuilder
        private var undoToastOverlay: some View {
            if viewModel.showingUndoToast {
                HStack(spacing: 12) {
                    Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Archived").font(.subheadline).fontWeight(.semibold)
                        if !viewModel.undoBulkTemplateIds.isEmpty {
                            Text("\(viewModel.undoBulkTemplateIds.count) molecules").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(viewModel.undoTemplateName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        if !viewModel.undoBulkTemplateIds.isEmpty {
                            viewModel.undoBulkArchive()
                        } else {
                            viewModel.undoArchive()
                        }
                    } label: {
                        Text("Undo").fontWeight(.semibold).foregroundStyle(.blue)
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
}
