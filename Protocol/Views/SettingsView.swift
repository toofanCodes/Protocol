//
//  SettingsView.swift
//  Protocol
//
//  Created on 2026-01-01.
//

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Reminder Offset Options

enum ReminderOffset: Int, CaseIterable, Identifiable {
    case none = -1
    case atTime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .atTime: return "At time"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationManager = NotificationManager.shared
    
    // User Preferences
    @AppStorage("defaultReminderOffset") private var defaultReminderOffset: Int = 15
    @AppStorage("showAppIconBadge") private var showAppIconBadge: Bool = true
    
    // Alert States
    @State private var showingResyncAlert = false
    @State private var showingNukeConfirmation = false
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Section 1: Notifications
                Section {
                    // Status Indicator
                    HStack {
                        Text("Status")
                        Spacer()
                        if notificationManager.isAuthorized {
                            Text("Active")
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        } else {
                            Text("Disabled")
                                .foregroundStyle(.red)
                                .fontWeight(.medium)
                        }
                    }
                    
                    // Open Settings button if denied
                    if !notificationManager.isAuthorized {
                        Button {
                            openAppSettings()
                        } label: {
                            Label("Enable in Settings", systemImage: "gear")
                        }
                    }
                    
                    // Default Reminder Picker
                    Picker("Default Reminder", selection: $defaultReminderOffset) {
                        ForEach(ReminderOffset.allCases) { offset in
                            Text(offset.displayName).tag(offset.rawValue)
                        }
                    }
                    
                    // Badge Toggle
                    Toggle("Show App Icon Badge", isOn: $showAppIconBadge)
                    
                    // Re-sync Alerts
                    Button {
                        resyncAlerts()
                    } label: {
                        Label("Re-sync Alerts", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Label("Notifications", systemImage: "bell.badge")
                } footer: {
                    Text("The Command Center for all your alerts.")
                }
                
                // MARK: - Section 1.5: Celebrations
                Section {
                    Toggle(isOn: Binding(
                        get: { SoundManager.shared.isSoundEnabled },
                        set: { SoundManager.shared.isSoundEnabled = $0 }
                    )) {
                        Label("Sound Effects", systemImage: "speaker.wave.2")
                    }
                    
                    if SoundManager.shared.isSoundEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Volume")
                                .font(.subheadline)
                            HStack {
                                Image(systemName: "speaker.fill")
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { Double(SoundManager.shared.volume) },
                                        set: { SoundManager.shared.volume = Float($0) }
                                    ),
                                    in: 0...1,
                                    step: 0.1
                                )
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Toggle(isOn: Binding(
                        get: { SoundManager.shared.isHapticEnabled },
                        set: { SoundManager.shared.isHapticEnabled = $0 }
                    )) {
                        Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                } header: {
                    Label("Celebrations", systemImage: "party.popper")
                } footer: {
                    Text("Customize the fanfare when you complete habits.")
                }
                
                // MARK: - Section 2: Resources
                Section {
                    NavigationLink {
                        FieldManualView()
                    } label: {
                        Label("Field Manual", systemImage: "book.closed")
                    }
                    
                    // About Row
                    HStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Protocol")
                                .font(.headline)
                            Text("Version 1.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Designed by Saran Pavuluri")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Resources", systemImage: "folder")
                }
                
                // MARK: - Section 3: Data Management
                Section {
                    Button {
                        exportAllData()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Label("Data Management", systemImage: "externaldrive")
                } footer: {
                    Text("Export all your molecules and instances as JSON.")
                }
                
                // MARK: - Section 4: Support
                Section {
                    Button {
                        sendFeedback()
                    } label: {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                    
                    Link(destination: URL(string: "https://protocol-app.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Label("Support", systemImage: "questionmark.circle")
                }
                
                // MARK: - Section 5: Architect Tools
                Section {
                    NavigationLink {
                        BlueprintImportView()
                    } label: {
                        Label("Blueprint Architect", systemImage: "doc.text")
                    }
                } header: {
                    Label("Architect Tools", systemImage: "hammer")
                } footer: {
                    Text("Import habits in bulk via CSV files.")
                }
                
                // MARK: - Section 6: Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingNukeConfirmation = true
                    } label: {
                        Label("Nuke Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Danger Zone")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("This will permanently delete ALL your data. This action cannot be undone.")
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .listStyle(.grouped)
            .navigationTitle("HQ")
            .onAppear {
                Task {
                    await notificationManager.checkAuthorization()
                }
            }
            .alert("Alerts Synced", isPresented: $showingResyncAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("All upcoming notifications have been refreshed.")
            }
            .alert("Delete All Data?", isPresented: $showingNukeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    nukeAllData()
                }
            } message: {
                Text("This will permanently delete all your molecules, instances, and settings. This action cannot be undone.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let data = exportData {
                    ShareSheet(activityItems: [data])
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func resyncAlerts() {
        Task {
            await NotificationManager.shared.refreshUpcomingNotifications(context: modelContext)
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            showingResyncAlert = true
        }
    }
    
    private func exportAllData() {
        // Fetch all data
        let templateDescriptor = FetchDescriptor<MoleculeTemplate>()
        let instanceDescriptor = FetchDescriptor<MoleculeInstance>()
        
        do {
            let templates = try modelContext.fetch(templateDescriptor)
            let instances = try modelContext.fetch(instanceDescriptor)
            
            // Create export structure
            let exportDict: [String: Any] = [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "appVersion": "1.0",
                "templates": templates.map { template in
                    [
                        "id": template.id.uuidString,
                        "title": template.title,
                        "notes": template.notes ?? "",
                        "compound": template.compound ?? "",
                        "recurrenceFreq": template.recurrenceFreq.rawValue,
                        "recurrenceDays": template.recurrenceDays,
                        "atomCount": template.atomTemplates.count
                    ] as [String: Any]
                },
                "instances": instances.map { instance in
                    [
                        "id": instance.id.uuidString,
                        "title": instance.displayTitle,
                        "scheduledDate": ISO8601DateFormatter().string(from: instance.scheduledDate),
                        "isCompleted": instance.isCompleted,
                        "atomCount": instance.atomInstances.count
                    ] as [String: Any]
                }
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
            exportData = jsonData
            showingExportSheet = true
            
        } catch {
            print("❌ Export failed: \(error)")
        }
    }
    
    private func sendFeedback() {
        let subject = "Protocol Feedback"
        let email = "support@yourdomain.com"
        let urlString = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func nukeAllData() {
        do {
            // Delete all MoleculeInstances first (due to relationships)
            let instanceDescriptor = FetchDescriptor<MoleculeInstance>()
            let instances = try modelContext.fetch(instanceDescriptor)
            for instance in instances {
                NotificationManager.shared.cancelNotification(for: instance)
                modelContext.delete(instance)
            }
            
            // Delete all MoleculeTemplates
            let templateDescriptor = FetchDescriptor<MoleculeTemplate>()
            let templates = try modelContext.fetch(templateDescriptor)
            for template in templates {
                modelContext.delete(template)
            }
            
            // Save changes
            try modelContext.save()
            
            // Cancel all remaining notifications
            NotificationManager.shared.cancelAllNotifications()
            
            // Reset UserDefaults
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
        } catch {
            print("❌ Failed to nuke data: \(error)")
        }
    }
}

// MARK: - Field Manual View

struct FieldManualView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero Section
                VStack(spacing: 12) {
                    Image(systemName: "atom")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("The Protocol System")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Master your habits with molecular precision")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                
                Divider()
                
                // Molecules Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Molecules", systemImage: "circle.hexagongrid")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("A **Molecule** is your recurring habit or routine. Think of it as the container that holds all your related tasks together.")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("**Examples:**")
                            .font(.callout)
                        Text("• 🏋️ Morning Workout")
                        Text("• 📚 Evening Reading")
                        Text("• 🧘 Meditation Practice")
                        Text("• 💊 Supplement Stack")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Atoms Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Atoms", systemImage: "atom")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("**Atoms** are the individual tasks within a Molecule. They're the atomic units of action that make up your habit.")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("**Types of Atoms:**")
                            .font(.callout)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                            Text("**Binary** – Simple yes/no tasks")
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "number.circle")
                                .foregroundStyle(.blue)
                            Text("**Counter** – Track reps or counts")
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "number.square")
                                .foregroundStyle(.purple)
                            Text("**Value** – Log specific numbers (weight, duration)")
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Workflow Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("The Workflow", systemImage: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        WorkflowStep(number: 1, title: "Create a Molecule", description: "Define your recurring habit with a schedule")
                        WorkflowStep(number: 2, title: "Add Atoms", description: "Break it down into specific, trackable tasks")
                        WorkflowStep(number: 3, title: "Generate Instances", description: "Auto-create scheduled occurrences")
                        WorkflowStep(number: 4, title: "Execute & Track", description: "Complete atoms as you go, track your progress")
                    }
                }
                
                Divider()
                
                // Pro Tips
                VStack(alignment: .leading, spacing: 12) {
                    Label("Pro Tips", systemImage: "lightbulb")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💡 **21 days** to form the habit, **66 days** to make it automatic")
                        Text("💡 Use **Compounds** to group related molecules")
                        Text("💡 Set multiple **alerts** for important habits")
                        Text("💡 Check the **Insights** tab to see your progress")
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Field Manual")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workflow Step Component

struct WorkflowStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Share Sheet (UIKit Bridge)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: [MoleculeTemplate.self, MoleculeInstance.self], inMemory: true)
}
