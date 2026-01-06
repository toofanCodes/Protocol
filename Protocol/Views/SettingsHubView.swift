//
//  SettingsHubView.swift
//  Protocol
//
//  A clean hub menu for navigating Settings categories.
//

import SwiftUI
import SwiftData

struct SettingsHubView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    settingsCards
                }
                .padding()
                
                appInfoFooter
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Settings")
        }
        .onAppear {
            Task {
                await notificationManager.checkAuthorization()
            }
        }
    }
    
    private var settingsCards: some View {
        Group {
            // Notifications
            SettingsCardLink(
                destination: NotificationsSettingsView(),
                icon: "bell.badge.fill",
                title: "Notifications",
                subtitle: notificationManager.isAuthorized ? "Active" : "Disabled",
                color: .blue
            )
            
            // Celebrations
            SettingsCardLink(
                destination: CelebrationsSettingsView(),
                icon: "party.popper.fill",
                title: "Celebrations",
                subtitle: "Sound & Haptics",
                color: .orange
            )
            
            // Backups
            SettingsCardLink(
                destination: BackupsSettingsView(),
                icon: "icloud.fill",
                title: "Backups",
                subtitle: "Sync & Restore",
                color: .cyan
            )
            
            // Resources
            SettingsCardLink(
                destination: ResourcesSettingsView(),
                icon: "book.closed.fill",
                title: "Resources",
                subtitle: "Help & Support",
                color: .purple
            )
            
            // Architect Tools
            SettingsCardLink(
                destination: ArchitectToolsView(),
                icon: "hammer.fill",
                title: "Architect",
                subtitle: "Import & Logs",
                color: .indigo
            )
            
            // Data Management
            SettingsCardLink(
                destination: DataManagementHubView(),
                icon: "externaldrive.fill",
                title: "Data",
                subtitle: "Archive & Recovery",
                color: .red
            )
        }
    }
    
    private var appInfoFooter: some View {
        VStack(spacing: 4) {
            Text("Protocol")
                .font(.headline)
                .fontWeight(.bold)
            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
    }
}

// MARK: - Settings Card Link

struct SettingsCardLink<Destination: View>: View {
    let destination: Destination
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)
                
                Spacer()
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .frame(height: 120)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notifications Settings

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationManager = NotificationManager.shared
    @AppStorage("defaultReminderOffset") private var defaultReminderOffset: Int = 15
    @AppStorage("showAppIconBadge") private var showAppIconBadge: Bool = true
    
    @State private var showingResyncConfirmation = false
    @State private var showingResyncSuccess = false
    
    var body: some View {
        List {
            Section {
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
                
                if !notificationManager.isAuthorized {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                }
                
                Picker("Default Reminder", selection: $defaultReminderOffset) {
                    ForEach(ReminderOffset.allCases) { offset in
                        Text(offset.displayName).tag(offset.rawValue)
                    }
                }
                
                Toggle("Show App Icon Badge", isOn: $showAppIconBadge)
                
                Button {
                    showingResyncConfirmation = true
                } label: {
                    Label("Re-sync Alerts", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("Notification Settings")
            } footer: {
                Text("Badge shows today's remaining habits count.")
            }
        }
        .navigationTitle("Notifications")
        .alert("Resync Alerts?", isPresented: $showingResyncConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Resync") {
                Task {
                    await NotificationManager.shared.refreshUpcomingNotifications(context: modelContext)
                    showingResyncSuccess = true
                }
            }
        }
        .alert("Alerts Synced", isPresented: $showingResyncSuccess) {
            Button("OK", role: .cancel) { }
        }
    }
}

// MARK: - Celebrations Settings

struct CelebrationsSettingsView: View {
    @AppStorage("celebrationIntensity") private var celebrationIntensity: String = CelebrationIntensity.normal.rawValue
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { SoundManager.shared.isSoundEnabled },
                    set: { SoundManager.shared.isSoundEnabled = $0 }
                )) {
                    Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                }
                
                if SoundManager.shared.isSoundEnabled {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { Double(SoundManager.shared.volume) },
                            set: { SoundManager.shared.volume = Float($0) }
                        ), in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { SoundManager.shared.isHapticEnabled },
                    set: { SoundManager.shared.isHapticEnabled = $0 }
                )) {
                    Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                }
                
                Picker("Intensity", selection: $celebrationIntensity) {
                    ForEach(CelebrationIntensity.allCases) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
            } header: {
                Text("Celebration Settings")
            } footer: {
                Text("Customize the fanfare when you complete habits.")
            }
        }
        .navigationTitle("Celebrations")
    }
}

// MARK: - Resources Settings

struct ResourcesSettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    FieldManualView()
                } label: {
                    Label("Field Manual", systemImage: "book.closed")
                }
                
                /*
                NavigationLink {
                    FAQView()
                } label: {
                    Label("FAQ", systemImage: "questionmark.circle")
                }
                */
                
                Link(destination: URL(string: "mailto:support@protocol.app")!) {
                    Label("Contact Support", systemImage: "envelope")
                }
                
                Link(destination: URL(string: "https://protocol.app/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            } header: {
                Text("Help & Support")
            }
        }
        .navigationTitle("Resources")
    }
}

// MARK: - Backups Settings

struct BackupsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var backupManager = BackupManager.shared
    @AppStorage("backupFrequency") private var backupFrequency: BackupFrequency = .daily
    
    @State private var availableBackups: [URL] = []
    @State private var showingBackupConfirmation = false
    @State private var showingBackupSuccess = false
    @State private var showingRestoreConfirmation = false
    @State private var backupToRestore: URL?
    @State private var shareItem: ShareItem?
    
    var body: some View {
        List {
            Section {
                Button {
                    showingBackupConfirmation = true
                } label: {
                    HStack {
                        Label("Create Backup", systemImage: "arrow.up.doc")
                        Spacer()
                        if backupManager.isCloudEnabled {
                            Image(systemName: "icloud.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Picker("Auto Backup", selection: $backupFrequency) {
                    ForEach(BackupFrequency.allCases) { freq in
                        Text(freq.rawValue).tag(freq)
                    }
                }
            } header: {
                Text("Backup Settings")
            }
            
            Section {
                if availableBackups.isEmpty {
                    ContentUnavailableView {
                        Label("No Backups", systemImage: "doc")
                    } description: {
                        Text("Create a backup to get started")
                    }
                } else {
                    ForEach(availableBackups, id: \.self) { url in
                        BackupRowView(
                            url: url,
                            onRestore: {
                                backupToRestore = url
                                showingRestoreConfirmation = true
                            },
                            onShare: {
                                shareItem = ShareItem(items: [url])
                            }
                        )
                    }
                    .onDelete(perform: deleteBackups)
                }
            } header: {
                Text("Available Backups")
            }
        }
        .navigationTitle("Backups")
        .onAppear { loadBackups() }
        .alert("Create Backup?", isPresented: $showingBackupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                Task {
                    try? await backupManager.createBackup(context: modelContext)
                    loadBackups()
                    showingBackupSuccess = true
                }
            }
        }
        .alert("Backup Created", isPresented: $showingBackupSuccess) {
            Button("OK", role: .cancel) { }
        }
        .alert("Restore Backup?", isPresented: $showingRestoreConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let url = backupToRestore {
                    Task {
                        try? await backupManager.restore(from: url, context: modelContext)
                    }
                }
            }
        } message: {
            Text("This will replace all current data.")
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: item.items)
        }
    }
    
    private func loadBackups() {
        availableBackups = backupManager.listBackups()
    }
    
    private func deleteBackups(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: availableBackups[index])
        }
        loadBackups()
    }
}

// MARK: - Backup Row View

struct BackupRowView: View {
    let url: URL
    let onRestore: () -> Void
    let onShare: () -> Void
    
    private var creationDate: Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                if let date = creationDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onRestore) {
                Image(systemName: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Architect Tools

struct ArchitectToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingSeedConfirmation = false
    @State private var showingSeedSuccess = false
    
    var body: some View {
        List {
            Section {
                NavigationLink {
                    BlueprintImportView()
                } label: {
                    Label("Import Blueprints", systemImage: "square.and.arrow.down")
                }
                
                NavigationLink {
                    AuditLogViewer()
                } label: {
                    Label("Audit Logs", systemImage: "doc.text.magnifyingglass")
                }
                
                Button {
                    showingSeedConfirmation = true
                } label: {
                    Label("Restore Default Protocols", systemImage: "arrow.counterclockwise.circle")
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Import habits in bulk or view data operation logs.")
            }
        }
        .navigationTitle("Architect Tools")
        .alert("Restore Defaults?", isPresented: $showingSeedConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") {
                OnboardingManager(modelContext: modelContext).forceSeedData()
                showingSeedSuccess = true
            }
        }
        .alert("Defaults Restored", isPresented: $showingSeedSuccess) {
            Button("OK", role: .cancel) { }
        }
    }
}

// MARK: - Data Management Hub

struct DataManagementHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    ArchivedMoleculesView()
                } label: {
                    Label("Archived Molecules", systemImage: "archivebox")
                }
                
                NavigationLink {
                    OrphanManagerView()
                } label: {
                    Label("Lost & Found", systemImage: "lifepreserver")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Recovery")
            } footer: {
                Text("Recover archived or orphaned data.")
            }
            
            Section {
                NavigationLink {
                    DataManagementView()
                } label: {
                    Label("Nuke Data", systemImage: "trash.fill")
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
                Text("Permanently delete all data. Cannot be undone.")
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .navigationTitle("Data Management")
    }
}


#Preview {
    SettingsHubView()
}
