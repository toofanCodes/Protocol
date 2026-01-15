//
//  MediaCaptureDetailView.swift
//  Protocol
//
//  Detail view for viewing and playing captured media.
//

import SwiftUI
import AVKit

struct MediaCaptureDetailView: View {
    let capture: MediaCapture
    
    @State private var showDeleteAlert = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch capture.type {
                case .photo:
                    photoDetailView
                case .video:
                    videoDetailView
                case .audio:
                    audioDetailView
                case .none:
                    Text("Unknown media type")
                }
            }
            .padding()
        }
        .navigationTitle(capture.type?.displayName ?? "Media")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Media?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteMedia()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    // MARK: - Photo View
    
    @ViewBuilder
    private var photoDetailView: some View {
        if let path = capture.mediaFileURL,
           let data = try? MediaFileManager.shared.loadMedia(relativePath: path),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            metadataSection
        } else {
            errorView("Photo not found")
        }
    }
    
    // MARK: - Video View
    
    @ViewBuilder
    private var videoDetailView: some View {
        if let path = capture.mediaFileURL {
            let url = MediaFileManager.shared.absoluteURL(for: path)
            
            if MediaFileManager.shared.fileExists(at: path) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                metadataSection
            } else {
                errorView("Video not found")
            }
        } else {
            errorView("No video file")
        }
    }
    
    // MARK: - Audio View
    
    @ViewBuilder
    private var audioDetailView: some View {
        // Snoring score header
        VStack(spacing: 8) {
            Text("Snoring Score")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(Int(capture.snoringScore ?? 0))%")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor)
            
            Text(capture.snoringCategory.rawValue)
                .font(.headline)
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(scoreColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        
        // Stats grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Duration", value: capture.durationString ?? "—")
            statCard(title: "Events", value: "\(capture.snoringEventCount ?? 0)")
            
            if let snoringDuration = capture.totalSnoringDuration {
                statCard(title: "Snoring Time", value: formatDuration(snoringDuration))
            }
            
            if let recordingDuration = capture.totalDuration,
               let snoringDuration = capture.totalSnoringDuration {
                let percentage = (snoringDuration / recordingDuration) * 100
                statCard(title: "% of Night", value: String(format: "%.1f%%", percentage))
            }
        }
        
        // Audio player (if full recording saved)
        if let path = capture.mediaFileURL, MediaFileManager.shared.fileExists(at: path) {
            audioPlayerSection
        }
        
        // Snoring events list
        if !capture.snoringEvents.isEmpty {
            snoringEventsSection
        }
        
        // Metadata
        metadataSection
    }
    
    private var scoreColor: Color {
        switch capture.snoringScore ?? 0 {
        case 0..<20: return .green
        case 20..<40: return .mint
        case 40..<60: return .yellow
        case 60..<80: return .orange
        default: return .red
        }
    }
    
    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var audioPlayerSection: some View {
        VStack(spacing: 12) {
            Text("Full Recording")
                .font(.headline)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.blue)
                        .frame(width: geo.size.width * playbackProgress)
                }
            }
            .frame(height: 8)
            
            // Controls
            HStack(spacing: 30) {
                Button {
                    seek(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                }
                
                Button {
                    seek(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
        }
        .padding()
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var snoringEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snoring Events")
                .font(.headline)
            
            ForEach(capture.snoringEvents.sorted(by: { $0.timestamp < $1.timestamp })) { event in
                HStack {
                    Circle()
                        .fill(eventColor(event.intensity))
                        .frame(width: 8, height: 8)
                    
                    if let start = capture.recordingStartTime {
                        Text(formatTimeOffset(event.timeOffset(from: start)))
                            .font(.caption.monospaced())
                    }
                    
                    Spacer()
                    
                    Text(event.durationString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int(event.intensity))%")
                        .font(.caption.bold())
                        .foregroundStyle(eventColor(event.intensity))
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)
            
            HStack {
                Text("Captured")
                Spacer()
                Text(capture.capturedAt, style: .date)
                    .foregroundStyle(.secondary)
            }
            
            if let start = capture.recordingStartTime {
                HStack {
                    Text("Start Time")
                    Spacer()
                    Text(start, style: .time)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let end = capture.recordingEndTime {
                HStack {
                    Text("End Time")
                    Spacer()
                    Text(end, style: .time)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Playback
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let path = capture.mediaFileURL else { return }
        let url = MediaFileManager.shared.absoluteURL(for: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true
            
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                updateProgress()
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer, player.duration > 0 else { return }
        playbackProgress = player.currentTime / player.duration
        
        if !player.isPlaying {
            stopPlayback()
        }
    }
    
    private func seek(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = newTime
    }
    
    private func deleteMedia() {
        if let path = capture.mediaFileURL {
            try? MediaFileManager.shared.deleteMedia(relativePath: path)
        }
        // Note: Actual deletion from SwiftData should be done by the caller
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func formatTimeOffset(_ offset: TimeInterval) -> String {
        let hours = Int(offset) / 3600
        let mins = (Int(offset) % 3600) / 60
        let secs = Int(offset) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func eventColor(_ intensity: Double) -> Color {
        switch intensity {
        case 0..<30: return .green
        case 30..<60: return .yellow
        default: return .red
        }
    }
}
