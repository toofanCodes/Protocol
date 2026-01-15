//
//  ProtocolApp.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct ProtocolApp: App {
    // Use the shared DataController which handles App Group logic
    var sharedModelContainer: ModelContainer {
        DataController.shared.container
    }

    // MARK: - Properties
    
    private let notificationHandler = NotificationHandler()
    @StateObject private var celebrationState = CelebrationState()
    @StateObject private var syncEngine = SyncEngine.shared
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Initializer
    
    init() {
        // Register background task schedulers
        BackgroundScheduler.shared.registerBackgroundTask()
        BackgroundSyncScheduler.shared.registerTask()
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                SplashScreenView()
                    .onAppear {
                        setupNotifications()
                        seedDataOnFirstLaunch()
                        restoreGoogleSignIn()
                    }
                
                // Gamification Overlay - Confetti (Z-Index 100)
                ConfettiView(celebrationState: celebrationState)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(100)
                
                // Perfect Day - Color Bomb (Z-Index 200)
                if celebrationState.showPerfectDayBomb {
                    ColorBombView(isShowing: $celebrationState.showPerfectDayBomb)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(200)
                }
                
                // Perfect Day - Greeting Card (Z-Index 201)
                if celebrationState.showGreetingCard {
                    GreetingCardView(isShowing: $celebrationState.showGreetingCard)
                        .zIndex(201)
                        // Greeting card needs hit testing to be dismissed by tap
                }
            }
            .modelContainer(sharedModelContainer)
            .environmentObject(MoleculeService(modelContext: sharedModelContainer.mainContext))
            .environmentObject(celebrationState)
            .environmentObject(DeepLinkManager.shared)
            .environmentObject(syncEngine)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
            // Handle Google Sign-In OAuth callback URL
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Set delegate
        UNUserNotificationCenter.current().delegate = notificationHandler
        
        // Request auth
        Task {
            await NotificationManager.shared.requestAuthorization()
        }
        
        // Configure handler actions
        notificationHandler.onComplete = { instanceId in
            Task { @MainActor in
                let context = sharedModelContainer.mainContext
                let descriptor = FetchDescriptor<MoleculeInstance>(
                    predicate: #Predicate<MoleculeInstance> { $0.id == instanceId }
                )
                
                if let instance = try? context.fetch(descriptor).first {
                    instance.markComplete()
                    try? context.save()
                }
            }
        }
        
        notificationHandler.onSnooze = { instanceId in
            Task { @MainActor in
                let context = sharedModelContainer.mainContext
                let descriptor = FetchDescriptor<MoleculeInstance>(
                    predicate: #Predicate<MoleculeInstance> { $0.id == instanceId }
                )
                
                if let instance = try? context.fetch(descriptor).first {
                    // Snooze logic handled by NotificationManager.snoozeNotification
                    await NotificationManager.shared.snoozeNotification(for: instance)
                    try? context.save()
                }
            }
        }
        
        // Handle notification tap - deep link to instance
        notificationHandler.onTap = { instanceId in
            Task { @MainActor in
                DeepLinkManager.shared.navigateToInstance(instanceId)
            }
        }
    }
    
    private func seedDataOnFirstLaunch() {
        let context = sharedModelContainer.mainContext
        let manager = OnboardingManager(modelContext: context)
        manager.seedDataIfNeeded()
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
// Refresh notifications when app becomes active
            Task {
                await BackgroundScheduler.shared.refreshNotifications()
                await BackupManager.shared.autoBackup(context: sharedModelContainer.mainContext)
                await RetirementService.shared.checkPendingRetirements(context: sharedModelContainer.mainContext)
                await RetirementService.shared.configure(with: sharedModelContainer)
                await RetirementService.shared.resumeInterruptedRetirements()
            }
            // Sync with cloud in background (fire-and-forget, never blocks)
            SyncEngine.shared.performFullSyncSafely(container: sharedModelContainer)
        case .background:
            // Schedule background refreshes when entering background
            BackgroundScheduler.shared.scheduleAppRefresh()
            BackgroundSyncScheduler.shared.scheduleNextSync()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
    
    /// Silently restore previous Google Sign-In session
    private func restoreGoogleSignIn() {
        Task {
            await GoogleAuthManager.shared.restorePreviousSignIn()
            // Trigger initial sync in background (fire-and-forget, never blocks)
            if GoogleAuthManager.shared.isSignedIn {
                SyncEngine.shared.performFullSyncSafely(container: sharedModelContainer)
            }
        }
    }
}
