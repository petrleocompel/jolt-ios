import SwiftUI

struct MathPuzzleChallengeView: View {
    let onSolved: () -> Void

    @State private var problem = MathProblem.random()
    @State private var answer = ""
    @State private var wasWrong = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Solve to dismiss")
                .font(.title2.bold())
            Text(problem.question)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .accessibilityIdentifier("mathPuzzleQuestion")

            TextField("Answer", text: $answer)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.center)
                .font(.title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .focused($isFocused)
                .accessibilityIdentifier("mathPuzzleAnswerField")
                .onSubmit(submit)

            if wasWrong {
                Text("Not quite — try again.")
                    .foregroundStyle(.red)
            }

            Button("Submit", action: submit)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("mathPuzzleSubmitButton")
        }
        .padding()
        .onAppear { isFocused = true }
    }

    private func submit() {
        if Int(answer.trimmingCharacters(in: .whitespaces)) == problem.answer {
            onSolved()
        } else {
            wasWrong = true
            answer = ""
            problem = MathProblem.random()
        }
    }
}

private struct MathProblem {
    let firstOperand: Int
    let secondOperand: Int
    let operation: Operation
    var answer: Int { operation.apply(firstOperand, secondOperand) }
    var question: String { "\(firstOperand) \(operation.symbol) \(secondOperand)" }

    enum Operation: CaseIterable {
        case add, subtract, multiply

        var symbol: String {
            switch self {
            case .add: return "+"
            case .subtract: return "−"
            case .multiply: return "×"
            }
        }

        func apply(_ lhs: Int, _ rhs: Int) -> Int {
            switch self {
            case .add: return lhs + rhs
            case .subtract: return lhs - rhs
            case .multiply: return lhs * rhs
            }
        }
    }

    static func random() -> MathProblem {
        let operation = Operation.allCases.randomElement() ?? .add
        let first = Int.random(in: 2...12)
        let second = Int.random(in: 2...12)
        return MathProblem(
            firstOperand: max(first, second),
            secondOperand: operation == .subtract ? min(first, second) : second,
            operation: operation
        )
    }
}
