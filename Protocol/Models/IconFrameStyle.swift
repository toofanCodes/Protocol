//
//  IconFrameStyle.swift
//  Protocol
//
//  Created on 2026-01-04.
//

import Foundation
import CoreGraphics

/// Defines the frame shape for custom icons on Molecules and Atoms
enum IconFrameStyle: String, Codable, CaseIterable, Identifiable {
    case circle = "circle"
    case square = "square"
    case star = "star"
    case triangle = "triangle"
    
    var id: String { rawValue }
    
    /// Display name for pickers
    var displayName: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .star: return "Star"
        case .triangle: return "Triangle"
        }
    }
    
    /// SF Symbol name for this shape (used as background for star/triangle)
    var sfSymbolName: String {
        switch self {
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        case .star: return "star.fill"
        case .triangle: return "triangle.fill"
        }
    }
    
    /// SF Symbol for the picker display
    var pickerSymbol: String {
        switch self {
        case .circle: return "circle"
        case .square: return "square"
        case .star: return "star"
        case .triangle: return "triangle"
        }
    }
    
    /// Returns the appropriate corner radius for border overlays based on shape and size
    func cornerRadius(for size: CGFloat) -> CGFloat {
        switch self {
        case .circle, .star, .triangle:
            return size / 2 // Fully rounded for circles and SF symbols
        case .square:
            return size * 0.22 // Roughly 22% for rounded squares
        }
    }
}
