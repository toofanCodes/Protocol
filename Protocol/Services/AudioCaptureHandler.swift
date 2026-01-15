//
//  AudioCaptureHandler.swift
//  Protocol
//
//  Handles audio recording using AVAudioEngine with real-time snoring detection.
//  Keeps screen awake during recording with isIdleTimerDisabled.
//

import Foundation
import AVFoundation
import UIKit
import os.log

// MARK: - Audio Capture Error

enum AudioCaptureError: LocalizedError {
    case microphoneUnavailable
    case permissionDenied
    case audioSessionSetupFailed
    case recordingFailed
    case alreadyRecording
    case notRecording
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "Microphone is not available"
        case .permissionDenied:
            return "Microphone permission denied"
        case .audioSessionSetupFailed:
            return "Failed to configure audio session"
        case .recordingFailed:
            return "Failed to record audio"
        case .alreadyRecording:
            return "Already recording"
        case .notRecording:
            return "Not currently recording"
        case .encodingFailed:
            return "Failed to encode audio"
        }
    }
}

// MARK: - Audio Capture Handler

/// Handles audio recording with real-time snoring detection
@MainActor
final class AudioCaptureHandler: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentIntensity: Double = 0
    @Published private(set) var detectedEvents: [DetectedSnoringEvent] = []
    @Published var error: AudioCaptureError?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "AudioCaptureHandler")
    private let audioEngine = AVAudioEngine()
    private var snoringEngine: SnoringDetectionEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var elapsedTimer: Timer?
    private var scheduledStopTime: Date?
    
    // Audio format settings for AAC encoding
    // Dynamic based on input hardware
    
    // MARK: - Permission Check
    
    /// Checks if microphone access is authorized
    static func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Recording Control
    
    /// Starts audio recording with optional snoring detection
    /// - Parameters:
    ///   - settings: Audio capture settings
    ///   - atomInstanceID: Associated atom instance for file naming
    func startRecording(settings: AudioCaptureSettings, atomInstanceID: UUID) async throws {
        guard !isRecording else {
            throw AudioCaptureError.alreadyRecording
        }
        
        guard await Self.checkMicrophonePermission() else {
            logger.error("Microphone permission denied")
            throw AudioCaptureError.permissionDenied
        }
        
        // Configure audio session
        try configureAudioSession()
        
        // Keep screen on during recording
        UIApplication.shared.isIdleTimerDisabled = true
        logger.info("Screen idle timer disabled for recording")
        
        // Get input format from hardware
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
             logger.error("Invalid input format received from audio engine")
             throw AudioCaptureError.microphoneUnavailable
        }
        
        // Create snoring engine if needed
        if settings.enableSnoringDetection {
            snoringEngine = SnoringDetectionEngine(confidenceThreshold: settings.sensitivityThreshold)
            snoringEngine?.delegate = self
        }
        
        // Setup audio file if saving full recording
        // Critical: Match file format to input format to prevent write crashes
        if settings.saveFullRecording {
            try setupAudioFile(atomInstanceID: atomInstanceID, format: inputFormat)
        }
        
        // Start audio engine
        try startAudioEngine(savingAudio: settings.saveFullRecording, format: inputFormat)
        
        // Track state
        recordingStartTime = Date()
        isRecording = true
        detectedEvents = []
        elapsedTime = 0
        
        // Start elapsed time timer
        startElapsedTimer()
        
        // Schedule auto-stop if needed
        scheduleAutoStop(duration: settings.recordingDuration)
        
        logger.info("Started audio recording (Rate: \(inputFormat.sampleRate)Hz, Ch: \(inputFormat.channelCount))")
    }
    
    /// Stops recording and returns the analysis results
    func stopRecording() async throws -> (analysis: SnoringAnalysis?, audioFileURL: String?) {
        guard isRecording else {
            throw AudioCaptureError.notRecording
        }
        
        // Stop timers
        stopElapsedTimer()
        cancelScheduledStop()
        
        // Stop audio engine
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        // Restore screen idle behavior
        UIApplication.shared.isIdleTimerDisabled = false
        logger.info("Screen idle timer restored")
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        // Get snoring analysis
        let analysis = snoringEngine?.stopAnalysis()
        snoringEngine = nil
        
        // Get audio file path
        var audioPath: String?
        if let fileURL = recordingURL {
            audioFile = nil  // Close file
            
            // Convert to relative path for storage
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                AppLogger.data.error("Could not access documents directory")
                return (analysis, nil)
            }
            let fullPath = fileURL.path
            let documentsPath = documentsURL.path
            
            if fullPath.hasPrefix(documentsPath) {
                let startIndex = fullPath.index(fullPath.startIndex, offsetBy: documentsPath.count + 1)
                audioPath = String(fullPath[startIndex...])
            }
        }
        
        // Reset state
        isRecording = false
        recordingURL = nil
        audioFile = nil
        recordingStartTime = nil
        
        logger.info("Stopped audio recording. Duration: \(self.elapsedTime)s, Events: \(analysis?.events.count ?? 0)")
        
        return (analysis, audioPath)
    }
    
    /// Cancels recording without saving
    func cancelRecording() {
        guard isRecording else { return }
        
        stopElapsedTimer()
        cancelScheduledStop()
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false)
        
        snoringEngine?.reset()
        snoringEngine = nil
        
        // Delete partial audio file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        isRecording = false
        recordingURL = nil
        audioFile = nil
        recordingStartTime = nil
        
        logger.info("Recording cancelled")
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
            throw AudioCaptureError.audioSessionSetupFailed
        }
    }
    
    private func setupAudioFile(atomInstanceID: UUID, format: AVAudioFormat) throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(atomInstanceID.uuidString)_\(timestamp).m4a"
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioCaptureError.recordingFailed
        }
        let audioDir = documentsURL.appendingPathComponent("MediaCaptures/Audio", isDirectory: true)
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        recordingURL = audioDir.appendingPathComponent(filename)
        
        // Create audio file with AAC format matching input sample rate
        // We generally keep channels to 1 (mono) for voice/snoring unless hardware forces 2
        let fileChannels = min(format.channelCount, 2)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: fileChannels,
            AVEncoderBitRateKey: 48000  // 48kbps
        ]
        
        audioFile = try AVAudioFile(forWriting: recordingURL!, settings: settings)
    }
    
    private func startAudioEngine(savingAudio: Bool, format: AVAudioFormat) throws {
        let inputNode = audioEngine.inputNode
        // inputFormat is passed in to ensure consistency
        
        // Validate format
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            logger.error("Invalid audio input format")
            throw AudioCaptureError.microphoneUnavailable
        }
        
        // Start snoring analysis
        if let engine = snoringEngine {
            try engine.startAnalysis(format: format)
        }
        
        // Install tap for audio processing
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Process for snoring detection
            self.snoringEngine?.processBuffer(buffer, at: time)
            
            // Write to file if saving
            if savingAudio, let file = self.audioFile {
                do {
                    try file.write(from: buffer)
                } catch {
                    self.logger.error("Failed to write audio buffer: \(error.localizedDescription)")
                }
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let startTime = recordingStartTime ?? Date()
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
    
    private func scheduleAutoStop(duration: RecordingDuration) {
        switch duration {
        case .manual:
            // No auto-stop
            break
            
        case .fixed(let minutes):
            let stopDate = Date().addingTimeInterval(Double(minutes) * 60)
            scheduleStop(at: stopDate)
            
        case .untilTime(let hour, let minute):
            // Find next occurrence of the specified time
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            
            if var targetDate = calendar.date(from: components) {
                // If target time has passed today, schedule for tomorrow
                if targetDate <= Date() {
                    targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate)!
                }
                scheduleStop(at: targetDate)
            }
        }
    }
    
    private func scheduleStop(at date: Date) {
        scheduledStopTime = date
        let delay = date.timeIntervalSinceNow
        
        guard delay > 0 else { return }
        
        logger.info("Scheduled auto-stop at \(date)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRecording,
                      let scheduled = self.scheduledStopTime,
                      abs(scheduled.timeIntervalSince(date)) < 1 else { return }
                
                self.logger.info("Auto-stopping recording")
                _ = try? await self.stopRecording()
            }
        }
    }
    
    private func cancelScheduledStop() {
        scheduledStopTime = nil
    }
}

// MARK: - SnoringDetectionDelegate

extension AudioCaptureHandler: SnoringDetectionDelegate {
    
    nonisolated func snoringDetectionEngine(_ engine: SnoringDetectionEngine, didDetectEvent event: DetectedSnoringEvent) {
        Task { @MainActor in
            detectedEvents.append(event)
            logger.debug("Snoring event detected: \(event.duration)s")
        }
    }
    
    nonisolated func snoringDetectionEngine(_ engine: SnoringDetectionEngine, didUpdateCurrentIntensity intensity: Double) {
        Task { @MainActor in
            currentIntensity = intensity
        }
    }
}
