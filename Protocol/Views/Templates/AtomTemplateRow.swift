//
//  AtomTemplateRow.swift
//  Protocol
//
//  Extracted from ContentView.swift on 2026-01-08.
//

import SwiftUI

struct AtomTemplateRow: View {
    let atom: AtomTemplate
    
    var body: some View {
        HStack(spacing: 10) {
            // Avatar (32x32 - smaller than molecule to show hierarchy)
            AvatarView(
                atom: atom,
                size: 32
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(atom.title)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: atom.inputType.iconName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    
                    Text(atom.inputType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    if let target = atom.targetDisplayString {
                        Text("•")
                        .foregroundStyle(.tertiary)
                        Text(target)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
