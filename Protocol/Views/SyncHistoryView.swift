//
//  SyncHistoryView.swift
//  Protocol
//
//  Displays sync history for debugging and user visibility.
//

import SwiftUI

/// View showing sync history with export capability
struct SyncHistoryView: View {
    @State private var entries: [SyncHistoryEntry] = []
    @State private var showExportSheet = false
    @State private var exportData: Data?
    
    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Sync History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sync history will appear here after your first sync.")
                )
            } else {
                ForEach(entries) { entry in
                    SyncHistoryRow(entry: entry)
                }
            }
        }
        .navigationTitle("Sync History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportHistory()
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                    
                    Button(role: .destructive) {
                        SyncHistoryManager.shared.clearHistory()
                        entries = []
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .disabled(entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            entries = SyncHistoryManager.shared.entries
        }
        .sheet(isPresented: $showExportSheet) {
            if let data = exportData {
                ShareSheet(activityItems: [data])
            }
        }
    }
    
    private func exportHistory() {
        if let data = SyncHistoryManager.shared.exportJSON() {
            exportData = data
            showExportSheet = true
        }
    }
}

// MARK: - Sync History Row

struct SyncHistoryRow: View {
    let entry: SyncHistoryEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack {
                statusIcon
                    .font(.system(size: 14))
                
                Text(entry.action.displayName)
                    .font(.system(size: 15, weight: .semibold))
                
                Spacer()
                
                Text(entry.timestamp, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            // Stats row
            HStack(spacing: 12) {
                Label("\(entry.recordsDownloaded)", systemImage: "arrow.down.circle")
                Label("\(entry.recordsUploaded)", systemImage: "arrow.up.circle")
                Label("\(entry.durationMs)ms", systemImage: "clock")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            
            // Error message if failed
            if let errorMessage = entry.errorMessage {
                HStack(spacing: 4) {
                    if let code = entry.errorCode {
                        Text(code)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(4)
                    }
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            
            // Details if present
            if !entry.details.isEmpty {
                Text(entry.details)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .success:
            Image(systemName: entry.status.systemImage)
                .foregroundStyle(.green)
        case .partialSuccess:
            Image(systemName: entry.status.systemImage)
                .foregroundStyle(.yellow)
        case .failed:
            Image(systemName: entry.status.systemImage)
                .foregroundStyle(.red)
        case .cancelled, .skipped:
            Image(systemName: entry.status.systemImage)
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SyncHistoryView()
    }
}
