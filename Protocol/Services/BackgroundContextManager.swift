//
//  BackgroundContextManager.swift
//  Protocol
//
//  Created on 2026-01-13.
//

import SwiftData
import Foundation

@globalActor
actor BackgroundDataActor {
    static let shared = BackgroundDataActor()
}

final class BackgroundContextManager {
    private let container: ModelContainer
    
    init(container: ModelContainer) {
        self.container = container
    }
    
    @BackgroundDataActor
    func createBackgroundContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false 
        return context
    }
}
