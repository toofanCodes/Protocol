//
//  AtomTemplateEditorViewModel.swift
//  Protocol
//
//  Created on 2026-01-12.
//

import SwiftUI
import SwiftData

@MainActor
class AtomTemplateEditorViewModel: ObservableObject {
    
    // MARK: - Properties
    
    let parentTemplate: MoleculeTemplate
    let existingAtom: AtomTemplate?
    
    // MARK: - Form State
    
    @Published var title: String = ""
    @Published var inputType: AtomInputType = .binary
    @Published var targetValue: String = ""
    @Published var unit: String = ""
    @Published var videoURL: String = ""
    
    // Workout-specific state
    @Published var isWorkoutExercise: Bool = false
    @Published var targetSets: String = ""
    @Published var targetReps: String = ""
    @Published var restTime: String = ""
    
    // Icon state
    @Published var iconSymbol: String = ""
    @Published var iconFrame: IconFrameStyle = .circle
    @Published var themeColor: Color = .blue
    
    // Audio capture state
    @Published var enableSnoringDetection: Bool = true
    @Published var snoringThreshold: Double = 40
    @Published var recordingDuration: RecordingDuration = .fixed(minutes: 480)
    @Published var saveFullRecording: Bool = false
    
    // Dialog state
    @Published var showingCascadeDialog = false
    @Published var showingIconEditor = false
    
    // MARK: - Change Detection
    
    private var originalTitle: String = ""
    private var originalTargetValue: String = ""
    private var originalUnit: String = ""
    private var originalVideoURL: String = ""
    private var originalTargetSets: String = ""
    private var originalTargetReps: String = ""
    private var originalRestTime: String = ""
    
    var isEditing: Bool {
        existingAtom != nil
    }
    
    var hasStructuralChanges: Bool {
        guard isEditing else { return false }
        return title != originalTitle ||
               targetValue != originalTargetValue ||
               unit != originalUnit ||
               videoURL != originalVideoURL ||
               targetSets != originalTargetSets ||
               targetReps != originalTargetReps ||
               restTime != originalRestTime
    }
    
    // MARK: - Initialization
    
    init(parentTemplate: MoleculeTemplate, existingAtom: AtomTemplate? = nil) {
        self.parentTemplate = parentTemplate
        self.existingAtom = existingAtom
        
        if let atom = existingAtom {
            loadExistingValues(atom)
        }
    }
    
    // MARK: - Logic
    
    private func loadExistingValues(_ atom: AtomTemplate) {
        title = atom.title
        inputType = atom.inputType
        videoURL = atom.videoURL ?? ""
        
        if let target = atom.targetValue {
            targetValue = String(format: target.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", target)
        }
        
        unit = atom.unit ?? ""
        
        // Load workout settings
        if let sets = atom.targetSets {
            targetSets = String(sets)
            isWorkoutExercise = true
        }
        
        if let reps = atom.targetReps {
            targetReps = String(reps)
        }
        
        if let rest = atom.defaultRestTime {
            restTime = String(Int(rest))
        }
        
        // Save originals for change detection
        originalTitle = title
        originalTargetValue = targetValue
        originalUnit = unit
        originalVideoURL = videoURL
        originalTargetSets = targetSets
        originalTargetReps = targetReps
        originalRestTime = restTime
        
        // Load icon values
        iconSymbol = atom.iconSymbol ?? ""
        iconFrame = atom.iconFrame
        themeColor = atom.themeColor
        
        // Load audio settings from mediaCaptureSettings
        if let settings = atom.mediaCaptureSettings?.audioSettings {
            enableSnoringDetection = settings.enableSnoringDetection
            snoringThreshold = settings.sensitivityThreshold
            recordingDuration = settings.recordingDuration
            saveFullRecording = settings.saveFullRecording
        }
    }
    
    func save(context: ModelContext, onSuccess: () -> Void) {
        if isEditing && hasStructuralChanges {
            showingCascadeDialog = true
        } else {
            saveTemplateOnly(context: context)
            onSuccess()
        }
    }
    
    func saveTemplateOnly(context: ModelContext) {
        let (target, unitValue, videoValue, sets, reps, rest) = prepareValues()
        let mediaSettings = buildMediaCaptureSettings()
        
        if let existingAtom = existingAtom {
            // Update existing template
            existingAtom.title = title
            existingAtom.inputType = inputType
            existingAtom.targetValue = inputType == .binary ? nil : target
            existingAtom.unit = inputType == .binary ? nil : unitValue
            existingAtom.videoURL = videoValue
            existingAtom.targetSets = sets
            existingAtom.targetReps = reps
            existingAtom.defaultRestTime = rest
            existingAtom.iconSymbol = iconSymbol.isEmpty ? nil : iconSymbol
            existingAtom.iconFrame = iconFrame
            existingAtom.themeColor = themeColor
            existingAtom.mediaCaptureSettings = mediaSettings
        } else {
            // Create new
            let nextOrder = (parentTemplate.atomTemplates.map(\.order).max() ?? -1) + 1
            
            let newAtom = AtomTemplate(
                title: title,
                inputType: inputType,
                targetValue: inputType == .binary ? nil : target,
                unit: inputType == .binary ? nil : unitValue,
                order: nextOrder,
                targetSets: sets,
                targetReps: reps,
                defaultRestTime: rest,
                videoURL: videoValue,
                parentMoleculeTemplate: parentTemplate,
                iconSymbol: iconSymbol.isEmpty ? nil : iconSymbol,
                iconFrame: iconFrame
            )
            newAtom.themeColor = themeColor
            newAtom.mediaCaptureSettings = mediaSettings
            
            context.insert(newAtom)
            parentTemplate.atomTemplates.append(newAtom)
        }
        
        try? context.save()
    }
    
    func saveWithCascade(context: ModelContext, allInstances: [AtomInstance], onSuccess: () -> Void) {
        // First update the template
        saveTemplateOnly(context: context)
        
        guard let existingAtom = existingAtom else {
            onSuccess()
            return
        }
        
        let (target, unitValue, videoValue, sets, reps, rest) = prepareValues()
        
        // Then Cascade to Future Instances
        let today = Calendar.current.startOfDay(for: Date())
        let futureInstances = allInstances.filter { instance in
            instance.sourceTemplateId == existingAtom.id &&
            instance.parentMoleculeInstance?.scheduledDate ?? Date.distantPast >= today
        }
        
        for instance in futureInstances {
            instance.title = title
            instance.inputType = inputType
            instance.targetValue = inputType == .binary ? nil : target
            instance.unit = inputType == .binary ? nil : unitValue
            instance.videoURL = videoValue
            instance.targetSets = sets
            instance.targetReps = reps
            instance.defaultRestTime = rest
        }
        
        try? context.save()
        onSuccess()
    }
    
    // MARK: - Private Helpers
    
    private func prepareValues() -> (Double?, String?, String?, Int?, Int?, TimeInterval?) {
        let target = Double(targetValue)
        let unitValue = unit.isEmpty ? nil : unit
        let videoValue = videoURL.isEmpty ? nil : videoURL
        
        let sets = isWorkoutExercise ? Int(targetSets) : nil
        let reps = isWorkoutExercise ? Int(targetReps) : nil
        let rest = isWorkoutExercise ? TimeInterval(restTime) : nil
        
        return (target, unitValue, videoValue, sets, reps, rest)
    }
    
    private func buildMediaCaptureSettings() -> MediaCaptureSettings? {
        switch inputType {
        case .photo:
            return MediaCaptureSettings.defaultPhoto
        case .video:
            return MediaCaptureSettings.defaultVideo
        case .audio:
            var settings = MediaCaptureSettings.defaultAudio
            settings.audioSettings = AudioCaptureSettings(
                enableSnoringDetection: enableSnoringDetection,
                recordingDuration: recordingDuration,
                saveFullRecording: saveFullRecording,
                saveSnoringClips: true,
                sensitivityThreshold: snoringThreshold
            )
            return settings
        default:
            return nil
        }
    }
}
