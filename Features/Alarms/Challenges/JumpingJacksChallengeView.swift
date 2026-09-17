import SwiftUI

/// Do jumping jacks to dismiss. Counted with the *phone's* accelerometer —
/// the wearable's motion data isn't read by this app — so the copy tells the
/// user to keep the phone on them rather than just nearby.
struct JumpingJacksChallengeView: View {
    static let target = 10

    let alternatives: [DismissChallenge]
    let onSwitch: (DismissChallenge) -> Void
    let onSolved: () -> Void

    @State private var counter = JumpingJackCounter()
    @State private var count = 0

    private var target: Int { Self.target }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlarmChallengeHeader(eyebrow: "Movement challenge", title: "\(target) jumping jacks")

            VStack(spacing: 0) {
                Text("\(count) / \(target)")
                    .font(.remoteNumeral(78))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(count) of \(target) jumping jacks")
                    .accessibilityIdentifier("jumpingJacksCount")

                ProgressBar(fraction: Double(count) / Double(target))
                    .padding(.top, 22)

                Text(counter.isAvailable
                     ? "Counted with your phone's motion sensor — hold it in your hand or pocket while you jump."
                     : "This phone has no motion sensor to count jumps. Switch to another challenge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 46)

            Spacer(minLength: 24)

            SwitchChallengeButton(alternatives: alternatives, onSwitch: onSwitch)
        }
        .padding(.horizontal, AlarmScreenStyle.horizontalPadding)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .onAppear {
            counter.start {
                withAnimation { count = min(target, count + 1) }
            }
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

/// The design's thin green bar under the counter.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AlarmScreenStyle.raised)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
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

    var isAvailable: Bool { motionManager.isAccelerometerAvailable }

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
