import SwiftUI

/// Solve a small arithmetic problem to dismiss. Three answer buttons instead
/// of a text field: a wrong tap costs a fresh problem, so guessing is slower
/// than reading.
struct MathPuzzleChallengeView: View {
    /// The other challenges this alarm allows, offered as text links.
    let alternatives: [DismissChallenge]
    let onSwitch: (DismissChallenge) -> Void
    let onSolved: () -> Void

    @State private var problem = MathProblem.random()
    @State private var wasWrong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlarmChallengeHeader(eyebrow: "Challenge 1 of 1", title: "Solve to dismiss")

            Text(problem.question)
                .font(.remoteNumeral(54))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .padding(.horizontal, 16)
                .background(AlarmScreenStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityLabel("What is \(problem.spokenQuestion)?")
                .accessibilityIdentifier("mathPuzzleQuestion")
                .padding(.top, 28)

            HStack(spacing: 12) {
                ForEach(Array(problem.choices.enumerated()), id: \.offset) { index, choice in
                    Button { choose(choice) } label: {
                        Text("\(choice)")
                            .font(.remoteNumeral(26))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(AlarmScreenStyle.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mathPuzzleChoice_\(index)")
                }
            }
            .padding(.top, 22)

            if wasWrong {
                Text("Wrong answer. Try again.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.top, 16)
                    .accessibilityIdentifier("mathPuzzleError")
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(alternatives) { challenge in
                    Button(challenge.switchTitle) { onSwitch(challenge) }
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: 44)
                }
            }
            .padding(.top, 20)

            Spacer(minLength: 24)

            Text("The alarm rang once and won't ring again on its own — this screen stays open until you solve it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AlarmScreenStyle.horizontalPadding)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private func choose(_ choice: Int) {
        if choice == problem.answer {
            onSolved()
        } else {
            wasWrong = true
            problem = MathProblem.random()
            UIAccessibility.post(notification: .announcement, argument: "Wrong answer. Try again.")
        }
    }
}
