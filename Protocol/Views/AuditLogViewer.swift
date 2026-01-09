//
//  AuditLogViewer.swift
//  Protocol
//
//  Debug view for viewing, filtering, and exporting audit logs.
//

import SwiftUI
import UniformTypeIdentifiers

struct AuditLogViewer: View {
    @StateObject private var viewModel = AuditLogViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading logs...")
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No Audit Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Data operations will be logged here for debugging.")
                )
            } else {
                VStack(spacing: 0) {
                    // Filter bar
                    if viewModel.showFilters {
                        filterSection
                            .padding()
                            .background(Color(.systemGroupedBackground))
                    }
                    
                    // Results count
                    HStack {
                        Text(viewModel.resultCountText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
                    List {
                        ForEach(viewModel.filteredEntries) { entry in
                            AuditLogRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedEntry = entry
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
                        viewModel.showFilters.toggle()
                    } label: {
                        Label(viewModel.showFilters ? "Hide Filters" : "Show Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    
                    Divider()
                    
                    Button {
                        viewModel.exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(viewModel.filteredEntries.isEmpty)
                    
                    Button {
                        viewModel.exportAsCSV()
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    .disabled(viewModel.filteredEntries.isEmpty)
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        viewModel.clearLogs()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(viewModel.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadEntries()
            }
        }
        .refreshable {
            await viewModel.loadEntries()
        }
        .sheet(item: $viewModel.selectedEntry) { entry in
            AuditLogDetailView(entry: entry)
        }
        .sheet(isPresented: $viewModel.showingExportSheet) {
            if !viewModel.shareItems.isEmpty {
                ShareSheet(activityItems: viewModel.shareItems)
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
                Picker("Operation", selection: $viewModel.operationFilter) {
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
                Picker("Entity", selection: $viewModel.entityFilter) {
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
                DatePicker("From", selection: $viewModel.startDate, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                    .font(.caption)
                DatePicker("To", selection: $viewModel.endDate, displayedComponents: .date)
                    .labelsHidden()
            }
            
            Button("Reset Filters") {
                viewModel.resetFilters()
            }
            .font(.caption)
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
