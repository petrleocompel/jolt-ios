import SwiftUI

/// Launch splash mirroring the petrleocompel.github.io/jolt-ios hero: a glowing green bolt over
/// black with the product name and tagline. Shown briefly at app start, then
/// cross-fades to `RootView` (see `JoltApp`).
///
/// Deliberately always dark — it's a branded moment, not a system-styled
/// screen — so it matches the marketing site regardless of appearance.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                BoltMark()
                    .fill(Color("AccentColor"))
                    .frame(width: 96, height: 96)
                    .shadow(color: Color("AccentColor").opacity(0.55), radius: 25)
                Text("Jolt Remote")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("For Pavlok wearables")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

/// The lightning-bolt mark from the marketing site, drawn from the same SVG
/// path (`M13 2 4.5 13.5H11l-1 8.5L19.5 10H13z`, 24×24 viewBox) so the app and
/// the website share one silhouette. Centered and scaled to fill the frame.
struct BoltMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale
        func point(_ pointX: CGFloat, _ pointY: CGFloat) -> CGPoint {
            CGPoint(x: originX + pointX * scale, y: originY + pointY * scale)
        }
        var path = Path()
        path.move(to: point(13, 2))
        path.addLine(to: point(4.5, 13.5))
        path.addLine(to: point(11, 13.5))
        path.addLine(to: point(10, 22))
        path.addLine(to: point(19.5, 10))
        path.addLine(to: point(13, 10))
        path.closeSubpath()
        return path
    }
}

#Preview {
    SplashView()
}
