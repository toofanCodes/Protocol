//
//  MediaGalleryView.swift
//  Protocol
//
//  Central gallery for viewing and managing captured media.
//

import SwiftUI
import SwiftData

struct MediaGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Sort by date descending
    @Query(sort: \MediaCapture.capturedAt, order: .reverse) private var allMedia: [MediaCapture]
    
    @State private var selectedFilter: MediaFilter = .all
    @State private var selectedMedia: MediaCapture?
    @State private var showDeleteConfirmation = false
    @State private var mediaToDelete: MediaCapture?
    
    // Grid columns
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    enum MediaFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case photo = "Photos"
        case video = "Videos"
        case audio = "Audio"
        
        var id: String { rawValue }
    }
    
    var filteredMedia: [MediaCapture] {
        switch selectedFilter {
        case .all:
            return allMedia
        case .photo:
            return allMedia.filter { $0.captureType == "photo" }
        case .video:
            return allMedia.filter { $0.captureType == "video" }
        case .audio:
            return allMedia.filter { $0.captureType == "audio" }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter
            Picker("Filter", selection: $selectedFilter) {
                ForEach(MediaFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            if filteredMedia.isEmpty {
                ContentUnavailableView(
                    "No Media Found",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Captured photos, videos, and audio will appear here.")
                )
            } else {
                ScrollView {
                    if selectedFilter == .audio {
                        audioList
                    } else {
                        mediaGrid
                    }
                }
            }
        }
        .navigationTitle("Media Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMedia) { media in
            MediaDetailView(media: media)
        }
    }
    
    // MARK: - Views
    
    private var mediaGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(filteredMedia) { media in
                Button {
                    selectedMedia = media
                } label: {
                    GeometryReader { geo in
                        if let relativePath = media.mediaFileURL {
                            if media.captureType == "photo" {
                                GalleryPhotoViewer(url: MediaFileManager.shared.absoluteURL(for: relativePath))
                            } else if media.captureType == "video" {
                                ZStack {
                                    Color.black
                                    Image(systemName: "video.fill")
                                        .foregroundStyle(.white)
                                }
                                .frame(width: geo.size.width, height: geo.size.width)
                            } else {
                                // Audio in grid (if mixed view)
                                ZStack {
                                    Color.gray.opacity(0.2)
                                    Image(systemName: "waveform")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: geo.size.width, height: geo.size.width)
                            }
                        } else {
                            ContentUnavailableView("Missing File", systemImage: "exclamationmark.triangle")
                                .frame(width: geo.size.width, height: geo.size.width)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        confirmDelete(media)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    if let taskName = media.parentAtomInstance?.title {
                        Text("Task: \(taskName)")
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }
    
    private var audioList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredMedia) { media in
                GalleryAudioRow(capture: media)
                    .padding()
                    .contextMenu {
                        Button(role: .destructive) {
                            confirmDelete(media)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                Divider()
            }
        }
    }
    
    // MARK: - Actions
    
    private func confirmDelete(_ media: MediaCapture) {
        mediaToDelete = media
        showDeleteConfirmation = true
    }
    
    private func deleteMedia() {
        guard let media = mediaToDelete else { return }
        
        Task {
            do {
                if let atom = media.parentAtomInstance {
                    // Use service to delete safely and sync state
                    try await MediaCaptureService.shared.deleteMedia(for: atom, context: modelContext)
                } else {
                    // Orphaned media (shouldn't happen often, but handle handle manual delete)
                    // If no atom, we just delete file + record
                    if let path = media.mediaFileURL {
                        try MediaFileManager.shared.deleteMedia(relativePath: path)
                    }
                    modelContext.delete(media)
                }
            } catch {
                print("Error deleting media: \(error)")
            }
            mediaToDelete = nil
        }
    }
}

// MARK: - Detail View wrapper

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let media: MediaCapture
    
    var body: some View {
        NavigationStack {
            Group {
                if let relativePath = media.mediaFileURL {
                    if media.captureType == "photo" {
                        GalleryPhotoViewer(url: MediaFileManager.shared.absoluteURL(for: relativePath))
                            .aspectRatio(contentMode: .fit)
                    } else if media.captureType == "video" {
                        GalleryVideoViewer(url: MediaFileManager.shared.absoluteURL(for: relativePath))
                    } else {
                        Text("Audio playback supported in list view")
                    }
                } else {
                   ContentUnavailableView("Media Missing", systemImage: "questionmark.folder")
                }
            }
            .navigationTitle(media.parentAtomInstance?.title ?? "Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        deleteAndDismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
    
    private func deleteAndDismiss() {
        Task {
            if let atom = media.parentAtomInstance {
                try? await MediaCaptureService.shared.deleteMedia(for: atom, context: modelContext)
            }
            dismiss()
        }
    }
}
