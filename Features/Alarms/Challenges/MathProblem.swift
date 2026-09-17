import Foundation

/// A small mental-arithmetic problem for the math dismiss challenge, with
/// three multiple-choice answers. Choices instead of a number pad keep the
/// challenge one-thumb friendly while half asleep; the distractors are close
/// to the real answer (off by one operand step, or a neighbouring result) so
/// guessing without reading the problem still usually fails.
struct MathProblem: Equatable {
    let firstOperand: Int
    let secondOperand: Int
    let operation: Operation
    /// Exactly three distinct values, one of them `answer`, in random order.
    let choices: [Int]

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

        /// VoiceOver reads "−" and "×" poorly, so the spoken form uses words.
        var spokenName: String {
            switch self {
            case .add: return "plus"
            case .subtract: return "minus"
            case .multiply: return "times"
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

    var spokenQuestion: String { "\(firstOperand) \(operation.spokenName) \(secondOperand)" }

    init(firstOperand: Int, secondOperand: Int, operation: Operation) {
        var generator = SystemRandomNumberGenerator()
        self.init(firstOperand: firstOperand, secondOperand: secondOperand, operation: operation, using: &generator)
    }

    init<G: RandomNumberGenerator>(firstOperand: Int, secondOperand: Int, operation: Operation, using generator: inout G) {
        self.firstOperand = firstOperand
        self.secondOperand = secondOperand
        self.operation = operation
        self.choices = Self.makeChoices(
            answer: operation.apply(firstOperand, secondOperand),
            step: operation == .multiply ? max(1, firstOperand) : 1,
            using: &generator
        )
    }

    static func random() -> MathProblem {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> MathProblem {
        let operation = Operation.allCases.randomElement(using: &generator) ?? .add
        let first = Int.random(in: 2...12, using: &generator)
        let second = Int.random(in: 2...12, using: &generator)
        return MathProblem(
            firstOperand: max(first, second),
            secondOperand: operation == .subtract ? min(first, second) : second,
            operation: operation,
            using: &generator
        )
    }

    /// Distractors are drawn from "plausible slips": a neighbouring times-
    /// table row for multiplication (7×8 → 49, 63), otherwise ±1…±3. Never
    /// negative, never equal to the answer or each other.
    private static func makeChoices<G: RandomNumberGenerator>(answer: Int, step: Int, using generator: inout G) -> [Int] {
        var candidates = [-2, -1, 1, 2].map { answer + $0 * step }
        candidates += [-3, -2, -1, 1, 2, 3].map { answer + $0 }
        var distractors: [Int] = []
        for candidate in candidates.shuffled(using: &generator)
        where candidate >= 0 && candidate != answer && !distractors.contains(candidate) {
            distractors.append(candidate)
            if distractors.count == 2 { break }
        }
        return ([answer] + distractors).shuffled(using: &generator)
    }
}
