//
//  PhotoCaptureHandler.swift
//  Protocol
//
//  Handles photo capture using UIImagePickerController or PHPickerViewController.
//

import Foundation
import UIKit
import Photos
import os.log

// MARK: - Photo Capture Error

enum PhotoCaptureError: LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case captureFailed
    case saveFailed
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device"
        case .permissionDenied:
            return "Camera permission denied"
        case .captureFailed:
            return "Failed to capture photo"
        case .saveFailed:
            return "Failed to save photo"
        case .cancelled:
            return "Photo capture was cancelled"
        }
    }
}

// MARK: - Photo Capture Handler

/// Handles photo capture operations using native iOS camera
@MainActor
final class PhotoCaptureHandler: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isCapturing = false
    @Published var capturedImage: UIImage?
    @Published var error: PhotoCaptureError?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.Toofan.Toofanprotocol", category: "PhotoCaptureHandler")
    private var continuation: CheckedContinuation<Data, Error>?
    
    // MARK: - Permission Check
    
    /// Checks if camera access is authorized
    static func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Checks if photo library access is authorized for saving
    static func checkPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Device Check
    
    /// Checks if the device has a camera
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
    
    /// Checks if the device has a front camera
    static var hasFrontCamera: Bool {
        UIImagePickerController.isCameraDeviceAvailable(.front)
    }
    
    /// Checks if the device has a rear camera
    static var hasRearCamera: Bool {
        UIImagePickerController.isCameraDeviceAvailable(.rear)
    }
    
    // MARK: - Capture Methods
    
    /// Captures a photo using the device camera
    /// - Parameters:
    ///   - useFrontCamera: Whether to use the front-facing camera
    ///   - compressionQuality: JPEG compression quality (0-1)
    /// - Returns: JPEG data of the captured photo
    func capturePhoto(useFrontCamera: Bool = false, compressionQuality: Double = 0.8) async throws -> Data {
        guard Self.isCameraAvailable else {
            logger.error("Camera not available")
            throw PhotoCaptureError.cameraUnavailable
        }
        
        guard await Self.checkCameraPermission() else {
            logger.error("Camera permission denied")
            throw PhotoCaptureError.permissionDenied
        }
        
        isCapturing = true
        error = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            picker.allowsEditing = false
            
            // Select camera based on preference and availability
            if useFrontCamera && Self.hasFrontCamera {
                picker.cameraDevice = .front
            } else {
                picker.cameraDevice = .rear
            }
            
            // Present picker
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                
                // Find the topmost presented view controller
                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                
                topController.present(picker, animated: true)
            } else {
                continuation.resume(throwing: PhotoCaptureError.captureFailed)
                self.isCapturing = false
            }
        }
    }
    
    /// Saves photo data to the device's Photos library
    /// - Parameter data: JPEG data to save
    func saveToPhotosLibrary(_ data: Data) async throws {
        guard await Self.checkPhotoLibraryPermission() else {
            logger.error("Photo library permission denied")
            throw PhotoCaptureError.permissionDenied
        }
        
        guard let image = UIImage(data: data) else {
            throw PhotoCaptureError.saveFailed
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    self.logger.info("Photo saved to library")
                    continuation.resume()
                } else {
                    self.logger.error("Failed to save photo: \(error?.localizedDescription ?? "unknown")")
                    continuation.resume(throwing: PhotoCaptureError.saveFailed)
                }
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension PhotoCaptureHandler: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            isCapturing = false
            
            guard let image = info[.originalImage] as? UIImage else {
                logger.error("No image in picker result")
                continuation?.resume(throwing: PhotoCaptureError.captureFailed)
                continuation = nil
                return
            }
            
            // Compress to JPEG
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                logger.error("Failed to compress image to JPEG")
                continuation?.resume(throwing: PhotoCaptureError.captureFailed)
                continuation = nil
                return
            }
            
            capturedImage = image
            logger.info("Photo captured: \(data.count) bytes")
            continuation?.resume(returning: data)
            continuation = nil
        }
    }
    
    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            isCapturing = false
            logger.info("Photo capture cancelled")
            continuation?.resume(throwing: PhotoCaptureError.cancelled)
            continuation = nil
        }
    }
}
