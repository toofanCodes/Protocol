//
//  AuditLogViewer.swift
//  Protocol
//
//  Debug view for viewing and exporting audit logs.
//

import SwiftUI

struct AuditLogViewer: View {
    @State private var entries: [AuditLogEntry] = []
    @State private var isLoading = true
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var selectedEntry: AuditLogEntry?
    
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
                List {
                    ForEach(entries) { entry in
                        AuditLogRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEntry = entry
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
                        exportLogs()
                    } label: {
                        Label("Export Logs", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                    
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
            if let data = exportData {
                ShareSheet(activityItems: [data])
            }
        }
    }
    
    private func loadEntries() async {
        isLoading = true
        entries = await AuditLogger.shared.getEntries()
        isLoading = false
    }
    
    private func exportLogs() {
        Task {
            if let data = await AuditLogger.shared.exportAsJSON() {
                exportData = data
                showingExportSheet = true
            }
        }
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
