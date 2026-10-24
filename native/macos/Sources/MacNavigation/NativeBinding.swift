import AppKit
import ApplicationServices
import NavigationCore

enum BindingTrigger {
    case key(CGKeyCode)
    case genericModifier(CGEventFlags)
}

struct NativeBinding {
    let trigger: BindingTrigger
    let modifiers: CGEventFlags

    func matches(keyCode: CGKeyCode, flags: CGEventFlags, exactModifiers: Bool = true) -> Bool {
        guard case let .key(expectedKeyCode) = trigger, expectedKeyCode == keyCode else { return false }
        let relevant = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        return exactModifiers ? relevant == modifiers : relevant.contains(modifiers)
    }

    func usesKeyCode(_ keyCode: CGKeyCode) -> Bool {
        guard case let .key(expectedKeyCode) = trigger else { return false }
        return expectedKeyCode == keyCode
    }

    func handlesModifierEvent(keyCode: CGKeyCode) -> Bool {
        switch trigger {
        case let .key(expectedKeyCode): return expectedKeyCode == keyCode && Self.sideModifierBits[keyCode] != nil
        case .genericModifier:
            guard let changedFlag = Self.sideModifierGenericFlags[keyCode] else { return false }
            return !activationModifierFlags.intersection(changedFlag).isEmpty
        }
    }

    func isModifierPressed(flags: CGEventFlags) -> Bool {
        switch trigger {
        case let .key(keyCode):
            guard let bit = Self.sideModifierBits[keyCode] else { return false }
            return flags.rawValue & bit != 0 && flags.contains(modifiers)
        case .genericModifier:
            return flags.contains(activationModifierFlags)
        }
    }

    var activationModifierFlags: CGEventFlags {
        var flags = modifiers
        switch trigger {
        case let .genericModifier(flag): flags.insert(flag)
        case let .key(keyCode):
            if let flag = Self.sideModifierGenericFlags[keyCode] { flags.insert(flag) }
        }
        return flags
    }

    static func parse(_ chord: String) -> NativeBinding? {
        guard let parsed = try? KeyChord(chord) else { return nil }
        let tokens = parsed.serialized.split(separator: "+").map(String.init)
        guard !tokens.isEmpty else { return nil }
        if tokens.allSatisfy({ genericModifierFlags[$0] != nil }) {
            guard Set(tokens).count == tokens.count, let trigger = genericModifierFlags[tokens.last!] else { return nil }
            var modifiers: CGEventFlags = []
            for token in tokens.dropLast() { modifiers.insert(genericModifierFlags[token]!) }
            return NativeBinding(trigger: .genericModifier(trigger), modifiers: modifiers)
        }
        var modifiers: CGEventFlags = []
        var keyCode: CGKeyCode?
        for token in tokens {
            if let modifier = genericModifierFlags[token] {
                modifiers.insert(modifier)
            } else if keyCode == nil, let resolved = keyCodes[token] {
                keyCode = resolved
            } else {
                return nil
            }
        }
        guard let keyCode else { return nil }
        return NativeBinding(trigger: .key(keyCode), modifiers: modifiers)
    }

    private static let genericModifierFlags: [String: CGEventFlags] = [
        "command": .maskCommand, "control": .maskControl, "option": .maskAlternate, "shift": .maskShift,
    ]
    private static let sideModifierBits: [CGKeyCode: UInt64] = [
        54: 0x10, 55: 0x08, 56: 0x02, 60: 0x04,
        58: 0x20, 61: 0x40, 59: 0x01, 62: 0x2000,
    ]
    private static let sideModifierGenericFlags: [CGKeyCode: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand, 56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate, 59: .maskControl, 62: .maskControl,
    ]
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28,
        "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46, "tab": 48, "space": 49, "backspace": 51,
        "escape": 53, "right_command": 54, "left_command": 55, "left_shift": 56,
        "left_option": 58, "left_control": 59, "right_shift": 60, "right_option": 61,
        "right_control": 62, "return": 36, "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
