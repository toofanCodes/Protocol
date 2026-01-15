//
//  VideoCaptureHandler.swift
//  Protocol
//
//  Handles video capture using UIImagePickerController in video mode.
//

import Foundation
import UIKit
import AVFoundation
import Photos
import os.log

// MARK: - Video Capture Error

enum VideoCaptureError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case permissionDenied(AVMediaType)
    case captureFailed
    case saveFailed
    case cancelled
    case invalidVideoURL
    
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device"
        case .microphoneUnavailable:
            return "Microphone is not available"
        case .permissionDenied(let type):
            return "\(type == .video ? "Camera" : "Microphone") permission denied"
        case .captureFailed:
            return "Failed to capture video"
        case .saveFailed:
            return "Failed to save video"
        case .cancelled:
            return "Video capture was cancelled"
        case .invalidVideoURL:
            return "Invalid video file URL"
        }
    }
}

// MARK: - Video Capture Handler

/// Handles video capture operations using native iOS camera
@MainActor
final class VideoCaptureHandler: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: VideoCaptureError?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "VideoCaptureHandler")
    private var continuation: CheckedContinuation<Data, Error>?
    private var durationTimer: Timer?
    
    // MARK: - Permission Check
    
    /// Checks if camera and microphone access are authorized
    static func checkPermissions() async -> Bool {
        // Check camera
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var cameraGranted = false
        
        switch cameraStatus {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            cameraGranted = false
        @unknown default:
            cameraGranted = false
        }
        
        guard cameraGranted else { return false }
        
        // Check microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch micStatus {
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
    
    // MARK: - Device Check
    
    /// Checks if video recording is available
    static var isVideoRecordingAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) &&
        (UIImagePickerController.availableMediaTypes(for: .camera)?.contains("public.movie") ?? false)
    }
    
    // MARK: - Capture Methods
    
    /// Captures a video using the device camera
    /// - Parameters:
    ///   - maxDuration: Maximum recording duration in seconds
    ///   - quality: Video quality preset
    /// - Returns: Video data
    func captureVideo(maxDuration: TimeInterval = 60, quality: VideoQuality = .medium) async throws -> Data {
        guard Self.isVideoRecordingAvailable else {
            logger.error("Video recording not available")
            throw VideoCaptureError.cameraUnavailable
        }
        
        guard await Self.checkPermissions() else {
            logger.error("Camera/microphone permission denied")
            throw VideoCaptureError.permissionDenied(.video)
        }
        
        isRecording = true
        recordingDuration = 0
        error = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = ["public.movie"]
            picker.delegate = self
            picker.videoMaximumDuration = maxDuration
            picker.videoQuality = quality.uiQuality
            picker.allowsEditing = false
            
            // Present picker
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                
                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                
                topController.present(picker, animated: true) {
                    // Start duration timer
                    self.startDurationTimer()
                }
            } else {
                continuation.resume(throwing: VideoCaptureError.captureFailed)
                self.isRecording = false
            }
        }
    }
    
    /// Saves video data to the device's Photos library
    func saveToPhotosLibrary(_ videoData: Data) async throws {
        // Write to temp file first
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        try videoData.write(to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        guard await PhotoCaptureHandler.checkPhotoLibraryPermission() else {
            throw VideoCaptureError.permissionDenied(.video)
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            } completionHandler: { success, error in
                if success {
                    self.logger.info("Video saved to library")
                    continuation.resume()
                } else {
                    self.logger.error("Failed to save video: \(error?.localizedDescription ?? "unknown")")
                    continuation.resume(throwing: VideoCaptureError.saveFailed)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        let startTime = Date()
        
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - UIImagePickerControllerDelegate

extension VideoCaptureHandler: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        Task { @MainActor in
            stopDurationTimer()
            picker.dismiss(animated: true)
            isRecording = false
            
            guard let videoURL = info[.mediaURL] as? URL else {
                logger.error("No video URL in picker result")
                continuation?.resume(throwing: VideoCaptureError.invalidVideoURL)
                continuation = nil
                return
            }
            
            do {
                let data = try Data(contentsOf: videoURL)
                logger.info("Video captured: \(data.count) bytes, duration: \(self.recordingDuration)s")
                continuation?.resume(returning: data)
                
                // Clean up temp video file
                try? FileManager.default.removeItem(at: videoURL)
            } catch {
                logger.error("Failed to read video data: \(error.localizedDescription)")
                continuation?.resume(throwing: VideoCaptureError.captureFailed)
            }
            continuation = nil
        }
    }
    
    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            stopDurationTimer()
            picker.dismiss(animated: true)
            isRecording = false
            logger.info("Video capture cancelled")
            continuation?.resume(throwing: VideoCaptureError.cancelled)
            continuation = nil
        }
    }
}

// MARK: - VideoQuality Extension

extension VideoQuality {
    var uiQuality: UIImagePickerController.QualityType {
        switch self {
        case .low:
            return .typeLow
        case .medium:
            return .typeMedium
        case .high:
            return .typeHigh
        }
    }
}
