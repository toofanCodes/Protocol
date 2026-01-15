//
//  MediaCaptureSheet.swift
//  Protocol
//
//  Unified capture and review interface for media atoms.
//  Transitions between "Capture" and "Review" states seamlessly.
//

import SwiftUI
import SwiftData
import Charts
import AVKit

/// Unified sheet that handles both capturing and reviewing media
struct MediaCaptureSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let atomInstance: AtomInstance
    let settings: MediaCaptureSettings
    
    @State private var captureService = MediaCaptureService.shared
    @State private var viewState: ViewState = .loading
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Audio Playback State
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlayingAudio = false
    @State private var audioProgress: Double = 0
    @State private var audioDuration: TimeInterval = 0
    
    enum ViewState {
        case loading
        case capture
        case review(MediaCapture)
        case provisionalReview(MediaCapture) // Reviewing a retake before committing
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch viewState {
                case .loading:
                    ProgressView()
                case .capture:
                    captureContent
                case .review(let capture):
                    reviewContent(capture: capture, isProvisional: false)
                case .provisionalReview(let capture):
                    reviewContent(capture: capture, isProvisional: true)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .capture = viewState {
                        Button("Cancel") {
                            cancelAndDismiss()
                        }
                    } else if case .provisionalReview = viewState {
                        // In provisional review, "Cancel" acts like Discard
                        Button("Discard") {
                           discardRetake()
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert("Capture Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                determineInitialState()
            }
            .onChange(of: captureService.state) { _, newState in
                if case .completed = newState {
                     // Check if it's a provisional capture (retake)
                    if let pending = captureService.pendingCapture {
                        withAnimation {
                            viewState = .provisionalReview(pending)
                        }
                    } else if let capture = atomInstance.mediaCapture {
                        withAnimation {
                            viewState = .review(capture)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(captureService.state.isActive)
        .onDisappear {
            stopAudioPlayback()
        }
    }
    
    private var navigationTitle: String {
        switch viewState {
        case .capture:
            return settings.captureType.displayName
        case .review:
            return "Review \(settings.captureType.displayName)"
        case .provisionalReview:
            return "Confirm Retake"
        case .loading:
            return ""
        }
    }
    
    private func determineInitialState() {
        if let capture = atomInstance.mediaCapture {
            viewState = .review(capture)
        } else {
            viewState = .capture
        }
    }
    
    // MARK: - Capture Views
    
    @ViewBuilder
    private var captureContent: some View {
        switch settings.captureType {
        case .photo:
            photoCaptureView
        case .video:
            videoCaptureView
        case .audio:
            audioCaptureView
        }
    }
    
    private var photoCaptureView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if captureService.state == .capturing {
                ProgressView("Capturing...")
                    .scaleEffect(1.5)
            } else if captureService.state == .processing {
                ProgressView("Saving...")
                    .scaleEffect(1.5)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                
                Text("Tap below to take a photo")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if captureService.state == .idle {
                Button {
                    startCapture()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Circle()
                                .stroke(.gray, lineWidth: 4)
                        }
                }
            }
            
            Spacer().frame(height: 40)
        }
        .padding()
    }
    
    private var videoCaptureView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if captureService.state == .capturing {
                HStack {
                    Circle().fill(.red).frame(width: 12, height: 12)
                    Text("Recording").foregroundStyle(.red)
                }
                Text(formatDuration(captureService.elapsedTime))
                    .font(.system(.largeTitle, design: .monospaced))
            } else if captureService.state == .processing {
                ProgressView("Saving...")
                    .scaleEffect(1.5)
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if captureService.state == .idle {
                Button {
                    startCapture()
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 80, height: 80)
                }
            } else if captureService.state == .capturing {
                Button {
                    Task {
                       // Video auto-stops usually, or handle manual stop if supported
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                        .frame(width: 80, height: 80)
                }
                .disabled(true) // Placeholder
                
                Text("Recording...")
                    .font(.caption)
            }
            
            Spacer().frame(height: 40)
        }
        .padding()
    }
    
    private var audioCaptureView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                HStack {
                    if captureService.state == .capturing {
                        Circle().fill(.red).frame(width: 12, height: 12)
                        Text("Recording").foregroundStyle(.red)
                    } else if captureService.state == .processing {
                        ProgressView()
                        Text("Processing...")
                    } else {
                        Image(systemName: "mic.fill").foregroundStyle(.secondary)
                        Text("Ready to Record")
                    }
                }
                .font(.headline)
                
                if captureService.state.isActive {
                    Text(formatDuration(captureService.elapsedTime))
                        .font(.system(.largeTitle, design: .monospaced))
                }
            }
            
            Divider()
            
            // Intensity meter
            GeometryReader { geo in
                let intensity = captureService.currentSnoringIntensity
                let width = geo.size.width * (intensity / 100)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4).fill(intensityColor(intensity))
                        .frame(width: max(width, 4))
                        .animation(.linear(duration: 0.1), value: intensity)
                }
            }
            .frame(height: 20)
            
            Spacer()
            
            if captureService.state == .idle {
                Button {
                    startCapture()
                } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if captureService.state == .capturing {
                Button {
                    stopAudioCapture()
                } label: {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
    }
    
    // MARK: - Review Views
    
    @ViewBuilder
    private func reviewContent(capture: MediaCapture, isProvisional: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            if isProvisional {
                Text("Review New Capture")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .padding(.top)
            }
            
            // Content
            Group {
                if capture.captureType == "photo" {
                    reviewPhoto(capture)
                } else if capture.captureType == "video" {
                    reviewVideo(capture)
                } else {
                    reviewAudio(capture)
                }
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
            Divider()
            
            // Action Bar
            HStack(spacing: 20) {
                if isProvisional {
                    // Provisional Actions: Discard vs keep
                    Button(role: .cancel) {
                        discardRetake()
                    } label: {
                         VStack {
                            Image(systemName: "xmark.circle")
                                .font(.title2)
                            Text("Discard")
                                .font(.caption)
                        }
                        .frame(width: 80)
                    }
                    .tint(.secondary)
                    
                    Spacer()
                    
                    Button {
                        commitRetake()
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("Keep This")
                                .font(.caption)
                        }
                        .frame(width: 80)
                    }
                    .tint(.green)
                    
                } else {
                    // Standard Review Actions: Delete vs Retake
                    Button(role: .destructive) {
                        deleteMedia(capture: capture)
                    } label: {
                        VStack {
                            Image(systemName: "trash")
                                .font(.title2)
                            Text("Delete")
                                .font(.caption)
                        }
                        .frame(width: 60)
                    }
                    .tint(.red)
                    
                    Spacer()
                    
                    Button {
                        retakeMedia(capture: capture)
                    } label: {
                        VStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title2)
                            Text("Retake")
                                .font(.caption)
                        }
                        .frame(width: 60)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    @ViewBuilder
    private func reviewPhoto(_ capture: MediaCapture) -> some View {
        if let relativePath = capture.mediaFileURL {
            AsyncImage(url: MediaFileManager.shared.absoluteURL(for: relativePath)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if phase.error != nil {
                    ContentUnavailableView("Failed to load image", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
        } else {
            ContentUnavailableView("No Image", systemImage: "photo.badge.exclamationmark")
        }
    }
    
    @ViewBuilder
    private func reviewVideo(_ capture: MediaCapture) -> some View {
        if let relativePath = capture.mediaFileURL {
            VideoPlayer(player: AVPlayer(url: MediaFileManager.shared.absoluteURL(for: relativePath)))
                .frame(minHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ContentUnavailableView("No Video", systemImage: "video.badge.exclamationmark")
        }
    }
    
    private func reviewAudio(_ capture: MediaCapture) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Audio Recording")
                .font(.headline)
            
            HStack(spacing: 20) {
                if let relativePath = capture.mediaFileURL {
                    Button {
                        toggleAudioPlayback(url: MediaFileManager.shared.absoluteURL(for: relativePath))
                    } label: {
                        Image(systemName: isPlayingAudio ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                    }
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }
            
            if isPlayingAudio {
                Text("Playing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func startCapture() {
        Task {
            do {
                if captureService.pendingCapture != nil {
                   // Shouldn't happen if state flow is correct
                   await captureService.discardRetake(context: modelContext)
                }
                
                // If we are coming from a Retake state (viewState is .capture but we used to have media)
                // We should check if we are truly retaking.
                // The state management is done via Service method call.
                // Check if the Atom has existing media -> Retake Mode
                if atomInstance.mediaCapture != nil {
                    try await captureService.startRetake(for: atomInstance, settings: settings, context: modelContext)
                } else {
                    try await captureService.startCapture(for: atomInstance, settings: settings, context: modelContext)
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func stopAudioCapture() {
        Task {
            do {
                _ = try await captureService.stopAudioCapture(context: modelContext)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func deleteMedia(capture: MediaCapture) {
        Task {
            do {
                try await captureService.deleteMedia(for: atomInstance, context: modelContext)
                withAnimation {
                    dismiss()
                }
            } catch {
                errorMessage = "Failed to delete: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func retakeMedia(capture: MediaCapture) {
        // Safe Retake: Just switch to capture UI.
        // We do NOT delete the old one yet.
        withAnimation {
            viewState = .capture
        }
    }
    
    private func commitRetake() {
        Task {
            do {
                try await captureService.commitRetake(context: modelContext)
                // ViewState will update automatically via onChange of Service state?
                // Service commit sets pending=nil, state=idle.
                // So onChange runs: state=idle. 
                // We need to re-check DetermineInitialState or just force review
                if let newCap = atomInstance.mediaCapture {
                    viewState = .review(newCap)
                }
            } catch {
                 errorMessage = "Failed to save: \(error.localizedDescription)"
                 showError = true
            }
        }
    }
    
    private func discardRetake() {
        Task {
            await captureService.discardRetake(context: modelContext)
            withAnimation {
                // Return to reviewing the original media
                determineInitialState()
            }
        }
    }
    
    private func cancelAndDismiss() {
        captureService.cancelCapture()
        
        // If we were in retake mode, go back to review.
        if atomInstance.mediaCapture != nil {
             determineInitialState()
        } else {
            dismiss()
        }
    }
    
    // MARK: - Audio Helper
    
    private func toggleAudioPlayback(url: URL) {
        if isPlayingAudio {
            stopAudioPlayback()
        } else {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                isPlayingAudio = true
                
                // Monitor completion if needed, for now just simple toggle
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    guard let player = audioPlayer else {
                        timer.invalidate()
                        return
                    }
                    if !player.isPlaying {
                        isPlayingAudio = false
                        timer.invalidate()
                    }
                }
            } catch {
                errorMessage = "Playback failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    private func intensityColor(_ intensity: Double) -> Color {
        switch intensity {
        case 0..<30: return .green
        case 30..<60: return .yellow
        default: return .red
        }
    }
}
