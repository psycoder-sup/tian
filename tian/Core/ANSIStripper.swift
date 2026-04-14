import Foundation

struct ANSIStripper {
    private(set) var state = State.normal

    enum State {
        case normal
        case escape
        case escapeIntermediate
        case csi
        case osc
        case oscEscape
    }

    mutating func strip(_ input: String) -> String {
        var result = String()
        result.reserveCapacity(input.count)

        for char in input {
            switch state {
            case .normal:
                if char == "\u{1B}" {
                    state = .escape
                } else if char == "\u{9B}" {
                    state = .csi
                } else if char.asciiValue.map({ $0 < 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 }) == true {
                    // Strip control chars except newline, carriage return, tab
                } else {
                    result.append(char)
                }

            case .escape:
                switch char {
                case "[":
                    state = .csi
                case "]":
                    state = .osc
                case "(", ")", "*", "+", "#":
                    state = .escapeIntermediate
                default:
                    state = .normal
                }

            case .escapeIntermediate:
                state = .normal

            case .csi:
                if char.asciiValue.map({ $0 >= 0x40 && $0 <= 0x7E }) == true {
                    state = .normal
                }

            case .osc:
                if char == "\u{07}" {
                    state = .normal
                } else if char == "\u{1B}" {
                    state = .oscEscape
                }

            case .oscEscape:
                if char == "\\" {
                    state = .normal
                } else {
                    state = .osc
                }
            }
        }

        return result
    }
}
