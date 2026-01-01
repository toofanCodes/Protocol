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
        }
    }
}

// MARK: - Template List View
struct TemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [MoleculeTemplate]
    
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
                        ForEach(templates) { template in
                            NavigationLink(value: template) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(template.title)
                                            .font(.headline)
                                        Spacer()
                                        if !template.atomTemplates.isEmpty {
                                            Text("\(template.atomTemplates.count) tasks")
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
                                    
                                    if let notes = template.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete(perform: deleteTemplates)
                    }
                }
            }
            .navigationTitle("Protocols")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addTemplate()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: MoleculeTemplate.self) { template in
                MoleculeTemplateDetailView(template: template)
            }
        }
    }
    
    private func addTemplate() {
        withAnimation {
            let newTemplate = MoleculeTemplate(
                title: "New Molecule",
                baseTime: Date(),
                recurrenceFreq: .daily
            )
            modelContext.insert(newTemplate)
        }
    }
    
    private func deleteTemplates(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(templates[index])
            }
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
    
    private var sortedAtomTemplates: [AtomTemplate] {
        template.atomTemplates.sorted { $0.order < $1.order }
    }
    
    private var uniqueCompounds: [String] {
        Array(Set(allTemplates.compactMap { $0.compound })).sorted()
    }
    
    var body: some View {
        List {
            // Template Info Section
            Section("Template Info") {
                TextField("Title", text: $template.title)
                
                DatePicker(
                    "Base Time",
                    selection: $template.baseTime,
                    displayedComponents: .hourAndMinute
                )
                
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
                Text("Atoms are cloned to each instance when generated.")
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
        HStack(spacing: 12) {
            Image(systemName: atom.inputType.iconName)
                .font(.title3)
                .foregroundColor(Color.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(atom.title)
                    .font(.body)
                
                HStack(spacing: 4) {
                    Text(atom.inputType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let target = atom.targetDisplayString {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("Target: \(target)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Molecule Instance Detail View

struct MoleculeInstanceDetailView: View {
    @Bindable var instance: MoleculeInstance
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MoleculeTemplate.title) private var templates: [MoleculeTemplate]
    
    @State private var atomForValueEntry: AtomInstance?
    @State private var atomForWorkoutLog: AtomInstance?
    
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
        }
        .navigationTitle(instance.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $atomForValueEntry) { atom in
            AtomValueEntrySheet(atom: atom)
        }
        .sheet(item: $atomForWorkoutLog) { atom in
            AtomDetailSheet(atom: atom)
        }
        .onChange(of: sortedAtoms.map(\.isCompleted)) { _, newValue in
            // Auto-complete instance when all atoms are done
            let allCompleted = !instance.atomInstances.isEmpty && instance.atomInstances.allSatisfy(\.isCompleted)
            if allCompleted && !instance.isCompleted {
                instance.markComplete()
                NotificationManager.shared.cancelNotification(for: instance)
            } else if !allCompleted && instance.isCompleted {
                instance.markIncomplete()
            }
            try? modelContext.save()
        }
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
