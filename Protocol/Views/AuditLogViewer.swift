//
//  AuditLogViewer.swift
//  Protocol
//
//  Debug view for viewing, filtering, and exporting audit logs.
//

import SwiftUI
import UniformTypeIdentifiers

struct AuditLogViewer: View {
    @State private var entries: [AuditLogEntry] = []
    @State private var isLoading = true
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var selectedEntry: AuditLogEntry?
    
    // MARK: - Filter State
    @State private var operationFilter: AuditOperation? = nil
    @State private var entityFilter: AuditEntityType? = nil
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate: Date = Date()
    @State private var showFilters = false
    
    // MARK: - Export State
    @State private var showingExportOptions = false
    @State private var csvExportURL: URL?
    @State private var shareItems: [Any] = []
    
    var filteredEntries: [AuditLogEntry] {
        entries.filter { entry in
            // Operation filter
            if let op = operationFilter, entry.operation != op {
                return false
            }
            // Entity filter
            if let entity = entityFilter, entry.entityType != entity {
                return false
            }
            // Date range filter
            if entry.timestamp < startDate || entry.timestamp > endDate {
                return false
            }
            return true
        }
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading logs...")
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Audit Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Data operations will be logged here for debugging.")
                )
            } else {
                VStack(spacing: 0) {
                    // Filter bar
                    if showFilters {
                        filterSection
                            .padding()
                            .background(Color(.systemGroupedBackground))
                    }
                    
                    // Results count
                    HStack {
                        Text("\(filteredEntries.count) of \(entries.count) entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
                    List {
                        ForEach(filteredEntries) { entry in
                            AuditLogRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showFilters.toggle()
                    } label: {
                        Label(showFilters ? "Hide Filters" : "Show Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    
                    Divider()
                    
                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(filteredEntries.isEmpty)
                    
                    Button {
                        exportAsCSV()
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    .disabled(filteredEntries.isEmpty)
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        clearLogs()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadEntries()
        }
        .refreshable {
            await loadEntries()
        }
        .sheet(item: $selectedEntry) { entry in
            AuditLogDetailView(entry: entry)
        }
        .sheet(isPresented: $showingExportSheet) {
            if !shareItems.isEmpty {
                ShareSheet(activityItems: shareItems)
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Operation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Operation", selection: $operationFilter) {
                    Text("All").tag(nil as AuditOperation?)
                    ForEach([AuditOperation.create, .update, .delete, .bulkCreate, .bulkDelete], id: \.self) { op in
                        Text(op.rawValue).tag(op as AuditOperation?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("Entity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Entity", selection: $entityFilter) {
                    Text("All").tag(nil as AuditEntityType?)
                    ForEach([AuditEntityType.moleculeTemplate, .moleculeInstance, .atomTemplate, .atomInstance, .workoutSet], id: \.self) { entity in
                        Text(entity.rawValue).tag(entity as AuditEntityType?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("Date Range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                    .font(.caption)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
            }
            
            Button("Reset Filters") {
                operationFilter = nil
                entityFilter = nil
                startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                endDate = Date()
            }
            .font(.caption)
        }
    }
    
    // MARK: - Actions
    
    private func loadEntries() async {
        isLoading = true
        entries = await AuditLogger.shared.getEntries()
        isLoading = false
    }
    
    private func exportAsJSON() {
        Task {
            if let data = await AuditLogger.shared.exportAsJSON() {
                shareItems = [data]
                showingExportSheet = true
            }
        }
    }
    
    private func exportAsCSV() {
        Task {
            let csv = generateCSV(from: filteredEntries)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_log.csv")
            do {
                try csv.write(to: tempURL, atomically: true, encoding: .utf8)
                shareItems = [tempURL]
                showingExportSheet = true
            } catch {
                AppLogger.audit.error("Failed to export CSV: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateCSV(from entries: [AuditLogEntry]) -> String {
        var csv = "Timestamp,Operation,Entity Type,Entity ID,Entity Name,Call Site,Changes,Additional Info\n"
        
        let dateFormatter = ISO8601DateFormatter()
        
        for entry in entries {
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let changes = entry.changes?.map { $0.description }.joined(separator: "; ") ?? ""
            let row = [
                timestamp,
                entry.operation.rawValue,
                entry.entityType.rawValue,
                entry.entityId,
                entry.entityName ?? "",
                entry.callSite,
                "\"\(changes)\"",
                entry.additionalInfo ?? ""
            ].joined(separator: ",")
            csv += row + "\n"
        }
        
        return csv
    }
    
    private func clearLogs() {
        Task {
            await AuditLogger.shared.clearAll()
            entries = []
        }
    }
}

// MARK: - Row View

struct AuditLogRow: View {
    let entry: AuditLogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                operationBadge
                
                Text(entry.entityType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(entry.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Text(entry.entityName ?? entry.entityId)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            
            if let changes = entry.changes, !changes.isEmpty {
                Text("\(changes.count) field\(changes.count == 1 ? "" : "s") changed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var operationBadge: some View {
        Text(entry.operation.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(operationColor)
            .cornerRadius(4)
    }
    
    private var operationColor: Color {
        switch entry.operation {
        case .create, .bulkCreate:
            return .green
        case .update:
            return .orange
        case .delete, .bulkDelete:
            return .red
        }
    }
}

// MARK: - Detail View

struct AuditLogDetailView: View {
    let entry: AuditLogEntry
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Operation") {
                    LabeledContent("Type", value: entry.operation.rawValue)
                    LabeledContent("Entity", value: entry.entityType.rawValue)
                    LabeledContent("ID", value: entry.entityId)
                    if let name = entry.entityName {
                        LabeledContent("Name", value: name)
                    }
                    LabeledContent("Time", value: entry.formattedTimestamp)
                }
                
                Section("Source") {
                    LabeledContent("Call Site", value: entry.callSite)
                    if let info = entry.additionalInfo {
                        LabeledContent("Info", value: info)
                    }
                }
                
                if let changes = entry.changes, !changes.isEmpty {
                    Section("Field Changes") {
                        ForEach(changes, id: \.field) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.field)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 8) {
                                    if let old = change.oldValue {
                                        Text(old)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                            .strikethrough()
                                    }
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    
                                    if let new = change.newValue {
                                        Text(new)
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("(nil)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Log Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        AuditLogViewer()
    }
}
