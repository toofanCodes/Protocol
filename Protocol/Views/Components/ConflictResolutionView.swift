//
//  ConflictResolutionView.swift
//  Protocol
//
//  Created on 2026-01-09.
//

import SwiftUI

/// Conflict info passed to the resolution view
struct SyncConflictInfo: Identifiable {
    let id = UUID()
    let otherDeviceName: String
    let otherDeviceLastSync: Date
    let localRecordCount: Int
    let isOtherDeviceSimulator: Bool
}

/// User's resolution choice
enum ConflictResolution {
    case useThisDevice      // Upload local data, overwrite remote
    case useCloudData       // Download cloud data, overwrite local
    case cancel             // Abort sync
}

/// Modal sheet for resolving sync conflicts between devices
struct ConflictResolutionView: View {
    let conflictInfo: SyncConflictInfo
    let onResolution: (ConflictResolution) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    private var timeSinceOtherSync: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: conflictInfo.otherDeviceLastSync, relativeTo: Date())
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Warning Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .padding(.top, 20)
                
                // Title
                Text("Sync Conflict Detected")
                    .font(.title2.bold())
                
                // Explanation
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("Last synced from:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(conflictInfo.otherDeviceName)
                                .font(.subheadline.bold())
                            Text(timeSinceOtherSync)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    HStack(spacing: 12) {
                        Image(systemName: DeviceIdentity.shared.isSimulator ? "desktopcomputer" : "iphone")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("This device:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(DeviceIdentity.shared.shortDescription)
                                .font(.subheadline.bold())
                            Text("\(conflictInfo.localRecordCount) local records")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Simulator Warning
                if DeviceIdentity.shared.isSimulator {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("You are on a simulator. Syncing may overwrite real device data.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        handleResolution(.useThisDevice)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Use This Device's Data")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessing)
                    
                    Button {
                        handleResolution(.useCloudData)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Use Cloud Data")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessing)
                    
                    Button {
                        handleResolution(.cancel)
                    } label: {
                        Text("Cancel Sync")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.tertiarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    .disabled(isProcessing)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled() // Force user to make a choice
        }
    }
    
    private func handleResolution(_ resolution: ConflictResolution) {
        isProcessing = true
        dismiss()
        onResolution(resolution)
    }
}

// MARK: - Preview

#Preview {
    ConflictResolutionView(
        conflictInfo: SyncConflictInfo(
            otherDeviceName: "John's iPhone 15 Pro",
            otherDeviceLastSync: Date().addingTimeInterval(-3600),
            localRecordCount: 42,
            isOtherDeviceSimulator: false
        ),
        onResolution: { resolution in
            print("User chose: \(resolution)")
        }
    )
}
