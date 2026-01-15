//
//  RetirementConfigurationSheet.swift
//  Protocol
//
//  Created on 2026-01-12.
//

import SwiftUI
import SwiftData

struct RetirementConfigurationSheet: View {
    @Bindable var template: MoleculeTemplate
    var onRetire: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Action Logic
    @State private var selectedReason: String = "Life Change"
    @State private var customReason: String = ""
    @State private var futureAction: String = "deleteAll"
    @State private var deleteAfterDate: Date = Date()
    @State private var showingPreview = false
    
    // Constants
    let reasons = ["Life Change", "Goal Reached", "Mistake", "Temporary Pause", "Other"]
    
    var effectiveReason: String {
        selectedReason == "Other" ? customReason : selectedReason
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: The Why
                Section("Why are you retiring this protocol?") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(reasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                    
                    if selectedReason == "Other" {
                        TextField("Enter reason...", text: $customReason)
                    }
                }
                
                // Section 2: Future Action
                Section("Future Instances") {
                    Picker("Action", selection: $futureAction) {
                        Text("Delete All Future").tag("deleteAll")
                        Text("Keep as Orphans").tag("keepAsOrphans")
                        Text("Delete After Date").tag("deleteAfterDate")
                    }
                    .pickerStyle(.inline)
                    
                    if futureAction == "deleteAfterDate" {
                        DatePicker("Delete After", selection: $deleteAfterDate, displayedComponents: .date)
                    }
                    
                    if futureAction == "keepAsOrphans" {
                        Text("Future instances will remain on your calendar but will be disconnected from this template.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Section 3: Summary Preview
                Section("Preview") {
                    PreviewSummaryView(template: template, futureAction: futureAction, deleteAfterDate: deleteAfterDate)
                }
                
                // Section 4: Consequences
                Section {
                   Text("You will have 24 hours to undo this action. After that, retirement is permanent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Retire Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Retirement") {
                        retireMolecule()
                    }
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
                    .disabled(selectedReason == "Other" && customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func retireMolecule() {
        RetirementService.shared.initiateRetirement(
            template: template,
            reason: effectiveReason,
            futureAction: futureAction,
            deleteAfterDate: deleteAfterDate,
            context: modelContext
        )
        onRetire()
    }
}

struct PreviewSummaryView: View {
    let template: MoleculeTemplate
    let futureAction: String
    let deleteAfterDate: Date
    
    var futureInstancesCount: Int {
        template.instances.filter { $0.scheduledDate > Date() }.count
    }
    
    var impactedCount: Int {
        let now = Date()
        if futureAction == "deleteAll" || futureAction == "keepAsOrphans" {
            return template.instances.filter { $0.scheduledDate > now }.count
        } else if futureAction == "deleteAfterDate" {
            return template.instances.filter { $0.scheduledDate > deleteAfterDate }.count
        }
        return 0
    }
    
    var impactDescription: String {
        switch futureAction {
        case "deleteAll":
            return "deleted"
        case "keepAsOrphans":
            return "orphaned"
        case "deleteAfterDate":
            return "deleted"
        default:
            return "affected"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(impactedCount) Instances")
                    .font(.headline)
                Text("will be \(impactDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if futureAction == "keepAsOrphans" {
                Text("👶")
                    .font(.largeTitle)
            } else {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
        }
    }
}
