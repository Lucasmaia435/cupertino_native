import UIKit
import SwiftUI

// MARK: ──────────────────────────────────────────────────────────────────────
// AnimatedMeshGradientView
//
// Real-time GPU-animated gradient background for CNButton.
//
//  • iOS 18+  → SwiftUI MeshGradient (3×3, 9 vertices) inside TimelineView.
//               ProMotion-aware, up to 120 fps.
//  • iOS < 18 → Two CAGradientLayers driven by CADisplayLink at 120 fps,
//               counter-rotating with a soft opacity pulse.
//
// Usage:  call configure(colors:speed:) whenever colors or speed change.
//         The view self-manages its animation lifecycle with the window.
// ────────────────────────────────────────────────────────────────────────────

final class AnimatedMeshGradientView: UIView {

    // MARK: - Configuration

    /// Round (Circle) vs. pill (Capsule) clip shape.
    var isRound: Bool = false {
        didSet {
            setNeedsLayout()
            if #available(iOS 18.0, *) { rebuildMeshView() }
        }
    }

    // MARK: - Private state

    private var gradientColors: [UIColor] = []

    /// 0.0 = frozen · 0.35 = subtle default · 1.0 = full speed.
    /// Applied as a multiplier on the animation clock (t × speed),
    /// so it simultaneously scales both spatial drift and colour evolution.
    private var animationSpeed: Double = 0.35

    // iOS 18+ SwiftUI path
    private var meshHostingController: UIHostingController<AnyView>?

    // iOS < 18 fallback path
    private let fallbackLayer1 = CAGradientLayer()
    private let fallbackLayer2 = CAGradientLayer()
    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    required init?(coder: NSCoder) { nil }

    private func setupView() {
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.masksToBounds = true
        if #available(iOS 13.0, *) { layer.cornerCurve = .continuous }
        isHidden = true

        guard #available(iOS 18.0, *) else {
            fallbackLayer1.frame = bounds
            fallbackLayer2.frame = bounds
            fallbackLayer2.opacity = 0.5
            layer.addSublayer(fallbackLayer1)
            layer.addSublayer(fallbackLayer2)
            return
        }
    }

    // MARK: - Public API

    /// Update colors and/or speed in one call to avoid a double SwiftUI rebuild.
    func configure(colors: [UIColor], speed: Double = 0.35) {
        gradientColors = colors
        animationSpeed = max(0, speed)

        guard !colors.isEmpty else {
            isHidden = true
            tearDown()
            return
        }

        isHidden = false

        if #available(iOS 18.0, *) {
            rebuildMeshView()
        } else {
            if window != nil { startFallback() }
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = isRound
            ? min(bounds.width, bounds.height) / 2
            : bounds.height / 2

        fallbackLayer1.frame = bounds
        fallbackLayer2.frame = bounds
        meshHostingController?.view.frame = bounds
    }

    // MARK: - Window lifecycle

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard #available(iOS 18.0, *) else {
            if newWindow != nil, !gradientColors.isEmpty { startFallback() }
            else { stopFallback() }
            return
        }
        // SwiftUI TimelineView manages its own lifecycle.
    }

    // MARK: - iOS 18+: SwiftUI MeshGradient

    @available(iOS 18.0, *)
    private func rebuildMeshView() {
        meshHostingController?.view.removeFromSuperview()
        meshHostingController = nil

        guard !gradientColors.isEmpty else { return }

        let root = AnyView(
            MeshGradientBackground(
                colors: gradientColors,
                speed: animationSpeed,
                isRound: isRound
            )
        )
        let hc = UIHostingController(rootView: root)
        hc.view.backgroundColor = .clear
        hc.view.frame = bounds
        hc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hc.view.isUserInteractionEnabled = false
        addSubview(hc.view)
        meshHostingController = hc
    }

    // MARK: - Fallback: CADisplayLink

    private func startFallback() {
        guard displayLink == nil else { return }
        animationStartTime = CACurrentMediaTime()
        let dl = CADisplayLink(target: self, selector: #selector(fallbackTick(_:)))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopFallback() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tearDown() {
        stopFallback()
        meshHostingController?.view.removeFromSuperview()
        meshHostingController = nil
    }

    @objc private func fallbackTick(_ link: CADisplayLink) {
        // Multiply wall time by speed so the animation slows or freezes cleanly.
        let effectiveT = (link.timestamp - animationStartTime) * animationSpeed
        renderFallback(t: effectiveT)
    }

    /// Two counter-rotating CAGradientLayers with a soft opacity pulse.
    /// Base rotation periods: ~57 s (layer 1) and ~79 s (layer 2) at speed 1.0.
    /// At the default speed of 0.35 those become ~163 s and ~226 s — imperceptibly slow.
    private func renderFallback(t: Double) {
        guard !gradientColors.isEmpty else { return }
        let cgColors = gradientColors.map(\.cgColor)

        let a1   = t * 0.11
        let s1   = CGPoint(x: 0.5 + 0.30 * sin(a1),       y: 0.5 + 0.30 * cos(a1 * 0.73))
        let e1   = CGPoint(x: 1 - s1.x + 0.06 * sin(a1 * 0.50 + 1.20),
                           y: 1 - s1.y + 0.06 * cos(a1 * 0.60 + 0.50))

        let a2   = t * 0.08 + .pi
        let s2   = CGPoint(x: 0.5 + 0.25 * sin(a2),  y: 0.5 + 0.25 * cos(a2 * 1.10))
        let e2   = CGPoint(x: 1 - s2.x,               y: 1 - s2.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer1.colors = cgColors
        fallbackLayer1.startPoint = s1
        fallbackLayer1.endPoint   = e1
        fallbackLayer2.colors = Array(cgColors.reversed())
        fallbackLayer2.startPoint = s2
        fallbackLayer2.endPoint   = e2
        fallbackLayer2.opacity = Float(0.38 + 0.18 * sin(t * 0.07))
        CATransaction.commit()
    }
}

// MARK: ──────────────────────────────────────────────────────────────────────
// SwiftUI MeshGradient renderer  (iOS 18+)
// ────────────────────────────────────────────────────────────────────────────

@available(iOS 18.0, *)
private struct MeshGradientBackground: View {

    // Pre-extract sRGB components once (struct init) so per-frame math is cheap.
    struct RGBA {
        let r, g, b, a: Double
        init(_ c: UIColor) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            // Ensure we get linear-sRGB values for correct interpolation.
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            self.r = Double(r); self.g = Double(g)
            self.b = Double(b); self.a = Double(a)
        }
    }

    let palette:  [RGBA]
    let speed:    Double   // 0 … 1+
    let isRound:  Bool

    init(colors: [UIColor], speed: Double, isRound: Bool) {
        self.palette  = colors.map { RGBA($0) }
        self.speed    = speed
        self.isRound  = isRound
    }

    // MARK: Body

    var body: some View {
        TimelineView(.animation) { ctx in
            // effectiveT advances at `speed` × wall-clock rate.
            // At speed 0.35 the mesh barely creeps; at 0.0 it is perfectly still.
            let effectiveT = ctx.date.timeIntervalSinceReferenceDate * speed
            gradient(t: effectiveT)
                .clipShape(isRound ? AnyShape(Circle()) : AnyShape(Capsule()))
        }
    }

    // MARK: MeshGradient

    private func gradient(t: Double) -> MeshGradient {
        MeshGradient(
            width:  3, height: 3,
            points: meshPoints(t: t),
            colors: meshColors(t: t),
            smoothsColors: true
        )
    }

    // MARK: Control-point positions
    //
    // Base drift amplitude: 0.030 (subtle at full speed, imperceptible at 0.35×).
    // Frequencies in the 0.05–0.08 Hz range → 12–20 s cycles at speed 1.0,
    // meaning ~35–57 s cycles at the default speed of 0.35.

    private func meshPoints(t: Double) -> [SIMD2<Float>] {
        let amp: Double = 0.030   // max vertex displacement in normalised space

        func drift(
            _ x: Float, _ y: Float,
            fx: Double, fy: Double,
            phase: Double
        ) -> SIMD2<Float> {
            let dx = Float(sin(t * fx + phase)        * amp)
            let dy = Float(cos(t * fy + phase + 0.91) * amp)
            return SIMD2(c01(x + dx), c01(y + dy))
        }

        return [
            // Row 0 — top edge
            SIMD2(0, 0),
            drift(0.5, 0.0,  fx: 0.070, fy: 0.058, phase: 0.00),
            SIMD2(1, 0),
            // Row 1 — middle
            drift(0.0, 0.5,  fx: 0.058, fy: 0.047, phase: 1.50),
            drift(0.5, 0.5,  fx: 0.047, fy: 0.068, phase: 2.80),
            drift(1.0, 0.5,  fx: 0.063, fy: 0.053, phase: 0.90),
            // Row 2 — bottom edge
            SIMD2(0, 1),
            drift(0.5, 1.0,  fx: 0.053, fy: 0.063, phase: 3.70),
            SIMD2(1, 1),
        ]
    }

    // MARK: Per-vertex colour evolution
    //
    // Each vertex cycles between two neighbouring palette entries with a
    // slow smoothstepped sine at ~0.040 Hz → ~25 s period at speed 1.0,
    // or ~71 s at the default 0.35× — so colours shift without any apparent loop.

    private func meshColors(t: Double) -> [Color] {
        guard !palette.isEmpty else {
            return Array(repeating: .black, count: 9)
        }
        let n = palette.count

        // Golden-ratio phase offsets keep adjacent vertices de-correlated.
        let phases: [Double] = [
            0.000, 0.707, 1.414,
            2.121, 2.828, 3.535,
            4.242, 4.949, 5.657,
        ]

        return phases.enumerated().map { (i, phase) in
            let raw   = sin(t * 0.040 + phase) * 0.5 + 0.5   // 0…1
            let blend = smoothstep(raw)

            let a = palette[i % n]
            let b = palette[(i + 1) % n]

            return Color(
                red:     lerp(a.r, b.r, blend),
                green:   lerp(a.g, b.g, blend),
                blue:    lerp(a.b, b.b, blend),
                opacity: lerp(a.a, b.a, blend)
            )
        }
    }

    // MARK: Helpers

    @inline(__always) private func c01(_ v: Float)   -> Float  { min(max(v, 0), 1) }
    @inline(__always) private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    @inline(__always) private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
