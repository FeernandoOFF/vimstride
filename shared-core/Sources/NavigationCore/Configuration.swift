import Foundation

public struct ConfigurationError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public struct KeyChord: Equatable {
    public static let modifierOrder = ["command", "control", "option", "shift"]
    public static let sideModifiers = ["left_command", "right_command", "left_control", "right_control", "left_option", "right_option", "left_shift", "right_shift"]
    public let key: String
    public let modifiers: Set<String>
    public var isModifier: Bool { Self.modifierOrder.contains(key) || Self.sideModifiers.contains(key) }
    public var serialized: String { (Self.modifierOrder.filter { modifiers.contains($0) } + [key]).joined(separator: "+") }
    public init(_ value: String) throws {
        let aliases = ["cmd": "command", "ctrl": "control", "alt": "option", "esc": "escape", "enter": "return", "super": "command+control+shift", "hyper": "command+control+shift"]
        let tokens = value.lowercased().split(separator: "+", omittingEmptySubsequences: false).flatMap { token -> [String] in
            let name = token.trimmingCharacters(in: .whitespaces)
            return (aliases[name] ?? name).components(separatedBy: "+")
        }
        guard !tokens.contains(""), Set(tokens).count == tokens.count else { throw ConfigurationError("Invalid or duplicate key in '\(value)'") }
        let nonModifiers = tokens.filter { !Self.modifierOrder.contains($0) }
        if nonModifiers.isEmpty, let last = Self.modifierOrder.last(where: { tokens.contains($0) }) {
            key = last; modifiers = Set(tokens.filter { $0 != last }); return
        }
        let supported = Set(Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init) + ["space", "tab", "escape", "backspace", "return", "equal", "minus", "left", "right", "up", "down"] + Self.sideModifiers)
        guard nonModifiers.count == 1, let key = nonModifiers.first, supported.contains(key) else { throw ConfigurationError("Unsupported key chord '\(value)'") }
        self.key = key
        modifiers = Set(tokens.filter { Self.modifierOrder.contains($0) })
    }
}
public struct NavigationConfig: Equatable {
    public var hintLabelSize = 13
    public var clickSound = true
    public var soundVolume = 0.25
    public var pointerSpeed = 650.0
    public var requestAccessibilityOnStart = false
    // Kept for compatibility with old dotfiles; typed keystrokes are never logged.
    public var diagnostics = false
    public var bindings = Self.defaultBindings
    public init() {}
    public static let defaultBindings: [String: String] = [
        "free_mode": "command+control+shift", "move_left": "h", "move_down": "j", "move_up": "k", "move_right": "l",
        "fast_modifier": "right_shift", "precision_modifier": "right_control", "left_click": "space", "right_click": "r",
        "hint_mode": "command+control+shift+f", "focus_mode": "command+control+shift+v",
        "hint_cancel": "escape", "hint_backspace": "backspace", "hint_size_up": "equal", "hint_size_down": "minus",
        "hint_next": "tab", "hint_previous": "shift+tab", "hint_click": "return", "hint_focus": "option+return",
        "hint_right_click": "shift+return", "hint_command_click": "command+return",
        "scroll_mode": "command+control+shift+g", "scroll_next": "tab", "scroll_previous": "shift+tab",
        "scroll_left": "h", "scroll_down": "j", "scroll_up": "k", "scroll_right": "l",
        "scroll_half_down": "d", "scroll_half_up": "u", "scroll_top": "t", "scroll_bottom": "b", "scroll_cancel": "escape",
    ]
    public static let bindingOrder = ["free_mode", "hint_mode", "scroll_mode", "focus_mode", "move_left", "move_down", "move_up", "move_right", "left_click", "right_click", "fast_modifier", "precision_modifier", "hint_next", "hint_previous", "hint_click", "hint_focus", "hint_right_click", "hint_command_click", "hint_cancel", "hint_backspace", "hint_size_up", "hint_size_down", "scroll_next", "scroll_previous", "scroll_left", "scroll_down", "scroll_up", "scroll_right", "scroll_half_down", "scroll_half_up", "scroll_top", "scroll_bottom", "scroll_cancel"]
    public func validated() throws -> NavigationConfig {
        guard (9...33).contains(hintLabelSize) else { throw ConfigurationError("hint_label_size must be between 9 and 33") }
        guard soundVolume.isFinite, (0...1).contains(soundVolume) else { throw ConfigurationError("sound_volume must be between 0 and 1") }
        guard pointerSpeed.isFinite, (50...3000).contains(pointerSpeed) else { throw ConfigurationError("pointer_speed must be between 50 and 3000") }
        var result = self
        for action in Self.bindingOrder {
            guard let value = bindings[action] else { throw ConfigurationError("Missing binding \(action)") }
            result.bindings[action] = try KeyChord(value).serialized
        }
        for action in ["free_mode", "fast_modifier", "precision_modifier"] {
            guard try KeyChord(result.bindings[action]!).isModifier else { throw ConfigurationError("\(action) must use modifier keys") }
        }
        for action in ["fast_modifier", "precision_modifier"] {
            guard try KeyChord(result.bindings[action]!).modifiers.isEmpty else { throw ConfigurationError("\(action) must be a single modifier") }
        }
        guard result.bindings["fast_modifier"] != result.bindings["precision_modifier"] else { throw ConfigurationError("fast_modifier and precision_modifier must differ") }
        for action in Self.bindingOrder where !["free_mode", "fast_modifier", "precision_modifier", "left_click", "right_click"].contains(action) {
            guard try !KeyChord(result.bindings[action]!).isModifier else { throw ConfigurationError("\(action) must include a non-modifier key") }
        }
        let free = try KeyChord(result.bindings["free_mode"]!)
        let activation = free.modifiers.union([free.key]).map { $0.components(separatedBy: "_").last! }
        for action in ["move_left", "move_down", "move_up", "move_right", "left_click", "right_click"] {
            let chord = try KeyChord(result.bindings[action]!)
            guard chord.modifiers.allSatisfy({ !activation.contains($0) }) else { throw ConfigurationError("\(action) is relative to free_mode; omit activation modifiers") }
        }
        for group in [["hint_mode", "scroll_mode", "focus_mode"], ["move_left", "move_down", "move_up", "move_right", "left_click", "right_click"], Self.bindingOrder.filter { $0.hasPrefix("hint_") && $0 != "hint_mode" }, Self.bindingOrder.filter { $0.hasPrefix("scroll_") && $0 != "scroll_mode" }] {
            var seen = Set<String>()
            for action in group {
                guard seen.insert(result.bindings[action]!).inserted else { throw ConfigurationError("Duplicate shortcut for \(action)") }
            }
        }
        return result
    }
    public static func parse(_ text: String, source: String = "config.toml") throws -> NavigationConfig {
        var config = NavigationConfig(), section = "", seen = Set<String>()
        for (index, original) in text.components(separatedBy: .newlines).enumerated() {
            do {
                var quoted = false
                var line = ""
                for character in original { if character == "\"" { quoted.toggle() }; if character == "#" && !quoted { break }; line.append(character) }
                line = line.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if line.hasPrefix("[") {
                    guard line == "[general]" || line == "[bindings]" else { throw ConfigurationError("Unknown or malformed table") }
                    section = String(line.dropFirst().dropLast()); continue
                }
                guard !section.isEmpty, let separator = line.firstIndex(of: "=") else { throw ConfigurationError("Expected key = value inside [general] or [bindings]") }
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                guard seen.insert("\(section).\(key)").inserted else { throw ConfigurationError("Duplicate key \(key)") }
                if section == "bindings" {
                    guard defaultBindings[key] != nil else { throw ConfigurationError("Unknown binding '\(key)'") }
                    guard value.count >= 2, value.first == "\"", value.last == "\"", !value.dropFirst().dropLast().contains("\""), !value.contains("\\") else { throw ConfigurationError("Bindings must be quoted strings without escapes") }
                    config.bindings[key] = try KeyChord(String(value.dropFirst().dropLast())).serialized
                } else {
                    func boolean() throws -> Bool { guard value == "true" || value == "false" else { throw ConfigurationError("Expected true or false") }; return value == "true" }
                    switch key {
                    case "hint_label_size": guard let number = Int(value), (9...33).contains(number) else { throw ConfigurationError("hint_label_size must be between 9 and 33") }; config.hintLabelSize = number
                    case "click_sound": config.clickSound = try boolean()
                    case "sound_volume": guard let number = Double(value), number.isFinite, (0...1).contains(number) else { throw ConfigurationError("sound_volume must be between 0 and 1") }; config.soundVolume = number
                    case "pointer_speed": guard let number = Double(value), number.isFinite, (50...3000).contains(number) else { throw ConfigurationError("pointer_speed must be between 50 and 3000") }; config.pointerSpeed = number
                    case "diagnostics": config.diagnostics = try boolean()
                    case "request_accessibility_on_start": config.requestAccessibilityOnStart = try boolean()
                    default: throw ConfigurationError("Unknown general setting '\(key)'")
                    }
                }
            } catch { throw ConfigurationError("\(source):\(index + 1): \(error.localizedDescription)") }
        }
        return try config.validated()
    }
    public var toml: String {
        """
        # Super = your Karabiner Caps Lock mapping: Command + Control + Shift.
        [general]
        hint_label_size = \(hintLabelSize)
        click_sound = \(clickSound)
        sound_volume = \(soundVolume)
        pointer_speed = \(pointerSpeed)
        diagnostics = \(diagnostics)
        request_accessibility_on_start = \(requestAccessibilityOnStart)

        [bindings]
        """ + "\n" + Self.bindingOrder.map { "\($0) = \"\(bindings[$0]!)\"" }.joined(separator: "\n") + "\n"
    }
    public static func configURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        for key in ["VIMSTRIDE_CONFIG", "KEYBOARD_NAV_CONFIG"] {
            if let path = environment[key], !path.isEmpty { return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath) }
        }
        let root = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.config"
        let preferred = URL(fileURLWithPath: root).appendingPathComponent("vimstride/config.toml")
        let legacy = URL(fileURLWithPath: root).appendingPathComponent("keyboard-navigation/config.toml")
        if !FileManager.default.fileExists(atPath: preferred.path), FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return preferred
    }
}
