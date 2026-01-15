//
//  AtomTemplateMediaSection.swift
//  Protocol
//
//  Configuration UI section for media capture settings in AtomTemplate editor.
//

import SwiftUI

/// A form section for configuring media capture on an AtomTemplate
struct AtomTemplateMediaSection: View {
    @Binding var mediaCaptureSettings: MediaCaptureSettings?
    
    // Local state for editing
    @State private var isEnabled = false
    @State private var captureType: MediaCaptureType = .photo
    
    // Audio settings
    @State private var enableSnoringDetection = true
    @State private var recordingDuration: RecordingDuration = .fixed(minutes: 480)
    @State private var saveFullRecording = false
    @State private var saveSnoringClips = true
    @State private var sensitivityThreshold: Double = 40
    
    // Photo settings
    @State private var useFrontCamera = false
    @State private var savePhotoToLibrary = false
    
    // Video settings
    @State private var maxVideoDuration: TimeInterval = 60
    @State private var videoQuality: VideoQuality = .medium
    @State private var saveVideoToLibrary = false
    
    var body: some View {
        Section {
            Toggle("Enable Media Capture", isOn: $isEnabled)
                .onChange(of: isEnabled) { oldValue, newValue in
                    if newValue && mediaCaptureSettings == nil {
                        // Create default settings
                        mediaCaptureSettings = .defaultPhoto
                        captureType = .photo
                    } else if !newValue {
                        mediaCaptureSettings = nil
                    }
                }
            
            if isEnabled {
                Picker("Capture Type", selection: $captureType) {
                    ForEach(MediaCaptureType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .onChange(of: captureType) { oldValue, newValue in
                    updateSettings()
                }
                
                switch captureType {
                case .audio:
                    audioSettingsSection
                case .photo:
                    photoSettingsSection
                case .video:
                    videoSettingsSection
                }
            }
        } header: {
            Label("Media Capture", systemImage: "camera.metering.multispot")
        } footer: {
            if isEnabled {
                footerText
            }
        }
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Audio Settings
    
    @ViewBuilder
    private var audioSettingsSection: some View {
        Toggle("Snoring Detection", isOn: $enableSnoringDetection)
            .onChange(of: enableSnoringDetection) { _, _ in updateSettings() }
        
        if enableSnoringDetection {
            HStack {
                Text("Sensitivity")
                Slider(value: $sensitivityThreshold, in: 10...90, step: 10)
                Text("\(Int(sensitivityThreshold))%")
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .onChange(of: sensitivityThreshold) { _, _ in updateSettings() }
        }
        
        Picker("Recording Duration", selection: $recordingDuration) {
            ForEach(RecordingDuration.presets, id: \.displayString) { duration in
                Text(duration.displayString).tag(duration)
            }
        }
        .onChange(of: recordingDuration) { _, _ in updateSettings() }
        
        Toggle("Save Full Recording", isOn: $saveFullRecording)
            .onChange(of: saveFullRecording) { _, _ in updateSettings() }
        
        if enableSnoringDetection {
            Toggle("Save Snoring Clips", isOn: $saveSnoringClips)
                .onChange(of: saveSnoringClips) { _, _ in updateSettings() }
        }
        
        if saveFullRecording {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("~20MB per night")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Photo Settings
    
    @ViewBuilder
    private var photoSettingsSection: some View {
        Toggle("Use Front Camera", isOn: $useFrontCamera)
            .onChange(of: useFrontCamera) { _, _ in updateSettings() }
        
        Toggle("Save to Photos Library", isOn: $savePhotoToLibrary)
            .onChange(of: savePhotoToLibrary) { _, _ in updateSettings() }
    }
    
    // MARK: - Video Settings
    
    @ViewBuilder
    private var videoSettingsSection: some View {
        Picker("Max Duration", selection: $maxVideoDuration) {
            Text("30 seconds").tag(30.0 as TimeInterval)
            Text("1 minute").tag(60.0 as TimeInterval)
            Text("2 minutes").tag(120.0 as TimeInterval)
            Text("5 minutes").tag(300.0 as TimeInterval)
        }
        .onChange(of: maxVideoDuration) { _, _ in updateSettings() }
        
        Picker("Quality", selection: $videoQuality) {
            ForEach(VideoQuality.allCases, id: \.self) { quality in
                Text(quality.displayName).tag(quality)
            }
        }
        .onChange(of: videoQuality) { _, _ in updateSettings() }
        
        Toggle("Save to Photos Library", isOn: $saveVideoToLibrary)
            .onChange(of: saveVideoToLibrary) { _, _ in updateSettings() }
    }
    
    // MARK: - Footer
    
    @ViewBuilder
    private var footerText: some View {
        switch captureType {
        case .audio:
            Text("Sleep tracking with snoring detection. Keep device plugged in and place nearby.")
        case .photo:
            Text("Capture a photo when completing this task.")
        case .video:
            Text("Record a video when completing this task.")
        }
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        guard let settings = mediaCaptureSettings else {
            isEnabled = false
            return
        }
        
        isEnabled = true
        captureType = settings.captureType
        
        if let audio = settings.audioSettings {
            enableSnoringDetection = audio.enableSnoringDetection
            recordingDuration = audio.recordingDuration
            saveFullRecording = audio.saveFullRecording
            saveSnoringClips = audio.saveSnoringClips
            sensitivityThreshold = audio.sensitivityThreshold
        }
        
        if let photo = settings.photoSettings {
            useFrontCamera = photo.useFrontCamera
            savePhotoToLibrary = photo.saveToPhotos
        }
        
        if let video = settings.videoSettings {
            maxVideoDuration = video.maxDuration
            videoQuality = video.quality
            saveVideoToLibrary = video.saveToPhotos
        }
    }
    
    private func updateSettings() {
        guard isEnabled else {
            mediaCaptureSettings = nil
            return
        }
        
        var settings = MediaCaptureSettings(captureType: captureType)
        
        switch captureType {
        case .audio:
            settings.audioSettings = AudioCaptureSettings(
                enableSnoringDetection: enableSnoringDetection,
                recordingDuration: recordingDuration,
                saveFullRecording: saveFullRecording,
                saveSnoringClips: saveSnoringClips,
                sensitivityThreshold: sensitivityThreshold
            )
            
        case .photo:
            settings.photoSettings = PhotoCaptureSettings(
                useFrontCamera: useFrontCamera,
                saveToPhotos: savePhotoToLibrary
            )
            
        case .video:
            settings.videoSettings = VideoCaptureSettings(
                maxDuration: maxVideoDuration,
                quality: videoQuality,
                saveToPhotos: saveVideoToLibrary
            )
        }
        
        mediaCaptureSettings = settings
    }
}

// MARK: - Preview

#Preview {
    Form {
        AtomTemplateMediaSection(mediaCaptureSettings: .constant(.defaultAudio))
    }
}
