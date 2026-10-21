import Foundation

/// Math-only calculator distilled from Tinycast's CalcEngine path (no units/currency/dates).
///
/// Type an expression in the launcher (`2+2`, `sqrt(9)`, `10% of 50`). A lead result row
/// appears when the query is a real calculation — lone literals stay app search.
enum Calculator {
    struct Result: Equatable, Sendable {
        /// Normalized expression echo ("2 × 2").
        let expression: String
        /// Grouped display ("1,234").
        let display: String
        /// Ungrouped pasteboard text ("1234").
        let copyText: String
    }

    /// `nil` when the query is not calculator input (app search continues alone).
    nonisolated static func evaluate(_ raw: String) -> Result? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256 else { return nil }

        // Tolerate a trailing "=" ("2+2=") — Tinycast does the same.
        var query = trimmed
        if query.hasSuffix("=") {
            query = String(query.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
        }

        guard let tokens = Tokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        // Trailing binary op: keep the last complete prefix on the card while typing.
        if let trailing = tokens.last, trailing.isPartialBinaryOperator {
            let prefix = Array(tokens.dropLast())
            guard !prefix.isEmpty else { return nil }
            // A lone literal prefix (`10*`) still shows; multi-token needs a real op.
            let requireOperation = prefix.count > 1
            guard let value = Parser.scalar(prefix, requireOperation: requireOperation) else {
                return nil
            }
            return makeResult(expression: Formatter.expression(query), value: value)
        }

        // A lone literal reads as an app search — except compact forms ("10k") and radix ("0xff").
        if tokens.count == 1 {
            switch tokens[0] {
            case .compactNumber(let value):
                return makeResult(expression: Formatter.expression(query), value: value)
            case .intLiteral(let value, let base) where base != .decimal:
                let text = String(value)
                return Result(
                    expression: query,
                    display: Formatter.grouped(text),
                    copyText: text
                )
            default:
                return nil
            }
        }

        guard let value = Parser.scalar(tokens, requireOperation: true) else { return nil }
        return makeResult(expression: Formatter.expression(query), value: value)
    }

    private nonisolated static func makeResult(expression: String, value: Double) -> Result? {
        guard value.isFinite else { return nil }
        let copy = Formatter.copyText(value)
        return Result(
            expression: expression,
            display: Formatter.grouped(copy),
            copyText: copy
        )
    }
}

// MARK: - Tokens

private enum CalcToken: Equatable {
    case number(Double)
    case compactNumber(Double)
    case intLiteral(UInt64, base: NumberBase)
    case ident(String)
    case op(CalcOp)
    case comma

    var isPartialBinaryOperator: Bool {
        guard case .op(let op) = self else { return false }
        switch op {
        case .add, .subtract, .multiply, .divide, .power: return true
        default: return false
        }
    }
}

private enum NumberBase: Int, Equatable {
    case binary = 2
    case octal = 8
    case decimal = 10
    case hexadecimal = 16

    var prefix: String {
        switch self {
        case .binary: return "0b"
        case .octal: return "0o"
        case .decimal: return ""
        case .hexadecimal: return "0x"
        }
    }
}

private enum CalcOp: Equatable {
    case add, subtract, multiply, divide, power
    case factorial, percent
    case open, close
    case equal, notEqual, less, greater, lessEqual, greaterEqual

    var bindingPower: Int? {
        switch self {
        case .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual: return 2
        case .add, .subtract: return 10
        case .multiply, .divide: return 20
        case .power: return 30
        default: return nil
        }
    }
}

// MARK: - Math library (Tinycast CalcMath, scalar subset)

private enum CalcMath {
    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "log": { log10($0) }, "ln": { log($0) }, "sin": { sin($0) },
        "cos": { cos($0) }, "tan": { tan($0) }, "abs": { abs($0) }, "floor": { floor($0) },
        "ceil": { ceil($0) }, "round": { $0.rounded() },
        "cot": { 1 / tan($0) }, "sec": { 1 / cos($0) }, "csc": { 1 / sin($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "arcsin": { asin($0) }, "arccos": { acos($0) }, "arctan": { atan($0) },
        "sinh": { sinh($0) }, "cosh": { cosh($0) }, "tanh": { tanh($0) },
        "asinh": { asinh($0) }, "acosh": { acosh($0) }, "atanh": { atanh($0) },
        "cbrt": { cbrt($0) }, "exp": { exp($0) }, "log2": { log2($0) },
        "sign": { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) }, "trunc": { $0.rounded(.towardZero) },
    ]

    static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "τ": 2 * .pi, "phi": (1 + sqrt(5.0)) / 2,
    ]

    static let multipleArguments: Set<String> = [
        "hypot", "round", "log", "gcd", "lcm", "atan2", "pow", "root", "fmod",
        "min", "max", "sum", "avg", "mean", "average",
    ]

    static func isFunction(_ name: String) -> Bool {
        functions[name] != nil || multipleArguments.contains(name)
    }

    static func factorial(_ value: Double) -> Double? {
        guard value >= 0, value.rounded() == value, value <= 170 else { return nil }
        var result = 1.0
        var next = 2.0
        while next <= value {
            result *= next
            next += 1
        }
        return result
    }

    static func evaluate(_ name: String, _ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        let first = values[0]
        let result: Double
        switch name {
        case "min": result = values.min() ?? first
        case "max": result = values.max() ?? first
        case "sum": result = values.reduce(0, +)
        case "avg", "mean", "average":
            result = values.reduce(0) { $0 + $1 / Double(values.count) }
        case "hypot": result = values.reduce(0) { hypot($0, $1) }
        case "gcd", "lcm":
            var accumulator: Int64 = name == "gcd" ? 0 : 1
            for value in values {
                guard let integer = exactInteger(value) else { return nil }
                let positive = abs(integer)
                var a = accumulator
                var b = positive
                while b != 0 { (a, b) = (b, a % b) }
                if name == "gcd" {
                    accumulator = a
                } else if a == 0 {
                    accumulator = 0
                } else {
                    let product = (accumulator / a).multipliedReportingOverflow(by: positive)
                    guard !product.overflow else { return nil }
                    accumulator = product.partialValue
                }
            }
            return abs(Double(accumulator)) < 9_007_199_254_740_992 ? Double(accumulator) : nil
        default:
            if values.count == 1, let function = functions[name] {
                result = function(first)
            } else {
                guard values.count == 2 else { return nil }
                let second = values[1]
                switch name {
                case "round":
                    guard let digits = Int(exactly: second), (-308...308).contains(digits) else {
                        return nil
                    }
                    let factor = pow(10, second)
                    let scaled = first * factor
                    result = scaled.isFinite ? scaled.rounded() / factor : first
                case "log":
                    guard first > 0, second > 0, second != 1 else { return nil }
                    result = log(first) / log(second)
                case "atan2": result = atan2(first, second)
                case "pow": result = pow(first, second)
                case "root":
                    guard second != 0 else { return nil }
                    result =
                        first < 0 && second.truncatingRemainder(dividingBy: 2) != 0
                            && second.rounded() == second
                        ? -pow(-first, 1 / second) : pow(first, 1 / second)
                case "fmod": result = first.truncatingRemainder(dividingBy: second)
                default: return nil
                }
            }
        }
        return result.isFinite ? result : nil
    }

    private static func exactInteger(_ value: Double) -> Int64? {
        guard abs(value) < 9_007_199_254_740_992 else { return nil }
        return Int64(exactly: value)
    }
}

// MARK: - Formatter (Tinycast CalcFormatter, number subset)

private enum Formatter {
    private static let maxExactInteger = 9_007_199_254_740_992.0

    static func expression(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }

    static func copyText(_ value: Double) -> String {
        let v = value == 0 ? 0 : value
        if v.rounded() == v && abs(v) <= maxExactInteger {
            return String(Int64(v))
        }
        return String(format: "%.10g", v)
    }

    static func grouped(_ text: String) -> String {
        let bytes = text.utf8
        guard !bytes.contains(101), !bytes.contains(69) else { return text }
        let signCount = bytes.first == 45 ? 1 : 0
        let integer = bytes.prefix { $0 != 46 }
        guard integer.count - signCount > 3 else { return text }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + integer.count / 3)
        for (index, byte) in bytes.enumerated() {
            if index > signCount, index < integer.count, (integer.count - index) % 3 == 0 {
                output.append(44)
            }
            output.append(byte)
        }
        return String(bytes: output, encoding: .utf8) ?? text
    }
}

// MARK: - Tokenizer

private enum Tokenizer {
    /// `nil` on any character that can't be calculator input — "not a calculation".
    static func tokenize(_ input: String) -> [CalcToken]? {
        let chars = Array(input.unicodeScalars)
        var tokens: [CalcToken] = []
        tokens.reserveCapacity(chars.count / 2 + 1)
        var i = 0
        var depth = 0
        var functionDepth: Int?

        func isDigit(_ ch: Unicode.Scalar) -> Bool { (48...57).contains(ch.value) }

        while i < chars.count {
            let ch = chars[i]
            if ch.properties.isWhitespace {
                i += 1
                continue
            }

            if ch == "0", i + 2 < chars.count, let base = literalBase(chars[i + 1]) {
                let start = i + 2
                var end = start
                while end < chars.count, chars[end].isASCII,
                    Character(chars[end]).isHexDigit
                {
                    end += 1
                }
                if end > start,
                    let value = UInt64(
                        String(String.UnicodeScalarView(chars[start..<end])), radix: base.rawValue)
                {
                    tokens.append(.intLiteral(value, base: base))
                    i = end
                    continue
                }
            }

            if isDigit(ch) || (ch == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var text = ""
                var seenDot = false
                while i < chars.count {
                    let c = chars[i]
                    if isDigit(c) {
                        text.unicodeScalars.append(c)
                    } else if c == "," && functionDepth == nil && i + 1 < chars.count
                        && isDigit(chars[i + 1])
                    {
                        // Skip thousands separators outside function args.
                    } else if c == "." && !seenDot {
                        seenDot = true
                        text.unicodeScalars.append(c)
                    } else {
                        break
                    }
                    i += 1
                }
                var isShorthand = false
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var digits = i + 1
                    if digits < chars.count, chars[digits] == "+" || chars[digits] == "-" {
                        digits += 1
                    }
                    var end = digits
                    while end < chars.count, isDigit(chars[end]) { end += 1 }
                    if end > digits {
                        text += String(String.UnicodeScalarView(chars[i..<end]))
                        i = end
                        isShorthand = true
                    }
                }
                guard let value = Double(text), value.isFinite else { return nil }
                if i < chars.count, chars[i] == "k" || chars[i] == "K", isCompactSuffix(chars, i) {
                    let scaled = value * 1_000
                    guard scaled.isFinite else { return nil }
                    tokens.append(.compactNumber(scaled))
                    i += 1
                } else if isShorthand {
                    tokens.append(.compactNumber(value))
                } else {
                    tokens.append(.number(value))
                }
                continue
            }

            if ch == "x" || ch == "X", isMultiplicationX(chars, at: i, previous: tokens.last) {
                tokens.append(.op(.multiply))
                i += 1
                continue
            }

            if ch.properties.isAlphabetic || ch == "π" || ch == "τ" {
                let start = i
                while i < chars.count,
                    chars[i].properties.isAlphabetic || chars[i] == "π" || chars[i] == "τ"
                {
                    i += 1
                }
                let text = String(String.UnicodeScalarView(chars[start..<i])).lowercased()
                tokens.append(.ident(text))
                continue
            }

            if ch == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.op(.power))
                i += 2
                continue
            }

            if i + 1 < chars.count {
                let combined: CalcOp? =
                    switch (ch, chars[i + 1]) {
                    case ("=", "="): .equal
                    case ("!", "="): .notEqual
                    case ("<", "="): .lessEqual
                    case (">", "="): .greaterEqual
                    default: nil
                    }
                if let op = combined {
                    tokens.append(.op(op))
                    i += 2
                    continue
                }
            }

            if ch == "(" {
                if functionDepth == nil, case .ident(let name)? = tokens.last, CalcMath.isFunction(name) {
                    functionDepth = depth
                }
                depth += 1
            } else if ch == ")" {
                depth -= 1
                if functionDepth == depth { functionDepth = nil }
            }

            switch ch {
            case "+": tokens.append(.op(.add))
            case "-", "−": tokens.append(.op(.subtract))
            case "*", "×": tokens.append(.op(.multiply))
            case "/", "÷": tokens.append(.op(.divide))
            case "^": tokens.append(.op(.power))
            case "!": tokens.append(.op(.factorial))
            case "%": tokens.append(.op(.percent))
            case "(": tokens.append(.op(.open))
            case ")": tokens.append(.op(.close))
            case "<": tokens.append(.op(.less))
            case ">": tokens.append(.op(.greater))
            case "≤": tokens.append(.op(.lessEqual))
            case "≥": tokens.append(.op(.greaterEqual))
            case "≠": tokens.append(.op(.notEqual))
            case ",": tokens.append(.comma)
            case "=":
                guard i == chars.count - 1 else { return nil }
            default:
                return nil
            }
            i += 1
        }
        return tokens
    }

    private static func literalBase(_ prefix: Unicode.Scalar) -> NumberBase? {
        switch prefix {
        case "x", "X": return .hexadecimal
        case "b", "B": return .binary
        case "o", "O": return .octal
        default: return nil
        }
    }

    private static func isMultiplicationX(
        _ chars: [Unicode.Scalar], at index: Int, previous: CalcToken?
    ) -> Bool {
        guard let previous, endsOperand(previous) else { return false }
        let next = index + 1
        guard next < chars.count else { return false }
        let ch = chars[next]
        if ch.properties.isWhitespace { return true }
        switch ch {
        case "(", "0"..."9", ".": return true
        default: return ch.properties.isAlphabetic || ch == "π" || ch == "τ"
        }
    }

    private static func endsOperand(_ token: CalcToken) -> Bool {
        switch token {
        case .number, .compactNumber, .intLiteral: return true
        case .op(let op): return op == .close || op == .factorial || op == .percent
        case .ident(let name): return CalcMath.constants[name] != nil
        case .comma: return false
        }
    }

    private static func isCompactSuffix(_ chars: [Unicode.Scalar], _ index: Int) -> Bool {
        let next = index + 1
        if next >= chars.count { return true }
        let ch = chars[next]
        if ch.properties.isWhitespace { return true }
        switch ch {
        case "+", "-", "*", "/", "^", ")", "!", "%", ",", "=", "×", "÷", "−": return true
        default: return false
        }
    }
}

// MARK: - Parser (Pratt, scalar-only)

private struct Parser {
    /// Amount plus optional percent flag so `100 + 10%` → 110 and `10% of 50` → 5.
    private struct Value {
        var amount: Double
        var isPercent: Bool = false
        var isBoolean: Bool = false

        var effective: Double { isPercent ? amount / 100 : amount }
    }

    private var tokens: [CalcToken]
    private var position = 0
    private var operationCount = 0

    private static let unaryBindingPower = 25

    static func scalar(_ tokens: [CalcToken], requireOperation: Bool) -> Double? {
        var parser = Parser(tokens: tokens)
        guard let value = parser.parse() else { return nil }
        if requireOperation {
            guard parser.operationCount > 0 else { return nil }
        }
        // Booleans copy as 1/0; bare percent alone is not a result (`50%` needs a partner).
        if value.isPercent, parser.operationCount == 1 { return nil }
        return value.isBoolean ? value.amount : value.effective
    }

    private var current: CalcToken? {
        position < tokens.count ? tokens[position] : nil
    }

    private mutating func parse() -> Value? {
        guard let value = parseExpression(minBindingPower: 0), position == tokens.count,
            value.amount.isFinite
        else { return nil }
        return value
    }

    private mutating func parseExpression(minBindingPower: Int) -> Value? {
        guard var left = parseOperand(), left.amount.isFinite else { return nil }
        while true {
            guard let binary = peekBinary(), binary.bindingPower >= minBindingPower else {
                return left
            }
            if binary.consumesToken { position += 1 }
            operationCount += 1
            guard let right = parseExpression(minBindingPower: binary.rightBindingPower),
                let combined = apply(binary.op, left, right), combined.amount.isFinite
            else { return nil }
            left = combined
        }
    }

    private struct BinaryOp {
        let op: CalcOp
        let bindingPower: Int
        let rightBindingPower: Int
        let consumesToken: Bool
    }

    private func peekBinary() -> BinaryOp? {
        switch current {
        case .op(let op) where op.bindingPower != nil:
            let power = op.bindingPower ?? 0
            return BinaryOp(
                op: op,
                bindingPower: power,
                rightBindingPower: power + (op == .power ? 0 : 1),
                consumesToken: true
            )
        case .ident("mod"):
            return BinaryOp(op: .percent, bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        case .ident("power"):
            return BinaryOp(op: .power, bindingPower: 30, rightBindingPower: 30, consumesToken: true)
        case .ident("of"):
            return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        default:
            if case .op(.open) = current {
                return BinaryOp(
                    op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if case .ident(let name) = current,
                CalcMath.constants[name] != nil || CalcMath.isFunction(name)
            {
                return BinaryOp(
                    op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            return nil
        }
    }

    private func apply(_ op: CalcOp, _ left: Value, _ right: Value) -> Value? {
        guard !left.isBoolean, !right.isBoolean else { return nil }
        switch op {
        case .add, .subtract:
            let direction = op == .add ? 1.0 : -1.0
            if right.isPercent, !left.isPercent {
                return Value(amount: left.effective * (1 + direction * right.amount / 100))
            }
            guard !left.isPercent else { return nil }
            return Value(amount: left.effective + direction * right.effective)
        case .multiply:
            return Value(amount: left.effective * right.effective)
        case .divide:
            guard right.effective != 0 else { return nil }
            return Value(amount: left.effective / right.effective)
        case .power:
            guard !left.isPercent, !right.isPercent else { return nil }
            return Value(amount: pow(left.amount, right.amount))
        case .percent:
            // Binary `mod`
            guard !left.isPercent, !right.isPercent else { return nil }
            return Value(amount: left.amount.truncatingRemainder(dividingBy: right.amount))
        case .equal:
            return Value(amount: left.effective == right.effective ? 1 : 0, isBoolean: true)
        case .notEqual:
            return Value(amount: left.effective != right.effective ? 1 : 0, isBoolean: true)
        case .less:
            return Value(amount: left.effective < right.effective ? 1 : 0, isBoolean: true)
        case .greater:
            return Value(amount: left.effective > right.effective ? 1 : 0, isBoolean: true)
        case .lessEqual:
            return Value(amount: left.effective <= right.effective ? 1 : 0, isBoolean: true)
        case .greaterEqual:
            return Value(amount: left.effective >= right.effective ? 1 : 0, isBoolean: true)
        default:
            return nil
        }
    }

    private mutating func parseOperand() -> Value? {
        guard var value = parsePrefix() else { return nil }
        while true {
            switch current {
            case .op(.percent):
                guard !value.isPercent, !value.isBoolean else { return nil }
                value.isPercent = true
                position += 1
                operationCount += 1
            case .op(.factorial):
                guard !value.isPercent, !value.isBoolean,
                    let factorial = CalcMath.factorial(value.amount)
                else { return nil }
                value = Value(amount: factorial)
                position += 1
                operationCount += 1
            default:
                return value
            }
        }
    }

    private mutating func parsePrefix() -> Value? {
        switch current {
        case .number(let value), .compactNumber(let value):
            position += 1
            return Value(amount: value)
        case .intLiteral(let value, _):
            position += 1
            return Value(amount: Double(value))
        case .op(.subtract):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower),
                !value.isBoolean
            else { return nil }
            operationCount += 1
            return Value(amount: -value.effective)
        case .op(.add):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower),
                !value.isBoolean
            else { return nil }
            return value
        case .op(.open):
            return parseGrouped()
        case .ident(let name):
            if let constant = CalcMath.constants[name] {
                position += 1
                return Value(amount: constant)
            }
            if CalcMath.isFunction(name), position + 1 < tokens.count,
                tokens[position + 1] == .op(.open)
            {
                return parseFunction(name)
            }
            if let function = CalcMath.functions[name] {
                // Juxtaposition: `sqrt 9` / `sqrt9` after tokenize is `sqrt` + operand.
                position += 1
                guard let argument = parseOperand(), !argument.isBoolean else { return nil }
                operationCount += 1
                let result = function(argument.effective)
                guard result.isFinite else { return nil }
                return Value(amount: result)
            }
            return nil
        default:
            return nil
        }
    }

    private mutating func parseFunction(_ name: String) -> Value? {
        position += 2  // name + (
        var amounts: [Double] = []
        while true {
            guard let end = argumentEnd() else { return nil }
            let slice = Array(tokens[position..<end])
            var nested = Parser(tokens: slice)
            guard let value = nested.parse(), !value.isBoolean else { return nil }
            operationCount += nested.operationCount
            amounts.append(value.effective)
            position = end + 1
            if case .op(.close) = tokens[end] { break }
            // comma: continue
        }
        operationCount += 1
        guard let result = CalcMath.evaluate(name, amounts) else { return nil }
        return Value(amount: result)
    }

    private mutating func parseGrouped() -> Value? {
        guard let close = matchingParenthesis() else { return nil }
        position += 1
        let slice = Array(tokens[position..<close])
        var nested = Parser(tokens: slice)
        guard let value = nested.parse() else { return nil }
        operationCount += nested.operationCount
        position = close + 1
        return value
    }

    private func argumentEnd() -> Int? {
        var depth = 0
        for index in position..<tokens.count {
            switch tokens[index] {
            case .op(.open): depth += 1
            case .op(.close):
                if depth == 0 { return index }
                depth -= 1
            case .comma where depth == 0: return index
            default: break
            }
        }
        return nil
    }

    private func matchingParenthesis() -> Int? {
        guard case .op(.open) = current else { return nil }
        var depth = 0
        for index in position..<tokens.count {
            switch tokens[index] {
            case .op(.open): depth += 1
            case .op(.close):
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }
}
