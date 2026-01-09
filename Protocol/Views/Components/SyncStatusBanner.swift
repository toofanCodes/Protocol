//
//  SyncStatusBanner.swift
//  Protocol
//
//  Created on 2026-01-08.
//

import SwiftUI

/// A non-intrusive banner that displays sync status at the top of the screen.
/// Automatically shows/hides based on SyncEngine state.
struct SyncStatusBanner: View {
    @EnvironmentObject private var syncEngine: SyncEngine
    
    /// Tracks if user manually dismissed the banner
    @State private var isManuallyDismissed = false
    
    /// Track swipe offset for gesture
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        Group {
            if isManuallyDismissed {
                EmptyView()
            } else {
                switch syncEngine.syncStatus {
                case .idle:
                    EmptyView()
                    
                case .syncing(let message):
                    bannerView(
                        icon: "arrow.triangle.2.circlepath",
                        message: message,
                        color: .blue,
                        isAnimating: true
                    )
                    
                case .success(let message):
                    bannerView(
                        icon: "checkmark.circle.fill",
                        message: message,
                        color: .green,
                        isAnimating: false
                    )
                    
                case .failed(let message):
                    bannerView(
                        icon: "exclamationmark.triangle.fill",
                        message: message,
                        color: .orange,
                        isAnimating: false,
                        showDismiss: true
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: syncEngine.syncStatus)
        .animation(.easeInOut(duration: 0.3), value: isManuallyDismissed)
        // Reset manual dismissal when status changes (e.g., new sync starts)
        .onChange(of: syncEngine.syncStatus) { _, newValue in
            if case .syncing = newValue {
                isManuallyDismissed = false
            }
        }
    }
    
    // MARK: - Banner View Builder
    
    @ViewBuilder
    private func bannerView(
        icon: String,
        message: String,
        color: Color,
        isAnimating: Bool,
        showDismiss: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    isAnimating ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isAnimating
                )
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if showDismiss {
                Button {
                    syncEngine.dismissStatus()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: color.opacity(0.2), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
        .offset(y: dragOffset)
        .opacity(1.0 - (abs(dragOffset) / 100.0))  // Fade as swiped
        // Tap to dismiss
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                isManuallyDismissed = true
            }
        }
        // Swipe up to dismiss
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow upward swipe (negative translation)
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // If swiped up more than 30pt, dismiss
                    if value.translation.height < -30 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isManuallyDismissed = true
                            dragOffset = 0
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        SyncStatusBanner()
            .environmentObject(SyncEngine.shared)
        
        Spacer()
    }
}
