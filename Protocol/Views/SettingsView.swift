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

enum BackupFrequency: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case manual = "Manual"
    
    var id: String { rawValue }

}

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationManager = NotificationManager.shared
    
    // User Preferences
    @AppStorage("defaultReminderOffset") private var defaultReminderOffset: Int = 15
    @AppStorage("showAppIconBadge") private var showAppIconBadge: Bool = true
    @AppStorage("backupFrequency") private var backupFrequency: BackupFrequency = .daily
    
    // Alert States
    @State private var showingResyncConfirmation = false
    @State private var showingResyncSuccess = false
    
    @State private var showingBackupConfirmation = false
    @State private var showingBackupSuccess = false
    
    @State private var showingSeedConfirmation = false
    @State private var showingSeedSuccess = false
    
    @State private var showingNukeConfirmation = false
    @State private var showingNukeSuccess = false
    
    @State private var showingRestoreConfirmation = false
    @State private var showingRestoreSuccess = false
    
    @State private var shareItem: ShareItem?
    
    // Backup State
    @StateObject private var backupManager = BackupManager.shared
    @State private var availableBackups: [URL] = []
    @State private var isBackingUp = false
    @State private var backupToRestore: URL?
    
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
                        showingResyncConfirmation = true
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
                
                // MARK: - Section 3: Backups
                Section {
                    Button {
                        showingBackupConfirmation = true
                    } label: {
                        HStack {
                            Label("Create Backup", systemImage: "arrow.down.doc")
                            Spacer()
                            if isBackingUp {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isBackingUp)
                    
                    Picker("Auto-Backup Frequency", selection: $backupFrequency) {
                        ForEach(BackupFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    
                    if !availableBackups.isEmpty {
                        ForEach(availableBackups, id: \.self) { url in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent.replacingOccurrences(of: "backup_", with: "").replacingOccurrences(of: ".json", with: ""))
                                        .font(.caption)
                                    Text(getFileSize(url: url))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Restore") {
                                    backupToRestore = url
                                    showingRestoreConfirmation = true
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                
                                Button {
                                    shareItem = ShareItem(items: [url])
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .onDelete(perform: deleteBackups)
                    } else {
                        Text("No backups found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Label("Backups", systemImage: "externaldrive")
                        if backupManager.isCloudEnabled {
                            Image(systemName: "icloud.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text(backupManager.isCloudEnabled ? "Backups are automatically saved to your iCloud Drive (Documents)." : "Backups are saved locally. Enable iCloud Drive for off-site protection.")
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
                    
                    NavigationLink {
                        AuditLogViewer()
                    } label: {
                        Label("Audit Log", systemImage: "doc.text.magnifyingglass")
                    }
                    
                    Button {
                        showingSeedConfirmation = true
                    } label: {
                        Label("Restore Default Protocols", systemImage: "arrow.counterclockwise.circle")
                    }
                } header: {
                    Label("Architect Tools", systemImage: "hammer")
                } footer: {
                    Text("Import habits in bulk or view data operation logs.")
                }
                
                // MARK: - Section 6: Danger Zone
                Section {
                    NavigationLink {
                        OrphanManagerView()
                    } label: {
                        Label("Lost & Found (Recovery)", systemImage: "lifepreserver")
                            .foregroundStyle(.orange)
                    }
                    
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
                    Text("Cleanup removes 'Untitled' orphan instances. Nuke permanently deletes ALL data.")
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .listStyle(.grouped)
            .navigationTitle("HQ")
            .onAppear {
                Task {
                    await notificationManager.checkAuthorization()
                    loadBackups() // Load backups when view appears
                }
            }
            
            // MARK: - Alerts
            
            // Re-sync Alerts
            .alert("Resync Alerts?", isPresented: $showingResyncConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Resync", role: .none) {
                    resyncAlerts()
                }
            } message: {
                Text("This will refresh all pending notifications based on your current schedule. Are you sure?")
            }
            .alert("Success", isPresented: $showingResyncSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("All alerts have been successfully resynchronized.")
            }

            // Create Backup
            .alert("Create Backup?", isPresented: $showingBackupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Create", role: .none) {
                    createBackup()
                }
            } message: {
                Text("This will save a snapshot of your current data. Do you want to proceed?")
            }
            .alert("Backup Created", isPresented: $showingBackupSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your data has been successfully backed up.")
            }

            // Restore Defaults
            .alert("Restore Protocols?", isPresented: $showingSeedConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Restore", role: .none) {
                    seedDefaultProtocols()
                }
            } message: {
                Text("This will add the default set of example habits to your library. It won't delete existing data.")
            }
            .alert("Protocols Restored", isPresented: $showingSeedSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Default protocols have been added to your library.")
            }

            // Restore Backup
            .alert("Restore Backup?", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Restore", role: .destructive) {
                    if let url = backupToRestore {
                        restoreBackup(url)
                    }
                }
            } message: {
                Text("This will REPLACE ALL current data with the backup. This action cannot be undone. Are you sure?")
            }
            .alert("Restore Complete", isPresented: $showingRestoreSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your data has been restored from the backup.")
            }

            // Nuke Data
            .alert("Nuke All Data?", isPresented: $showingNukeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Nuke Everything", role: .destructive) {
                    nukeAllData()
                }
            } message: {
                Text("WARNING: This will permanently delete ALL molecules, history, and settings. This cannot be undone.")
            }
            .alert("Data Nuked", isPresented: $showingNukeSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("All data has been erased. You have a clean slate.")
            }
            
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: item.items)
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
            
            showingResyncSuccess = true
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

            shareItem = ShareItem(items: [jsonData])
            
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
    
    private func seedDefaultProtocols() {
        let manager = OnboardingManager(modelContext: modelContext)
        manager.forceSeedData()
        
        // Audit log
        Task {
            await AuditLogger.shared.logBulkCreate(
                entityType: .moleculeTemplate,
                count: 5, // Approx count
                additionalInfo: "User triggered Restore Default Protocols"
            )
            
            showingSeedSuccess = true
        }
    }
    
    // MARK: - Backup Operations
    
    private func loadBackups() {
        availableBackups = backupManager.listBackups()
    }
    
    private func createBackup() {
        Task {
            isBackingUp = true
            do {
                _ = try await backupManager.createBackup(context: modelContext)
                loadBackups()
                showingBackupSuccess = true
            } catch {
                print("Backup failed: \(error)")
            }
            isBackingUp = false
        }
    }
    
    private func deleteBackups(at offsets: IndexSet) {
        let urls = offsets.map { availableBackups[$0] }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        loadBackups()
    }
    
    private func restoreBackup(_ url: URL) {
        Task {
            do {
                try await backupManager.restore(from: url, context: modelContext)
                
                // Audit log
                await AuditLogger.shared.logBulkCreate(
                    entityType: .moleculeTemplate,
                    count: 1, // Summary count
                    additionalInfo: "Restored from backup: \(url.lastPathComponent)"
                )
                
                showingRestoreSuccess = true
                
            } catch {
                print("Restore failed: \(error)")
            }
        }
    }
    
    private func getFileSize(url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    // Export function replaced by BackupManager
    // private func exportAllData() { ... }
    
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
            
            showingNukeSuccess = true
            
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
