//
//  MoleculeBlockView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

/// A visual representation of a MoleculeInstance on the calendar
struct MoleculeBlockView: View {
    let instance: MoleculeInstance
    
    // MARK: - Constants
    
    private let cornerRadius: CGFloat = 8
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        let title = instance.displayTitle.lowercased()
        
        if title.contains("lift") || title.contains("workout") || title.contains("gym") {
            return .blue.opacity(0.8)
        } else if title.contains("routine") || title.contains("skin") {
            return .teal.opacity(0.8)
        } else if title.contains("medication") || title.contains("thyroid") {
            return .purple.opacity(0.8)
        } else {
            return Color.accentColor.opacity(0.8)
        }
    }
    
    private var atomCountSubtitle: String {
        let count = instance.atomInstances.count
        return "\(count) Task\(count == 1 ? "" : "s")"
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            // Status Strip
            Rectangle()
                .fill(instance.isCompleted ? Color.green : Color.white.opacity(0.5))
                .frame(width: 4)
                .clipShape(Capsule())
                .padding(.vertical, 4)
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(instance.displayTitle)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    if instance.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                
                Text(atomCountSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                
                if let notes = instance.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 6)
            
            Spacer(minLength: 0)
        }

        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview
// MARK: - Preview
#Preview {
    MoleculeBlockPreviewWrapper()
}

private struct MoleculeBlockPreviewWrapper: View {
    let container: ModelContainer
    
    init() {
        do {
            container = try OnboardingManager.createPreviewContainer()
        } catch {
            fatalError("Failed to create preview container")
        }
    }
    
    var body: some View {
        MoleculeBlockPreviewContent()
            .modelContainer(container)
    }
}

private struct MoleculeBlockPreviewContent: View {
    @Query private var instances: [MoleculeInstance]
    
    var body: some View {
        VStack(spacing: 20) {
            if let instance = instances.first {
                MoleculeBlockView(instance: instance)
                    .frame(height: 60)
                    .padding()
                
                MoleculeBlockView(instance: instance)
                    .frame(width: 200, height: 80)
            } else {
                Text("No preview data")
            }
        }
    }
}
