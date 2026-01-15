//
//  MediaComponents.swift
//  Protocol
//
//  Reusable components for viewing media.
//

import SwiftUI
import AVKit

/// Simple photo viewer with zoom support
struct GalleryPhotoViewer: View {
    let url: URL
    
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if phase.error != nil {
                ContentUnavailableView("Failed to load image", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
    }
}

/// Video player wrapper
struct GalleryVideoViewer: View {
    let url: URL
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
    }
}

/// Audio player row for lists
struct GalleryAudioRow: View {
    let capture: MediaCapture
    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    
    var body: some View {
        HStack(spacing: 16) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.parentAtomInstance?.title ?? "Unknown Task")
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(capture.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let duration = capture.totalDuration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onDisappear {
            stopPlayback()
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            do {
                if let relativePath = capture.mediaFileURL {
                    let url = MediaFileManager.shared.absoluteURL(for: relativePath)
                    player = try AVAudioPlayer(contentsOf: url)
                    player?.play()
                    isPlaying = true
                    
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                        guard let p = player else {
                            timer.invalidate()
                            return
                        }
                        if !p.isPlaying {
                            isPlaying = false
                            timer.invalidate()
                        }
                    }
                }
            } catch {
                print("Playback failed: \(error)")
            }
        }
    }
    
    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
