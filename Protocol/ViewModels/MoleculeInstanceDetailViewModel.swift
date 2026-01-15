//
//  MoleculeInstanceDetailViewModel.swift
//  Protocol
//
//  Created on 2026-01-12.
//

import SwiftUI
import SwiftData

@MainActor
class MoleculeInstanceDetailViewModel: ObservableObject {
    
    // MARK: - Properties
    
    var instance: MoleculeInstance
    
    // MARK: - State
    
    @Published var atomForValueEntry: AtomInstance?
    @Published var atomForWorkoutLog: AtomInstance?
    @Published var showingRescheduleSheet = false
    @Published var rescheduleDate: Date = Date()
    
    // MARK: - Initialization
    
    init(instance: MoleculeInstance) {
        self.instance = instance
    }
    
    // MARK: - Computed Properties
    
    var sortedAtoms: [AtomInstance] {
        instance.atomInstances.sorted { $0.order < $1.order }
    }
    
    var completedCount: Int {
        instance.atomInstances.filter(\.isCompleted).count
    }
    
    var progress: Double {
        guard !instance.atomInstances.isEmpty else { return 0 }
        return Double(completedCount) / Double(instance.atomInstances.count)
    }
    
    // MARK: - Actions
    
    func handleAtomTap(_ atom: AtomInstance, context: ModelContext) {
        switch atom.inputType {
        case .binary:
            // Binary atoms toggle directly from the row (handled by AtomInstanceRowView binding usually, 
            // but if we want to validte: actually AtomInstanceRowView toggles it internally? 
            // Checking the View code: The view code just calls handleAtomTap. 
            // Wait, AtomInstanceRowView usually binds to the atom. 
            // In the original view: 
            // case .binary: break
            // So it seems binary atoms are handled by the row's internal logic or binding.
            break
            
        case .counter:
            // Counter atoms can use the row controls, but also open detail for notes
            if atom.targetReps != nil || atom.notes != nil {
                atomForWorkoutLog = atom
            }
            
        case .value:
            // Check if this is a workout exercise (has sets/reps)
            if atom.isWorkoutExercise {
                atomForWorkoutLog = atom
            } else {
                atomForValueEntry = atom
            }
        
        case .photo, .video, .audio:
            // TODO: Present MediaCaptureSheet for media capture
            // For now, mark as completed when tapped
            HapticFeedback.light()
            atom.toggleComplete()
            try? context.save()
        }
    }
    
    func postponeToTomorrow(context: ModelContext) {
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: instance.scheduledDate) {
            rescheduleInstance(to: tomorrow, context: context)
        }
    }
    
    func rescheduleInstance(to newDate: Date, context: ModelContext) {
        // Store original date for tracking
        if instance.originalScheduledDate == nil {
            instance.originalScheduledDate = instance.scheduledDate
        }
        
        instance.scheduledDate = newDate
        instance.isException = true
        instance.exceptionTime = newDate
        instance.updatedAt = Date()
        
        try? context.save()
        
        // Reschedule notifications
        Task {
            await NotificationManager.shared.scheduleNotifications(for: instance)
        }
    }
    
    func checkForCompletion(oldAtoms: [AtomInstance], newAtoms: [AtomInstance], context: ModelContext, dismissal: () -> Void, triggerCelebration: @escaping (Color?) -> Void, triggerPerfectDayCheck: @escaping () -> Void) {
        let oldCompleted = oldAtoms.map(\.isCompleted)
        let newCompleted = newAtoms.map(\.isCompleted)
        
        // Detect TRANSITION from <100% to 100%
        let wasAllCompleted = !oldCompleted.isEmpty && oldCompleted.allSatisfy { $0 }
        let isNowAllCompleted = !newCompleted.isEmpty && newCompleted.allSatisfy { $0 }
        
        if !wasAllCompleted && isNowAllCompleted {
            // Mark instance complete if not already
            if !instance.isCompleted {
                instance.markComplete()
                try? context.save()
            }
            NotificationManager.shared.cancelNotification(for: instance)
            
            // Dismiss sheet first
            dismissal()
            
            // Trigger celebration
            let themeColor = instance.parentTemplate?.themeColor
            triggerCelebration(themeColor)
            
            // Check for Perfect Day
            triggerPerfectDayCheck()
            
        } else if !isNowAllCompleted && instance.isCompleted {
            instance.markIncomplete()
            try? context.save()
        }
    }
}
