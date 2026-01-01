//
//  AppHeaderView.swift
//  Protocol
//
//  Created on 2025-12-30.
//

import SwiftUI

/// A branded header component for the app
struct AppHeaderView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Logo
                Image(systemName: "cube.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Caption
                Text("Daily Protocol")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    AppHeaderView()
}
