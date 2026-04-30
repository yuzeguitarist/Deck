// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  AIChatBreathingDot.swift
//  Deck
//
//  Pulsing breathing-dot animation for AI thinking state.
//

import SwiftUI
import AppKit
import QuartzCore

struct AIChatBreathingDot: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AIChatBreathingDotRepresentable(
            color: colorScheme == .dark ? .white : .black
        )
        .frame(width: 8, height: 8)
    }
}

private struct AIChatBreathingDotRepresentable: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> DotView {
        DotView(color: color)
    }

    func updateNSView(_ nsView: DotView, context: Context) {
        nsView.updateColor(color)
    }

    final class DotView: NSView {
        private let dotLayer = CALayer()

        init(color: NSColor) {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = false
            dotLayer.masksToBounds = true
            layer?.addSublayer(dotLayer)
            updateColor(color)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            return nil
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dotLayer.frame = bounds
            dotLayer.cornerRadius = min(bounds.width, bounds.height) * 0.5
            CATransaction.commit()
            ensureAnimation()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                dotLayer.removeAllAnimations()
            } else {
                ensureAnimation()
            }
        }

        func updateColor(_ color: NSColor) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dotLayer.backgroundColor = color.cgColor
            CATransaction.commit()
            ensureAnimation()
        }

        private func ensureAnimation() {
            guard dotLayer.animation(forKey: Self.animationKey) == nil else { return }

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 1.28

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1.0
            opacity.toValue = 0.38

            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = 1.35
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false

            dotLayer.add(group, forKey: Self.animationKey)
        }

        private static let animationKey = "deck.ai-chat.breathing-dot"
    }
}
