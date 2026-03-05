// TrackpadView.swift
// MacPilot — MacPilot-iOS / Views
//
// Fullscreen gesture capture surface that translates
// iPhone touch gestures into Mac input events.

import SwiftUI
import SharedCore

// MARK: - TrackpadView

/// A fullscreen gesture surface for controlling the Mac cursor.
///
/// Supports:
/// - 1 finger drag → mouse movement
/// - Single tap → left click
/// - Two finger tap → right click
/// - Two finger drag → scroll
/// - Pinch → zoom
struct TrackpadView: View {
    @ObservedObject var viewModel: TrackpadViewModel

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.1, blue: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                HStack {
                    Circle()
                        .fill(viewModel.isActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(viewModel.isActive ? "Active" : "Touch to control")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(viewModel.eventsSent) events")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Touch surface
                GeometryReader { geometry in
                    ZStack {
                        // Grid pattern
                        TrackpadGrid()
                            .opacity(0.1)

                        // Center crosshair
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.15))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if value.translation == .zero {
                                    viewModel.panBegan(at: value.location)
                                } else {
                                    viewModel.panChanged(to: value.location)
                                }
                            }
                            .onEnded { _ in
                                viewModel.panEnded()
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 1)
                            .onEnded {
                                viewModel.singleTap()
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                viewModel.pinchChanged(scale: Double(scale))
                            }
                    )
                }
            }

            // Corner labels
            VStack {
                Spacer()
                HStack {
                    Text("Trackpad")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(16)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Grid Pattern

/// Subtle grid pattern for the trackpad surface.
struct TrackpadGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 40
            let lineColor = Color.white

            // Vertical lines
            var x: CGFloat = spacing
            while x < size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                x += spacing
            }

            // Horizontal lines
            var y: CGFloat = spacing
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                y += spacing
            }
        }
    }
}
