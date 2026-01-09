//
//  DayOfWeekPicker.swift
//  Protocol
//
//  Extracted from ContentView.swift on 2026-01-08.
//

import SwiftUI

struct DayOfWeekPicker: View {
    @Binding var selectedDays: [Int]
    
    private let days = [
        (0, "S"), (1, "M"), (2, "T"), (3, "W"),
        (4, "T"), (5, "F"), (6, "S")
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.0) { day in
                let isSelected = selectedDays.contains(day.0)
                
                Button {
                    toggleDay(day.0)
                } label: {
                    Text(day.1)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func toggleDay(_ day: Int) {
        if let index = selectedDays.firstIndex(of: day) {
            selectedDays.remove(at: index)
        } else {
            selectedDays.append(day)
            selectedDays.sort()
        }
    }
}
