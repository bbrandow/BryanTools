import Foundation

enum QuickTaskCalculator {
    static func evaluate(_ input: String) -> Double? {
        let normalized = input
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMathExpression(normalized) else {
            return nil
        }
        var parser = Parser(input: normalized)
        guard let value = parser.parseExpression(),
              parser.isAtEnd,
              value.isFinite else {
            return nil
        }
        return value
    }

    static func formatted(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func isMathExpression(_ input: String) -> Bool {
        guard input.contains(where: { $0.isNumber }) else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^() \t")
        return input.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

private struct Parser {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(input: String) {
        self.scalars = Array(input.unicodeScalars)
    }

    var isAtEnd: Bool {
        mutating get {
            skipWhitespace()
            return index >= scalars.count
        }
    }

    mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else {
            return nil
        }
        while true {
            skipWhitespace()
            if consume("+") {
                guard let rhs = parseTerm() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = parseTerm() else { return nil }
                value -= rhs
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parsePower() else {
            return nil
        }
        while true {
            skipWhitespace()
            if consume("*") {
                guard let rhs = parsePower() else { return nil }
                value *= rhs
            } else if consume("/") {
                guard let rhs = parsePower(), rhs != 0 else { return nil }
                value /= rhs
            } else {
                return value
            }
        }
    }

    private mutating func parsePower() -> Double? {
        guard let value = parseUnary() else {
            return nil
        }
        skipWhitespace()
        if consume("^") {
            guard let exponent = parsePower() else {
                return nil
            }
            return pow(value, exponent)
        }
        return value
    }

    private mutating func parseUnary() -> Double? {
        skipWhitespace()
        if consume("+") {
            return parseUnary()
        }
        if consume("-") {
            return parseUnary().map { -$0 }
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        skipWhitespace()
        if consume("(") {
            guard let value = parseExpression() else {
                return nil
            }
            skipWhitespace()
            return consume(")") ? value : nil
        }
        return parseNumber()
    }

    private mutating func parseNumber() -> Double? {
        skipWhitespace()
        let start = index
        var sawDigit = false
        var sawDecimal = false
        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.decimalDigits.contains(scalar) {
                sawDigit = true
                index += 1
            } else if scalar == "." && !sawDecimal {
                sawDecimal = true
                index += 1
            } else {
                break
            }
        }
        guard sawDigit else {
            return nil
        }
        return Double(String(String.UnicodeScalarView(scalars[start..<index])))
    }

    private mutating func skipWhitespace() {
        while index < scalars.count,
              CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
            index += 1
        }
    }

    private mutating func consume(_ token: UnicodeScalar) -> Bool {
        skipWhitespace()
        guard index < scalars.count, scalars[index] == token else {
            return false
        }
        index += 1
        return true
    }
}
