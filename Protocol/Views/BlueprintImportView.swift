//
//  BlueprintImportView.swift
//  Protocol
//
//  Blueprint Architect - Import habits via CSV with validation feedback.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BlueprintImportView: View {
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - State
    
    enum ImportState {
        case idle
        case analyzing
        case results(ImportReport)
    }
    
    @State private var importState: ImportState = .idle
    @State private var showingFileImporter = false
    @State private var showingShareSheet = false
    @State private var showingConfirmation = false
    @State private var templateURL: URL?
    
    private let csvManager = CSVManager()
    
    // MARK: - Body
    
    var body: some View {
        List {
            switch importState {
            case .idle:
                idleSection
                
            case .analyzing:
                Section {
                    HStack {
                        ProgressView()
                        Text("Analyzing blueprint...")
                            .foregroundStyle(.secondary)
                    }
                }
                
            case .results(let report):
                resultsSection(report: report)
            }
            
            troubleshootingSection
        }
        .navigationTitle("Blueprint Architect")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = templateURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    // MARK: - State A: Idle
    
    private var idleSection: some View {
        Group {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Blueprint Architect")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Bulk-create habits by importing a CSV file. Download the template to see the required format.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            
            Section {
                Button {
                    downloadTemplate()
                } label: {
                    Label("Download Template", systemImage: "arrow.down.doc")
                }
                
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Upload Blueprint", systemImage: "arrow.up.doc")
                }
            } header: {
                Text("Actions")
            }
        }
    }
    
    // MARK: - State B: Results
    
    @ViewBuilder
    private func resultsSection(report: ImportReport) -> some View {
        // Validation Issues (Red)
        if !report.errors.isEmpty {
            Section {
                ForEach(report.errors) { error in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Row \(error.rowNumber)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                            
                            Text(error.userGuidance)
                                .font(.subheadline)
                        }
                        
                        Text(error.rawContent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Label("Validation Issues (\(report.errors.count))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        
        // Ready to Build (Green)
        if !report.validItems.isEmpty {
            Section {
                ForEach(report.validItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 8) {
                                if item.isAllDay {
                                    Text("All Day")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(item.time.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                if !item.atoms.isEmpty {
                                    Text("\(item.atoms.count) atoms")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Label("Ready to Build (\(report.validItems.count))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        
        // Action Buttons
        Section {
            Button {
                if report.hasErrors {
                    showingConfirmation = true
                } else {
                    commitItems(report.validItems)
                }
            } label: {
                HStack {
                    Spacer()
                    Label("Build Empire", systemImage: "hammer.fill")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(report.validItems.isEmpty)
            .alert("Import with Errors?", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Import \(report.validItems.count) Items") {
                    commitItems(report.validItems)
                }
            } message: {
                Text("Import \(report.validItems.count) valid items and skip \(report.errors.count) errors?")
            }
            
            Button(role: .destructive) {
                importState = .idle
            } label: {
                HStack {
                    Spacer()
                    Text("Start Over")
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Troubleshooting
    
    private var troubleshootingSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    troubleshootingItem(
                        title: "CSV Format",
                        detail: "Time,MoleculeName,Atoms,IsAllDay"
                    )
                    troubleshootingItem(
                        title: "Time Format",
                        detail: "Use HH:mm (e.g., 14:30) or h:mm a (e.g., 2:30 PM)"
                    )
                    troubleshootingItem(
                        title: "Atoms Separator",
                        detail: "Use pipe | to separate atoms, not commas"
                    )
                    troubleshootingItem(
                        title: "All Day Events",
                        detail: "Use true/false, yes/no, or 1/0"
                    )
                    troubleshootingItem(
                        title: "European CSV",
                        detail: "Semicolons (;) are auto-detected as delimiters"
                    )
                }
                .padding(.vertical, 8)
            } label: {
                Label("Troubleshooting Guide", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Help")
        }
    }
    
    private func troubleshootingItem(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func downloadTemplate() {
        let template = csvManager.generateTemplate()
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("Protocol_Blueprint_Template.csv")
        
        do {
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
            templateURL = fileURL
            showingShareSheet = true
        } catch {
            print("Failed to create template file: \(error)")
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            importState = .analyzing
            
            // Read file content
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let report = csvManager.analyze(csvString: content)
                importState = .results(report)
            } catch {
                // Try other encodings
                if let content = try? String(contentsOf: url, encoding: .isoLatin1) {
                    let report = csvManager.analyze(csvString: content)
                    importState = .results(report)
                } else {
                    importState = .idle
                }
            }
            
        case .failure:
            importState = .idle
        }
    }
    
    private func commitItems(_ items: [ParsedMolecule]) {
        let _ = csvManager.commit(items: items, context: modelContext)
        importState = .idle
    }
}

#Preview {
    NavigationStack {
        BlueprintImportView()
    }
}
