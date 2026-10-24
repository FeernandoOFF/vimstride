import Foundation

public struct Target: Equatable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(id: Int, x: Double, y: Double, width: Double, height: Double) {
        self.id = id; self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var valid: Bool { id >= 0 && [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}
public struct HintLabel: Equatable {
    public let target: Target
    public let text: String
}
public struct HintSession {
    public static let alphabet = Array("ASDFGHJKL")
    public private(set) var labels: [HintLabel]
    public private(set) var prefix = ""
    public private(set) var focusedID: Int?
    public var visible: [HintLabel] { labels.filter { $0.text.hasPrefix(prefix) } }
    public init(targets: [Target]) {
        var seen = Set<Int>()
        let sorted = targets.filter { $0.valid && seen.insert($0.id).inserted }.sorted {
            if $0.y != $1.y { return $0.y < $1.y }
            if $0.x != $1.x { return $0.x < $1.x }
            return $0.id < $1.id
        }.prefix(500)
        var length = 1, capacity = Self.alphabet.count
        while capacity < sorted.count { length += 1; capacity *= Self.alphabet.count }
        labels = sorted.enumerated().map { index, target in
            var value = index
            var text = Array(repeating: Self.alphabet[0], count: length)
            for position in (0..<length).reversed() {
                text[position] = Self.alphabet[value % Self.alphabet.count]
                value /= Self.alphabet.count
            }
            return HintLabel(target: target, text: String(text))
        }
        focusedID = labels.first?.target.id
    }
    public mutating func type(_ character: Character) -> (accepted: Bool, selected: Int?) {
        let next = prefix + String(character).uppercased()
        let matches = labels.filter { $0.text.hasPrefix(next) }
        guard !matches.isEmpty else { return (false, nil) }
        prefix = next
        focusedID = matches.first?.target.id
        return (true, matches.count == 1 && matches[0].text == next ? matches[0].target.id : nil)
    }
    public mutating func backspace() { prefix = String(prefix.dropLast()); focusedID = visible.first?.target.id }
    public mutating func cycle(backward: Bool = false) {
        let candidates = visible
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex { $0.target.id == focusedID } ?? 0
        focusedID = candidates[(index + (backward ? candidates.count - 1 : 1)) % candidates.count].target.id
    }
}
public struct ScrollSession {
    public let targets: [Target]
    public private(set) var selectedIndex: Int
    public var selected: Target { targets[selectedIndex] }
    public init?(targets: [Target], preferredID: Int? = nil) {
        var seen = Set<Int>()
        self.targets = Array(targets.filter { $0.valid && $0.width >= 24 && $0.height >= 24 && seen.insert($0.id).inserted }.sorted {
            if $0.y != $1.y { return $0.y < $1.y }
            if $0.x != $1.x { return $0.x < $1.x }
            return $0.id < $1.id
        }.prefix(64))
        guard !self.targets.isEmpty else { return nil }
        selectedIndex = self.targets.firstIndex { $0.id == preferredID } ?? 0
    }
    public mutating func cycle(backward: Bool = false) { selectedIndex = (selectedIndex + (backward ? targets.count - 1 : 1)) % targets.count }
    public mutating func select(index: Int) { if targets.indices.contains(index) { selectedIndex = index } }
    public func delta(_ direction: Direction, halfPage: Bool = false, dash: Bool = false) -> Vector {
        let length = direction == .left || direction == .right ? selected.width : selected.height
        let amount = halfPage ? length * 0.5 : min(100, max(48, length * 0.12)) * (dash ? 3 : 1)
        switch direction {
        case .left: return Vector(-amount, 0)
        case .right: return Vector(amount, 0)
        case .up: return Vector(0, -amount)
        case .down: return Vector(0, amount)
        }
    }
    public static func easedProgress(_ progress: Double) -> Double {
        let t = min(1, max(0, progress)); return t * t * (3 - 2 * t)
    }
}
