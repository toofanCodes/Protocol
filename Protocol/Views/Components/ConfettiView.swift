//
//  ConfettiView.swift
//  Protocol
//
//  Created on 2026-01-04.
//

import SwiftUI

// MARK: - Particle Shape

enum ParticleShape: CaseIterable {
    case circle
    case square
    case ribbon
    case star
}

// MARK: - Confetti Particle

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var color: Color
    var size: CGFloat
    var shape: ParticleShape
    var rotation: Double
    var rotationSpeed: Double
    var rotation3D: Double = 0 // For ribbon/3D effect
    var rotation3DSpeed: Double = 0
    var lifetime: Double = 0
    var maxLifetime: Double = 3.0
    
    var opacity: Double {
        // Fade out in last 20% of lifetime
        let fadeStart = maxLifetime * 0.8
        if lifetime > fadeStart {
            return 1.0 - ((lifetime - fadeStart) / (maxLifetime * 0.2))
        }
        return 1.0
    }
    
    var isExpired: Bool {
        lifetime >= maxLifetime
    }
}

// MARK: - Confetti Engine

class ConfettiEngine {
    var particles: [ConfettiParticle] = []
    private let maxParticles = 200
    private var lastUpdate: Date = Date()
    
    /// Generate colors based on a theme color
    func generateColors(from themeColor: Color) -> [Color] {
        // ... (keep same)
        // Theme color + complementary/accent colors
        return [
            themeColor,
            themeColor.opacity(0.8),
            .white,
            .yellow.opacity(0.9), // Gold accent
            Color(hue: 0.1, saturation: 0.9, brightness: 1.0), // Orange accent
        ]
    }
    
    func burst(at position: CGPoint, count: Int = 50, colors: [Color]) {
        // Enforce max particle limit
        let availableSlots = max(0, maxParticles - particles.count)
        let actualCount = min(count, availableSlots)
        
        for _ in 0..<actualCount {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 200...600)
            let shape = ParticleShape.allCases.randomElement()!
            
            // Ribbons are thinner
            let baseSize: CGFloat = shape == .ribbon ? CGFloat.random(in: 3...6) : CGFloat.random(in: 6...12)
            
            particles.append(
                ConfettiParticle(
                    position: position,
                    velocity: CGPoint(
                        x: CGFloat(cos(angle) * speed * 0.6),
                        y: CGFloat(sin(angle) * speed * 0.4) - 200 // Initial upward burst
                    ),
                    color: colors.randomElement()!,
                    size: baseSize,
                    shape: shape,
                    rotation: Double.random(in: 0...360),
                    rotationSpeed: Double.random(in: -8...8),
                    rotation3D: 0,
                    rotation3DSpeed: shape == .ribbon ? Double.random(in: -10...10) : Double.random(in: -3...3),
                    lifetime: 0,
                    maxLifetime: Double.random(in: 2.5...4.0)
                )
            )
        }
    }
    
    func update(currentTime: Date, size: CGSize) {
        let delta = min(currentTime.timeIntervalSince(lastUpdate), 0.05)
        lastUpdate = currentTime
        
        let gravity: CGFloat = 800 // Increased gravity for snappier feel
        let friction: CGFloat = 0.985
        let windSway = sin(Date().timeIntervalSinceReferenceDate * 2) * 20 
        
        for i in particles.indices {
            // Update lifetime
            particles[i].lifetime += delta
            
            // Gravity
            particles[i].velocity.y += gravity * CGFloat(delta)
            
            // Wind sway
            particles[i].velocity.x += CGFloat(windSway) * CGFloat(delta)
            
            // Friction/Drag
            particles[i].velocity.x *= friction
            particles[i].velocity.y *= friction
            
            // Position update
            particles[i].position.x += particles[i].velocity.x * CGFloat(delta)
            particles[i].position.y += particles[i].velocity.y * CGFloat(delta)
            
            // Rotation
            particles[i].rotation += particles[i].rotationSpeed
            particles[i].rotation3D += particles[i].rotation3DSpeed
        }
        
        // Remove expired particles
        particles.removeAll { $0.isExpired || $0.position.y > size.height + 50 }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @ObservedObject var celebrationState: CelebrationState
    @State private var engine = ConfettiEngine()
    
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let now = timeline.date
                
                Canvas { context, size in
                    // Update physics synchronously
                    engine.update(currentTime: now, size: size)
                    
                    for particle in engine.particles {
                        var pContext = context
                        pContext.translateBy(x: particle.position.x, y: particle.position.y)
                        pContext.rotate(by: .degrees(particle.rotation))
                        pContext.opacity = particle.opacity
                        
                        // 3D rotation effect (scale X based on rotation)
                        let scaleX = abs(cos(particle.rotation3D * .pi / 180))
                        
                        drawParticle(context: &pContext, particle: particle, scaleX: scaleX)
                    }
                }
            }
            .onChange(of: celebrationState.confettiCounter) { _, _ in
                // Spawn from top-center with current settings
                let startPos = CGPoint(x: geometry.size.width / 2, y: -30)
                let colors = engine.generateColors(from: celebrationState.celebrationColor)
                let count = 50 // Standard burst size
                
                engine.burst(at: startPos, count: count, colors: colors)
            }
        }
        .allowsHitTesting(false)
    }
    
    private func drawParticle(context: inout GraphicsContext, particle: ConfettiParticle, scaleX: CGFloat) {
        let size = particle.size
        
        switch particle.shape {
        case .circle:
            let rect = CGRect(x: -size/2, y: -size/2, width: size, height: size)
            context.fill(Circle().path(in: rect), with: .color(particle.color))
            
        case .square:
            let rect = CGRect(x: -size/2, y: -size/2, width: size, height: size)
            context.fill(RoundedRectangle(cornerRadius: 1).path(in: rect), with: .color(particle.color))
            
        case .ribbon:
            // Thin rectangle with 3D rotation (width scales)
            let width = size * 0.4 * max(0.1, scaleX)
            let height = size * 2
            let rect = CGRect(x: -width/2, y: -height/2, width: width, height: height)
            context.fill(RoundedRectangle(cornerRadius: 1).path(in: rect), with: .color(particle.color))
            
        case .star:
            // Simple 4-point star using two overlapping rectangles
            let rect1 = CGRect(x: -size/2, y: -size/6, width: size, height: size/3)
            let rect2 = CGRect(x: -size/6, y: -size/2, width: size/3, height: size)
            context.fill(Rectangle().path(in: rect1), with: .color(particle.color))
            context.fill(Rectangle().path(in: rect2), with: .color(particle.color))
        }
    }
}
