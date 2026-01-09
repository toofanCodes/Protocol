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
    
    /// Uses the template's compound to determine background color
    private var blockColor: Color {
        Color.color(forCompound: instance.parentTemplate?.compound)
    }
    
    /// Dynamic text color that contrasts with the tile background
    private var textColor: Color {
        blockColor.contrastingColor
    }
    
    private var atomCountSubtitle: String {
        let count = instance.atomInstances.count
        return "\(count) Task\(count == 1 ? "" : "s")"
    }
    
    /// Whether the scheduled time has passed
    private var isOverdue: Bool {
        !instance.isCompleted && instance.scheduledDate < Date()
    }
    
    /// Progress value (0.0 to 1.0)
    private var progress: Double {
        instance.progress
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Avatar (28x28 for compact calendar view) with contrasting border
            if let template = instance.parentTemplate {
                AvatarView(
                    molecule: template,
                    size: 28
                )
            } else {
                // Fallback for orphaned instances
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                    Text(String(instance.displayTitle.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(textColor.opacity(0.3), lineWidth: 1.5))
            }
            
            // Content with dynamic contrast colors
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(instance.displayTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if instance.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                            .foregroundStyle(textColor)
                    }
                }
                
                Text(atomCountSubtitle)
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.8))
            }
            
            // Progress Strip on right (fills from bottom to top)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Background: Red if overdue and not complete, otherwise subtle
                    Rectangle()
                        .fill(isOverdue ? Color.red.opacity(0.6) : textColor.opacity(0.2))
                    
                    // Progress fill (green, from bottom)
                    Rectangle()
                        .fill(Color.green)
                        .frame(height: geometry.size.height * progress)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(width: 4)
            .clipShape(Capsule())
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [blockColor.opacity(0.7), blockColor.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
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
