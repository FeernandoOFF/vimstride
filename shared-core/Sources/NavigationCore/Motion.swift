import Foundation

public enum Direction: String, CaseIterable { case left, down, up, right }
public struct Vector: Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double = 0, _ y: Double = 0) { self.x = x; self.y = y }
    public static let zero = Vector()
}

public struct MovementState: Equatable {
    public private(set) var active = false
    public private(set) var directions = Set<Direction>()
    public var fast = false
    public var precise = false
    public init() {}
    public mutating func activate(_ pressed: Bool) {
        if pressed { active = true } else { self = MovementState() }
    }
    @discardableResult public mutating func direction(_ direction: Direction, pressed: Bool) -> Bool {
        guard active else { return false }
        if pressed { directions.insert(direction) } else { directions.remove(direction) }
        return true
    }
    public var vector: Vector {
        guard active else { return .zero }
        let x = (directions.contains(.right) ? 1.0 : 0) - (directions.contains(.left) ? 1.0 : 0)
        let y = (directions.contains(.down) ? 1.0 : 0) - (directions.contains(.up) ? 1.0 : 0)
        let magnitude = hypot(x, y)
        return magnitude == 0 ? .zero : Vector(x / magnitude, y / magnitude)
    }
    public var speedMultiplier: Double { (fast ? 3 : 1) * (precise ? 0.25 : 1) }
    public func displacement(heldSeconds: Double, elapsedSeconds: Double, speed: Double = 650) -> Vector {
        guard active, elapsedSeconds > 0, elapsedSeconds.isFinite, speed.isFinite else { return .zero }
        let acceleration = 1 + min(1, max(0, (heldSeconds - 0.25) / 0.75))
        let distance = speed * speedMultiplier * acceleration * min(elapsedSeconds, 0.05)
        return Vector(vector.x * distance, vector.y * distance)
    }
}
