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
            
            // Cloud Sync
            SettingsCardLink(
                destination: CloudSyncSettingsView(),
                icon: "arrow.triangle.2.circlepath.circle.fill",
                title: "Cloud Sync",
                subtitle: "Google Drive",
                color: .green
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
    @State private var showingBackupError = false
    @State private var showingRestoreConfirmation = false
    @State private var showingRestoreSuccess = false
    @State private var showingRestoreError = false
    @State private var restoreErrorMessage = ""
    @State private var backupToRestore: URL?
    @State private var shareItem: ShareItem?
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var passwordInput = "" // For encryption
    
    var body: some View {
        List {
            Section {
                Button {
                    passwordInput = "" // Reset
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
            SecureField("Password (Optional)", text: $passwordInput)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                Task {
                    do {
                        _ = try await backupManager.createBackup(context: modelContext, password: passwordInput)
                        loadBackups()
                        showingBackupSuccess = true
                    } catch {
                        showingBackupError = true
                    }
                    passwordInput = ""
                }
            }
        }
        .alert("Backup Created", isPresented: $showingBackupSuccess) {
            Button("OK", role: .cancel) { }
        }
        .alert("Backup Failed", isPresented: $showingBackupError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Failed to create backup. Please try again.")
        }
        .alert("Restore Backup?", isPresented: $showingRestoreConfirmation) {
            if let url = backupToRestore, url.pathExtension == "enc" {
                SecureField("Password Required", text: $passwordInput)
            }
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let url = backupToRestore {
                    Task {
                        do {
                            try await backupManager.restore(from: url, context: modelContext, password: passwordInput)
                            showingRestoreSuccess = true
                        } catch {
                            restoreErrorMessage = error.localizedDescription
                            showingRestoreError = true
                        }
                        passwordInput = ""
                    }
                }
            }
        } message: {
            Text("This will replace all current data.")
        }
        .alert("Restore Complete", isPresented: $showingRestoreSuccess) {
            Button("OK", role: .cancel) { }
        }
        .alert("Restore Failed", isPresented: $showingRestoreError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(restoreErrorMessage)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: item.items)
        }
        .alert("Delete Failed", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
    }
    
    private func loadBackups() {
        availableBackups = backupManager.listBackups()
    }
    
    private func deleteBackups(at offsets: IndexSet) {
        var firstError: Error?
        for index in offsets {
            do {
                try FileManager.default.removeItem(at: availableBackups[index])
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        loadBackups()
        if let error = firstError {
            deleteErrorMessage = error.localizedDescription
            showingDeleteError = true
        }
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
                
                NavigationLink {
                    GoogleSignInTestView()
                } label: {
                    Label("Google Sign-In Test", systemImage: "person.badge.key")
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

// MARK: - Cloud Sync Settings

struct CloudSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncEngine: SyncEngine
    @StateObject private var authManager = GoogleAuthManager.shared
    
    var body: some View {
        List {
            // Account Section
            Section {
                if authManager.isSignedIn {
                    HStack {
                        if let imageURL = authManager.currentUser?.profile?.imageURL(withDimension: 80) {
                            AsyncImage(url: imageURL) { image in
                                image
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.green)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(authManager.currentUser?.profile?.name ?? "Signed In")
                                .font(.headline)
                            Text(authManager.currentUser?.profile?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    Button(role: .destructive) {
                        authManager.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        if let rootVC = UIApplication.shared.rootViewController {
                            Task {
                                try? await authManager.signIn(presentingViewController: rootVC)
                            }
                        }
                    } label: {
                        Label("Sign in with Google", systemImage: "person.badge.plus")
                    }
                }
            } header: {
                Text("Google Account")
            } footer: {
                if !authManager.isSignedIn {
                    Text("Sign in to sync your data across devices.")
                }
            }
            
            // Sync Status Section
            if authManager.isSignedIn {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if syncEngine.isSyncing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(syncEngine.syncStatus.message)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = syncEngine.syncError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        } else {
                            Text(syncEngine.syncStatus.message.isEmpty ? "Ready" : syncEngine.syncStatus.message)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    if let lastSync = syncEngine.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button {
                        Task {
                            await syncEngine.performFullSync(context: modelContext)
                        }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if syncEngine.isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(syncEngine.isSyncing)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Sync happens automatically when the app opens.")
                }
                
                // Pending Queue Section
                Section {
                    let queueCount = SyncQueueManager.shared.queue.count
                    HStack {
                        Text("Pending Uploads")
                        Spacer()
                        Text("\(queueCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Button {
                        let count = SyncQueueManager.shared.queueAllRecords(context: modelContext)
                        // Trigger sync after queuing
                        if count > 0 {
                            Task {
                                await syncEngine.performFullSync(context: modelContext)
                            }
                        }
                    } label: {
                        Label("Queue All for Sync", systemImage: "tray.and.arrow.up")
                    }
                    .disabled(syncEngine.isSyncing)
                } header: {
                    Text("Queue")
                } footer: {
                    Text("Use 'Queue All' for initial sync of existing data.")
                }
            }
        }
        .navigationTitle("Cloud Sync")
    }
}
