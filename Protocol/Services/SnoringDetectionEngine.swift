//
//  SnoringDetectionEngine.swift
//  Protocol
//
//  Uses Apple's Sound Analysis framework to detect snoring in real-time.
//  SNAudioStreamAnalyzer provides built-in .snoring classification.
//

import Foundation
import SoundAnalysis
import AVFoundation
import os.log

// MARK: - Detected Snoring Event

/// Represents a single snoring event detected by the engine
struct DetectedSnoringEvent: Identifiable, Equatable {
    let id = UUID()
    let startTime: Date
    var endTime: Date?
    var peakConfidence: Double
    var audioClipData: Data?
    
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
    
    /// Intensity as 0-100 scale (confidence * 100)
    var intensity: Double {
        peakConfidence * 100
    }
}

// MARK: - Snoring Analysis Result

/// Final analysis result after recording stops
struct SnoringAnalysis {
    let events: [DetectedSnoringEvent]
    let totalRecordingDuration: TimeInterval
    
    var totalSnoringDuration: TimeInterval {
        events.reduce(0) { $0 + $1.duration }
    }
    
    var snoringPercentage: Double {
        guard totalRecordingDuration > 0 else { return 0 }
        return (totalSnoringDuration / totalRecordingDuration) * 100
    }
    
    var averageIntensity: Double {
        guard !events.isEmpty else { return 0 }
        return events.reduce(0) { $0 + $1.intensity } / Double(events.count)
    }
    
    /// Score from 0-100
    /// Weighted: 70% snoring percentage, 30% average intensity
    var score: Double {
        let durationScore = min(snoringPercentage * 2, 100)  // Cap at 100
        let intensityScore = averageIntensity
        return (durationScore * 0.7) + (intensityScore * 0.3)
    }
}

// MARK: - Snoring Detection Delegate

protocol SnoringDetectionDelegate: AnyObject {
    func snoringDetectionEngine(_ engine: SnoringDetectionEngine, didDetectEvent event: DetectedSnoringEvent)
    func snoringDetectionEngine(_ engine: SnoringDetectionEngine, didUpdateCurrentIntensity intensity: Double)
}

// MARK: - Snoring Detection Engine

/// Real-time snoring detection using Apple's Sound Analysis framework
final class SnoringDetectionEngine: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: SnoringDetectionDelegate?
    
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "SnoringDetection")
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.protocol.snoring.analysis", qos: .userInitiated)
    
    /// Confidence threshold for snoring detection (0-1)
    private var confidenceThreshold: Double = 0.4
    
    /// Recording start time for offset calculations
    private var recordingStartTime: Date?
    
    /// All detected events during this session
    private var detectedEvents: [DetectedSnoringEvent] = []
    
    /// Current event being tracked (nil if not currently snoring)
    private var currentEvent: DetectedSnoringEvent?
    
    /// Debounce: Minimum time between events to be considered separate
    private let eventDebounceInterval: TimeInterval = 2.0
    
    /// Time of last snore detection for debouncing
    private var lastSnoreTime: Date?
    
    // MARK: - Initialization
    
    init(confidenceThreshold: Double = 0.4) {
        self.confidenceThreshold = max(0.1, min(confidenceThreshold / 100.0, 0.9))  // Convert 0-100 to 0-1
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Starts analyzing audio for snoring
    /// - Parameter format: The audio format from AVAudioEngine
    func startAnalysis(format: AVAudioFormat) throws {
        recordingStartTime = Date()
        detectedEvents = []
        currentEvent = nil
        
        // Create analyzer
        analyzer = SNAudioStreamAnalyzer(format: format)
        
        // Create snoring classification request
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            
            // Add the request to the analyzer
            try analyzer?.add(request, withObserver: self)
            
            logger.info("Started snoring detection analysis (threshold: \(self.confidenceThreshold))")
        } catch {
            logger.error("Failed to create sound classification request: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Processes an audio buffer for snoring detection
    /// - Parameters:
    ///   - buffer: Audio buffer from AVAudioEngine tap
    ///   - time: Timestamp of the buffer
    func processBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        analysisQueue.async { [weak self] in
            self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }
    
    /// Stops analysis and returns the final results
    func stopAnalysis() -> SnoringAnalysis {
        // Finalize any current event
        if var event = currentEvent {
            event.endTime = Date()
            detectedEvents.append(event)
            currentEvent = nil
        }
        
        // Remove observer and cleanup
        analyzer?.removeAllRequests()
        analyzer = nil
        
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let analysis = SnoringAnalysis(events: detectedEvents, totalRecordingDuration: duration)
        
        logger.info("Snoring analysis complete: \(self.detectedEvents.count) events, score: \(analysis.score)")
        
        return analysis
    }
    
    /// Resets the engine for a new session
    func reset() {
        detectedEvents = []
        currentEvent = nil
        recordingStartTime = nil
        lastSnoreTime = nil
    }
    
    // MARK: - Private Methods
    
    private func handleSnoringDetection(confidence: Double, timestamp: Date) {
        let isSnoring = confidence >= confidenceThreshold
        
        // Update delegate with current intensity
        DispatchQueue.main.async {
            self.delegate?.snoringDetectionEngine(self, didUpdateCurrentIntensity: confidence * 100)
        }
        
        if isSnoring {
            // Check debounce
            if let lastEvent = currentEvent {
                // Continue existing event
                if confidence > lastEvent.peakConfidence {
                    currentEvent?.peakConfidence = confidence
                }
            } else if let lastTime = lastSnoreTime,
                      timestamp.timeIntervalSince(lastTime) < eventDebounceInterval,
                      let last = detectedEvents.last {
                // Merge with previous event (within debounce window)
                var merged = last
                merged.endTime = timestamp
                if confidence > merged.peakConfidence {
                    merged.peakConfidence = confidence
                }
                detectedEvents[detectedEvents.count - 1] = merged
            } else {
                // Start new event
                currentEvent = DetectedSnoringEvent(
                    startTime: timestamp,
                    endTime: nil,
                    peakConfidence: confidence
                )
            }
            
            lastSnoreTime = timestamp
            
        } else if var event = currentEvent {
            // End current event
            event.endTime = timestamp
            detectedEvents.append(event)
            currentEvent = nil
            
            // Notify delegate
            DispatchQueue.main.async {
                self.delegate?.snoringDetectionEngine(self, didDetectEvent: event)
            }
            
            logger.debug("Snoring event ended: \(event.duration)s, intensity: \(event.intensity)")
        }
    }
}

// MARK: - SNResultsObserving

extension SnoringDetectionEngine: SNResultsObserving {
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        
        // Look for snoring classification
        if let snoringClassification = classification.classifications.first(where: { $0.identifier == "snoring" }) {
            handleSnoringDetection(
                confidence: snoringClassification.confidence,
                timestamp: Date()
            )
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Sound analysis failed: \(error.localizedDescription)")
    }
    
    func requestDidComplete(_ request: SNRequest) {
        logger.debug("Sound analysis request completed")
    }
}
