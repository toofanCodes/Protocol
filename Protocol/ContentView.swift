//
//  ContentView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject private var syncEngine: SyncEngine
    
    @State private var deepLinkedInstance: MoleculeInstance?
    
    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                
                TemplateListView()
                    .tabItem {
                        Label("Protocols", systemImage: "list.bullet")
                    }
                
                InsightsView()
                    .tabItem {
                        Label("Insights", systemImage: "chart.bar.xaxis")
                    }
                
                SettingsHubView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            
            // Sync Status Banner (non-intrusive, top overlay)
            VStack {
                if syncEngine.syncStatus != .idle {
                    SyncStatusBanner()
                        .padding(.top, 50) // Below status bar
                }
                Spacer()
            }
        }
        .onChange(of: deepLinkManager.pendingInstanceId) { _, newId in
            guard let instanceId = newId else { return }
            
            // Fetch the instance from the database
            let descriptor = FetchDescriptor<MoleculeInstance>(
                predicate: #Predicate<MoleculeInstance> { $0.id == instanceId }
            )
            
            if let instance = try? modelContext.fetch(descriptor).first {
                deepLinkedInstance = instance
            }
            
            // Clear the pending navigation
            deepLinkManager.clearPendingNavigation()
        }
        .sheet(item: $deepLinkedInstance) { instance in
            NavigationStack {
                MoleculeInstanceDetailView(instance: instance)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MoleculeTemplate.self, MoleculeInstance.self, AtomTemplate.self, AtomInstance.self, WorkoutSet.self], inMemory: true)
}
