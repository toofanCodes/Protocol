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
    @Query(filter: #Predicate<MoleculeTemplate> { !$0.isArchived }) private var templates: [MoleculeTemplate]
    
    @StateObject private var viewModel = TemplateListViewModel()
    
    // Sorted/organized templates
    private var sortedTemplates: [MoleculeTemplate] {
        viewModel.sortedTemplates(from: templates)
    }
    
    private var pinnedCount: Int {
        templates.filter { $0.isPinned }.count
    }
    
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
                .modifier(TemplateListDialogsModifier(
                    viewModel: viewModel,
                    templates: templates,
                    pinnedCount: pinnedCount
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
                            viewModel.addTemplate(allTemplates: templates)
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
                ScrollViewReader { proxy in
                    List {
                        if !sortedTemplates.filter({ $0.isPinned }).isEmpty {
                            Section {
                                ForEach(sortedTemplates.filter { $0.isPinned }) { template in
                                    templateRow(for: template)
                                }
                                .onMove(perform: { source, destination in
                                    viewModel.movePinnedTemplates(from: source, to: destination, in: sortedTemplates)
                                })
                            } header: {
                                Label("Pinned", systemImage: "pin.fill")
                            }
                        }
                        
                        Section {
                            ForEach(sortedTemplates.filter { !$0.isPinned }) { template in
                                templateRow(for: template)
                            }
                            .onMove(perform: viewModel.sortOption == .manual ? { source, destination in
                                viewModel.moveUnpinnedTemplates(from: source, to: destination, in: sortedTemplates)
                            } : nil)
                        } header: {
                            if !sortedTemplates.filter({ $0.isPinned }).isEmpty {
                                Text("All Protocols")
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
                        viewModel.addTemplate(allTemplates: templates)
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
            if !templates.isEmpty {
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
    
    // MARK: - Row View
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
                viewModel.undoTemplateId = templateId
                viewModel.undoTemplateName = templateName
                withAnimation {
                    viewModel.showingUndoToast = true
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                viewModel.duplicateMolecule(template, allTemplates: templates)
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
}

// MARK: - Dialogs Modifier
struct TemplateListDialogsModifier: ViewModifier {
    @ObservedObject var viewModel: TemplateListViewModel
    let templates: [MoleculeTemplate]
    let pinnedCount: Int
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Actions", isPresented: $viewModel.showingBulkActionSheet) {
                bulkActionsButtons
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
                Button("OK") {
                    viewModel.newlyCreatedTemplate = nil
                }
            } message: {
                Text(viewModel.creationSuccessMessage)
            }
            .overlay(alignment: .bottom) { undoToastOverlay }
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
    private var bulkActionsButtons: some View {
        let selectedTemplates = templates.filter { viewModel.selectedMoleculeIDs.contains($0.persistentModelID) }
        let allPinned = selectedTemplates.allSatisfy { $0.isPinned }
        let canPin = pinnedCount + selectedTemplates.filter { !$0.isPinned }.count <= 3
        
        if allPinned {
            Button("Unpin Selected") { viewModel.bulkUnpin(templates: templates) }
        } else if canPin {
            Button("Pin Selected") { viewModel.bulkPin(templates: templates, pinnedCount: pinnedCount) }
        }
        
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
    
    private var backfillSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start Date", selection: $viewModel.backfillStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $viewModel.backfillEndDate, displayedComponents: .date)
                } footer: {
                    Text("Instances will be generated for every day in this range that matches the schedule of the \(viewModel.selectedMoleculeIDs.count) selected protocols.")
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
                        // Delay alert to allow sheet to dismiss
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
    
    @ViewBuilder
    private var undoToastOverlay: some View {
        if viewModel.showingUndoToast {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archived")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    if !viewModel.undoBulkTemplateIds.isEmpty {
                        Text("\(viewModel.undoBulkTemplateIds.count) molecules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.undoTemplateName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
