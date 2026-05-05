import SwiftUI

/// Full-bleed background with deep base color, a slowly drifting mesh gradient,
/// and two soft radial glows in opposite corners. Sets the futuristic tone.
struct AnimatedBackground: View {
    @State private var t: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.bgBase.ignoresSafeArea()

            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(),
                colors: [
                    Theme.bgBase,                       Theme.neonViolet.opacity(0.30), Theme.bgBase,
                    Theme.neonCyan.opacity(0.22),       Theme.bgElevated,               Theme.neonMagenta.opacity(0.22),
                    Theme.bgBase,                       Theme.neonViolet.opacity(0.18), Theme.bgBase
                ]
            )
            .ignoresSafeArea()
            .blur(radius: 60)
            .opacity(0.85)

            // Hard radial accent in the top-left
            RadialGradient(
                colors: [Theme.neonViolet.opacity(0.45), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
            .blur(radius: 30)
            .ignoresSafeArea()

            // And a cyan one bottom-right
            RadialGradient(
                colors: [Theme.neonCyan.opacity(0.32), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 460
            )
            .blur(radius: 40)
            .ignoresSafeArea()
        }
        .task {
            // Slow drift on the mesh control points so the gradient breathes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                t += 0.005
            }
        }
    }

    private func meshPoints() -> [SIMD2<Float>] {
        let f = Float(t)
        let s = sin(f) * 0.05
        let c = cos(f) * 0.05
        return [
            .init(0.0, 0.0),         .init(0.5 + s, 0.0), .init(1.0, 0.0),
            .init(0.0, 0.5 + c),     .init(0.5 - s, 0.5 + c), .init(1.0, 0.5 - c),
            .init(0.0, 1.0),         .init(0.5 + c, 1.0), .init(1.0, 1.0)
        ]
    }
}
