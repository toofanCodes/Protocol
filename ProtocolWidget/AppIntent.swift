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
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let context = DataController.shared.container.mainContext
        
        guard let uuid = UUID(uuidString: id) else {
            return .result()
        }
        
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate<MoleculeInstance> { $0.id == uuid }
        )
        
        if let instance = try? context.fetch(descriptor).first {
            instance.isCompleted.toggle()
            if instance.isCompleted {
                instance.completedAt = Date()  // FIXED: was completedDate
            } else {
                instance.completedAt = nil     // FIXED: was completedDate
            }
            
            try? context.save()
        }
        
        return .result()
    }
}
