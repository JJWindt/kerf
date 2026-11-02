import Foundation

/// JSON that keeps its key order and number spelling, so editing someone's settings file changes
/// only what we touch. Prints like `JSON.stringify(value, null, 2)`, as Claude Code and Codex write.
public indirect enum OrderedJSON: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public var key: String
        public var value: OrderedJSON

        public init(_ key: String, _ value: OrderedJSON) {
            self.key = key
            self.value = value
        }
    }

    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([OrderedJSON])
    case object([Member])

    public subscript(key: String) -> OrderedJSON? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(Member(key, newValue))
            }
            self = .object(members)
        }
    }

    public var arrayValue: [OrderedJSON]? {
        if case .array(let value) = self { value } else { nil }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    // MARK: Printing

    public func printed(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent)
        let inner = String(repeating: " ", count: indent + 2)
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let literal): return literal
        case .string(let value): return Self.quote(value)
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            return "[\n" + items.map { inner + $0.printed(indent: indent + 2) }.joined(separator: ",\n") + "\n\(pad)]"
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            return "{\n" + members.map { inner + Self.quote($0.key) + ": " + $0.value.printed(indent: indent + 2) }
                .joined(separator: ",\n") + "\n\(pad)}"
        }
    }

    static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{C}": out += "\\f"
            case let s where s.value < 0x20: out += String(format: "\\u%04x", s.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    // MARK: Parsing

    public enum ParseError: Error {
        case invalid(Int)
    }

    public static func parse(_ text: String) throws -> OrderedJSON {
        var parser = Parser(bytes: Array(text.utf8))
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw ParseError.invalid(parser.index) }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
        }

        mutating func value() throws -> OrderedJSON {
            skipWhitespace()
            guard index < bytes.count else { throw ParseError.invalid(index) }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let token = Array(word.utf8)
            guard bytes.count - index >= token.count, Array(bytes[index..<index + token.count]) == token else { throw ParseError.invalid(index) }
            index += token.count
        }

        mutating func number() throws -> OrderedJSON {
            let start = index
            while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
            guard index > start else { throw ParseError.invalid(index) }
            return .number(String(decoding: bytes[start..<index], as: UTF8.self))
        }

        mutating func string() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var raw: [UInt8] = []
            func flush() {
                scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
                raw.removeAll()
            }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == UInt8(ascii: "\"") {
                    flush()
                    return String(scalars)
                }
                guard byte == UInt8(ascii: "\\") else {
                    raw.append(byte)
                    continue
                }
                flush()
                guard index < bytes.count else { break }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "b"): scalars.append("\u{8}")
                case UInt8(ascii: "f"): scalars.append("\u{C}")
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                        index += 2
                        let low = try hex4()
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    if let scalar = Unicode.Scalar(code) { scalars.append(scalar) }
                default: scalars.append(Unicode.Scalar(escape))
                }
            }
            throw ParseError.invalid(index)
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count, let code = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
                throw ParseError.invalid(index)
            }
            index += 4
            return code
        }

        mutating func array() throws -> OrderedJSON {
            index += 1
            var items: [OrderedJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try value())
                skipWhitespace()
                guard index < bytes.count else { throw ParseError.invalid(index) }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw ParseError.invalid(index)
            }
        }

        mutating func object() throws -> OrderedJSON {
            index += 1
            var members: [Member] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw ParseError.invalid(index) }
                let key = try string()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ParseError.invalid(index) }
                index += 1
                members.append(Member(key, try value()))
                skipWhitespace()
                guard index < bytes.count else { throw ParseError.invalid(index) }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw ParseError.invalid(index)
            }
        }
    }
}
