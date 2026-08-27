import SwiftUI

struct JumpingJacksChallengeView: View {
    let onSolved: () -> Void
    let target: Int = 10

    @State private var counter = JumpingJackCounter()
    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Do \(target) jumping jacks to dismiss")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(1, Double(count) / Double(target)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(count)/\(target)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("jumpingJacksCount")
            }
            .frame(width: 180, height: 180)
            .padding()

            Text("Hold your phone in your pocket or hand while you jump.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            counter.start { count = min(target, count + 1) }
        }
        .onDisappear { counter.stop() }
        .onChange(of: count) { _, newValue in
            if newValue >= target {
                counter.stop()
                onSolved()
            }
        }
    }
}

import CoreMotion

/// Counts jumps by peak-detecting vertical accelerometer magnitude, the
/// same rough approach as the Android app's `alarm_jumping_jacks_bottom_sheet`.
/// Not step-counter-grade accuracy — good enough for "prove you got out of bed".
private final class JumpingJackCounter {
    private let motionManager = CMMotionManager()
    private var lastPeakAt = Date.distantPast
    private let threshold = 1.8
    private let debounce: TimeInterval = 0.6

    func start(onJump: @escaping () -> Void) {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let magnitude = sqrt(data.acceleration.x * data.acceleration.x
                + data.acceleration.y * data.acceleration.y
                + data.acceleration.z * data.acceleration.z)
            let now = Date()
            if magnitude > threshold, now.timeIntervalSince(lastPeakAt) > debounce {
                lastPeakAt = now
                onJump()
            }
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
    }
}
