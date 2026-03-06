// TrackpadView.swift
// MacPilot — MacPilot-iOS / Views
//
// Fullscreen gesture capture surface that translates
// iPhone touch gestures into Mac input events.

import SwiftUI
import UIKit
import SharedCore

// MARK: - TrackpadView

/// A fullscreen gesture surface for controlling the Mac cursor.
///
/// Supports:
/// - 1 finger drag → mouse movement
/// - Single tap → left click
/// - Double tap → double click
/// - Two finger tap → right click
/// - Two finger double tap → smart zoom-like double click
/// - Two finger drag → scroll
/// - Three finger tap → Look Up
/// - Three finger drag → drag and drop
/// - Four finger swipe → spaces / mission control
/// - Four finger pinch in/out → launchpad / desktop
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
                GeometryReader { _ in
                    ZStack {
                        // Grid pattern
                        TrackpadGrid()
                            .opacity(0.1)

                        // Center crosshair
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.15))

                        TrackpadGestureSurface(
                            onPanBegan: { point in
                                viewModel.panBegan(at: point)
                            },
                            onPanChanged: { delta in
                                viewModel.panChanged(by: delta)
                            },
                            onPanEnded: {
                                viewModel.panEnded()
                            },
                            onSingleTap: {
                                viewModel.singleTap()
                            },
                            onDoubleTap: {
                                viewModel.doubleTap()
                            },
                            onTwoFingerTap: {
                                viewModel.twoFingerTap()
                            },
                            onTwoFingerDoubleTap: {
                                viewModel.twoFingerDoubleTap()
                            },
                            onThreeFingerTap: {
                                viewModel.threeFingerTapLookup()
                            },
                            onScrollBegan: { point in
                                viewModel.scrollBegan(at: point)
                            },
                            onScrollChanged: { delta in
                                viewModel.scrollChanged(by: delta)
                            },
                            onScrollEnded: { velocity in
                                viewModel.scrollEnded(with: velocity)
                            },
                            onDragBegan: {
                                viewModel.dragBegan()
                            },
                            onDragChanged: { delta in
                                viewModel.dragChanged(by: delta)
                            },
                            onDragEnded: {
                                viewModel.dragEnded()
                            },
                            onFourFingerSwipe: { direction in
                                viewModel.fourFingerSwipe(direction)
                            },
                            onFourFingerPinchIn: {
                                viewModel.launchpadGesture()
                            },
                            onFourFingerPinchOut: {
                                viewModel.showDesktopGesture()
                            },
                            onPinchChanged: { scale in
                                viewModel.pinchChanged(scale: scale)
                            }
                        )
                        .background(Color.clear)
                    }
                    .contentShape(Rectangle())
                }
            }

            // Corner labels
            VStack {
                Spacer()
                HStack {
                    Text("Trackpad • 3F Tap/Drag • 4F Swipe/Pinch")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(16)
                    Spacer()
                }
            }
        }
    }
}

private struct TrackpadGestureSurface: UIViewRepresentable {
    let onPanBegan: (CGPoint) -> Void
    let onPanChanged: (CGPoint) -> Void
    let onPanEnded: () -> Void
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onTwoFingerTap: () -> Void
    let onTwoFingerDoubleTap: () -> Void
    let onThreeFingerTap: () -> Void
    let onScrollBegan: (CGPoint) -> Void
    let onScrollChanged: (CGPoint) -> Void
    let onScrollEnded: (CGPoint) -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onFourFingerSwipe: (TrackpadViewModel.MultiFingerSwipeDirection) -> Void
    let onFourFingerPinchIn: () -> Void
    let onFourFingerPinchOut: () -> Void
    let onPinchChanged: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let oneFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.delegate = context.coordinator
        oneFingerPan.cancelsTouchesInView = false

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = context.coordinator
        twoFingerPan.cancelsTouchesInView = false

        let threeFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleThreeFingerPan(_:)))
        threeFingerPan.minimumNumberOfTouches = 3
        threeFingerPan.maximumNumberOfTouches = 3
        threeFingerPan.delegate = context.coordinator
        threeFingerPan.cancelsTouchesInView = false

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTouchesRequired = 1
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: oneFingerPan)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)

        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.require(toFail: twoFingerPan)

        let twoFingerDoubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerDoubleTap(_:)))
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerTap.require(toFail: twoFingerDoubleTap)

        let threeFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleThreeFingerTap(_:)))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.numberOfTapsRequired = 1
        threeFingerTap.require(toFail: threeFingerPan)

        let swipeLeft4 = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFourFingerSwipe(_:)))
        swipeLeft4.numberOfTouchesRequired = 4
        swipeLeft4.direction = .left

        let swipeRight4 = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFourFingerSwipe(_:)))
        swipeRight4.numberOfTouchesRequired = 4
        swipeRight4.direction = .right

        let swipeUp4 = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFourFingerSwipe(_:)))
        swipeUp4.numberOfTouchesRequired = 4
        swipeUp4.direction = .up

        let swipeDown4 = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFourFingerSwipe(_:)))
        swipeDown4.numberOfTouchesRequired = 4
        swipeDown4.direction = .down

        // Prefer explicit multi-finger swipes over three-finger drag.
        threeFingerPan.require(toFail: swipeLeft4)
        threeFingerPan.require(toFail: swipeRight4)
        threeFingerPan.require(toFail: swipeUp4)
        threeFingerPan.require(toFail: swipeDown4)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(oneFingerPan)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(threeFingerPan)
        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(twoFingerTap)
        view.addGestureRecognizer(twoFingerDoubleTap)
        view.addGestureRecognizer(threeFingerTap)
        view.addGestureRecognizer(swipeLeft4)
        view.addGestureRecognizer(swipeRight4)
        view.addGestureRecognizer(swipeUp4)
        view.addGestureRecognizer(swipeDown4)
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let parent: TrackpadGestureSurface
        private var lastOneFingerTranslation: CGPoint = .zero
        private var lastTwoFingerTranslation: CGPoint = .zero
        private var lastThreeFingerTranslation: CGPoint = .zero
        private var didFireFourFingerPinchAction = false

        init(_ parent: TrackpadGestureSurface) {
            self.parent = parent
        }

        @objc func handleOneFingerPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastOneFingerTranslation = .zero
                gesture.setTranslation(.zero, in: gesture.view)
                parent.onPanBegan(.zero)
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = CGPoint(
                    x: translation.x - lastOneFingerTranslation.x,
                    y: translation.y - lastOneFingerTranslation.y
                )
                lastOneFingerTranslation = translation
                parent.onPanChanged(delta)
            case .ended, .cancelled, .failed:
                parent.onPanEnded()
            default:
                break
            }
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastTwoFingerTranslation = .zero
                gesture.setTranslation(.zero, in: gesture.view)
                parent.onScrollBegan(.zero)
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = CGPoint(
                    x: translation.x - lastTwoFingerTranslation.x,
                    y: translation.y - lastTwoFingerTranslation.y
                )
                lastTwoFingerTranslation = translation
                parent.onScrollChanged(delta)
            case .ended:
                parent.onScrollEnded(gesture.velocity(in: gesture.view))
            case .cancelled, .failed:
                parent.onScrollEnded(.zero)
            default:
                break
            }
        }

        @objc func handleThreeFingerPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastThreeFingerTranslation = .zero
                gesture.setTranslation(.zero, in: gesture.view)
                parent.onDragBegan()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = CGPoint(
                    x: translation.x - lastThreeFingerTranslation.x,
                    y: translation.y - lastThreeFingerTranslation.y
                )
                lastThreeFingerTranslation = translation
                parent.onDragChanged(delta)
            case .ended, .cancelled, .failed:
                parent.onDragEnded()
            default:
                break
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                parent.onSingleTap()
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                parent.onDoubleTap()
            }
        }

        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                parent.onTwoFingerTap()
            }
        }

        @objc func handleTwoFingerDoubleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                parent.onTwoFingerDoubleTap()
            }
        }

        @objc func handleThreeFingerTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                parent.onThreeFingerTap()
            }
        }

        @objc func handleFourFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard gesture.state == .ended else { return }
            switch gesture.direction {
            case .left:
                parent.onFourFingerSwipe(.left)
            case .right:
                parent.onFourFingerSwipe(.right)
            case .up:
                parent.onFourFingerSwipe(.up)
            case .down:
                parent.onFourFingerSwipe(.down)
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                didFireFourFingerPinchAction = false
            case .changed:
                // Four-finger pinch gestures are mapped to desktop/launchpad.
                if gesture.numberOfTouches >= 4 {
                    guard !didFireFourFingerPinchAction else { return }
                    if gesture.scale <= 0.88 {
                        didFireFourFingerPinchAction = true
                        parent.onFourFingerPinchIn()
                    } else if gesture.scale >= 1.12 {
                        didFireFourFingerPinchAction = true
                        parent.onFourFingerPinchOut()
                    }
                    return
                }

                parent.onPinchChanged(Double(gesture.scale))
                // Send incremental pinch values to keep zoom smooth.
                gesture.scale = 1.0
            case .ended, .cancelled, .failed:
                didFireFourFingerPinchAction = false
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
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
