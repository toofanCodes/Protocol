//
//  AppIntent.swift
//  Protocol
//
//  Created on 2025-12-31.
//

import AppIntents
import SwiftData
import Foundation

struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Habit"
    
    @Parameter(title: "Habit ID")
    var id: String
    
    init() {}
    
    init(id: UUID) {
        self.id = id.uuidString
    }
    
    func perform() async throws -> some IntentResult {
        let context = await DataController.shared.container.mainContext
        
        // Find the instance
        guard let uuid = UUID(uuidString: id) else {
            return .result()
        }
        
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate<MoleculeInstance> { $0.id == uuid }
        )
        
        if let instance = try? context.fetch(descriptor).first {
            // Toggle status
            instance.isCompleted.toggle()
            if instance.isCompleted {
                instance.completedDate = Date()
            } else {
                instance.completedDate = nil
            }
            
            try? context.save()
        }
        
        // Force widget reload
        return .result()
    }
}
