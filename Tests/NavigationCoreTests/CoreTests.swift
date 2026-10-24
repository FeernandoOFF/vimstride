import XCTest
@testable import NavigationCore

final class CoreTests: XCTestCase {
    func target(_ id: Int, x: Double = 0, y: Double = 0, width: Double = 20, height: Double = 20) -> Target { Target(id: id, x: x, y: y, width: width, height: height) }
    func testInactiveDirectionsPassThrough() {
        var state = MovementState()
        XCTAssertFalse(state.direction(.left, pressed: true)); XCTAssertEqual(state.vector, .zero)
    }
    func testReleaseClearsAllHeldState() {
        var state = MovementState(); state.activate(true); state.direction(.right, pressed: true); state.fast = true; state.precise = true
        state.activate(false); XCTAssertEqual(state, MovementState())
    }
    func testNormalizedDiagonalsAndOpposingDirections() {
        var state = MovementState(); state.activate(true); state.direction(.right, pressed: true); state.direction(.down, pressed: true)
        XCTAssertEqual(state.vector.x, 1 / sqrt(2), accuracy: 0.000001)
        state.direction(.left, pressed: true); XCTAssertEqual(state.vector, Vector(0, 1))
    }
    func testSpeedAndAccelerationAndBoundedElapsedTime() {
        var state = MovementState(); state.activate(true); state.direction(.right, pressed: true)
        XCTAssertEqual(state.displacement(heldSeconds: 0, elapsedSeconds: 0.01, speed: 100).x, 1)
        XCTAssertEqual(state.displacement(heldSeconds: 1, elapsedSeconds: 0.01, speed: 100).x, 2)
        state.fast = true; XCTAssertEqual(state.speedMultiplier, 3)
        state.precise = true; XCTAssertEqual(state.speedMultiplier, 0.75)
        XCTAssertEqual(state.displacement(heldSeconds: 1, elapsedSeconds: 100, speed: 100).x, 7.5)
        XCTAssertEqual(state.displacement(heldSeconds: 1, elapsedSeconds: -.infinity), .zero)
    }
    func testHintCapacityBoundaries() {
        for count in [1, 9, 10, 81, 82, 500] {
            let labels = HintSession(targets: (0..<count).map { target($0) }).labels.map(\.text)
            XCTAssertEqual(Set(labels).count, count); XCTAssertEqual(Set(labels.map(\.count)).count, 1)
            XCTAssertTrue(labels.allSatisfy { $0.allSatisfy { HintSession.alphabet.contains($0) } })
        }
    }
    func testSpatialSortKeepsNegativeCoordinates() {
        XCTAssertEqual(HintSession(targets: [target(1, x: 40, y: 20), target(2, x: -100, y: 20), target(3, y: -30)]).labels.map(\.target.id), [3, 2, 1])
    }
    func testOnlyCompleteHintsSelect() {
        var session = HintSession(targets: (0..<10).map { target($0) })
        XCTAssertNil(session.type("s").selected); XCTAssertEqual(session.visible.count, 1)
        XCTAssertEqual(session.type("a").selected, 9)
    }
    func testInvalidPrefixAndBackspace() {
        var session = HintSession(targets: (0..<10).map { target($0) })
        _ = session.type("a"); XCTAssertFalse(session.type("z").accepted); XCTAssertEqual(session.prefix, "A")
        session.backspace(); XCTAssertEqual(session.visible.count, 10)
    }
    func testMalformedAndExcessiveTargets() {
        XCTAssertTrue(HintSession(targets: []).labels.isEmpty)
        XCTAssertEqual(HintSession(targets: [target(1), target(1), target(2, width: 0), target(3, x: .nan)]).labels.count, 1)
        XCTAssertEqual(HintSession(targets: (0..<600).map { target($0) }).labels.count, 500)
    }
    func testHintFocusCyclesWithinVisibleTargets() {
        var session = HintSession(targets: (0..<10).map { target($0) })
        XCTAssertEqual(session.focusedID, 0); session.cycle(backward: true); XCTAssertEqual(session.focusedID, 9)
        session.cycle(); XCTAssertEqual(session.focusedID, 0)
        _ = session.type("s"); session.cycle(); XCTAssertEqual(session.focusedID, 9)
    }
    func testScrollSelectionAndWraparound() {
        var session = ScrollSession(targets: [target(2, x: 300, y: 20, width: 200, height: 300), target(1, x: 10, y: 20, width: 200, height: 300), target(3, x: 10, y: 400, width: 400, height: 200)], preferredID: 2)!
        XCTAssertEqual(session.selected.id, 2); session.cycle(); XCTAssertEqual(session.selected.id, 3)
        session.cycle(); XCTAssertEqual(session.selected.id, 1); session.cycle(backward: true); XCTAssertEqual(session.selected.id, 3)
        session.select(index: 999); XCTAssertEqual(session.selected.id, 3)
    }
    func testScrollDistancesAndDashAndEasing() {
        let session = ScrollSession(targets: [target(1, width: 800, height: 600)])!
        XCTAssertEqual(session.delta(.down), Vector(0, 72)); XCTAssertEqual(session.delta(.up, halfPage: true), Vector(0, -300))
        XCTAssertEqual(session.delta(.right), Vector(96, 0)); XCTAssertEqual(session.delta(.left, halfPage: true), Vector(-400, 0))
        XCTAssertEqual(session.delta(.down, dash: true), Vector(0, 216))
        XCTAssertEqual(ScrollSession.easedProgress(-1), 0); XCTAssertEqual(ScrollSession.easedProgress(0.5), 0.5); XCTAssertEqual(ScrollSession.easedProgress(2), 1)
        XCTAssertNil(ScrollSession(targets: [target(1, width: 20, height: 20)]))
    }
    func testChordAliasesAndOrder() throws {
        XCTAssertEqual(try KeyChord("shift+CTRL+cmd+k").serialized, "command+control+shift+k")
        XCTAssertEqual(try KeyChord("super+f").serialized, "command+control+shift+f")
        XCTAssertTrue(try KeyChord("left_option").isModifier)
        XCTAssertThrowsError(try KeyChord("h+j")); XCTAssertThrowsError(try KeyChord("ctrl+control+h"))
        XCTAssertThrowsError(try KeyChord("shift+not_a_key")); XCTAssertThrowsError(try KeyChord("+h"))
    }
    func testDefaultConfigRoundtrip() throws {
        XCTAssertEqual(try NavigationConfig.parse(NavigationConfig().toml), NavigationConfig())
        XCTAssertEqual(NavigationConfig().bindings["hint_mode"], "command+control+shift+f")
    }
    func testPartialAndLegacyConfiguration() throws {
        let config = try NavigationConfig.parse("[general]\nhint_label_size = 21\ndiagnostics = true\n[bindings]\nfree_mode = \"right_option\" # comment\nhint_mode = \"command+shift+f\"")
        XCTAssertEqual(config.hintLabelSize, 21); XCTAssertTrue(config.diagnostics)
        XCTAssertEqual(config.bindings["free_mode"], "right_option"); XCTAssertEqual(config.bindings["move_left"], "h")
    }
    func testMalformedConfigReportsLine() {
        for source in ["[general]\nunknown = true", "[bindings]\nmove_left = \"not_a_key\"", "[general]\nclick_sound = yes", "[general]\nsound_volume = nan", "[general]\nhint_label_size = 100"] {
            XCTAssertThrowsError(try NavigationConfig.parse(source)) { XCTAssertTrue($0.localizedDescription.contains("config.toml:2")) }
        }
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nmove_left = \"h\"\nmove_left = \"j\""))
    }
    func testConfigRejectsConflictsAndNonModifierActivation() {
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nfree_mode = \"f\""))
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nhint_mode = \"super+g\""))
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nmove_left = \"j\""))
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nleft_click = \"super+space\""))
    }
    func testUnsupportedModifierOnlyCommandsFailClearly() {
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nhint_mode = \"right_option\""))
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nmove_left = \"left_shift\""))
        XCTAssertThrowsError(try NavigationConfig.parse("[bindings]\nfast_modifier = \"right_control\""))
    }
    func testConfigPathsHonorOverrides() {
        XCTAssertEqual(NavigationConfig.configURL(environment: ["KEYBOARD_NAV_CONFIG": "/tmp/custom.toml"]).path, "/tmp/custom.toml")
        XCTAssertEqual(NavigationConfig.configURL(environment: ["VIMSTRIDE_CONFIG": "/tmp/vimstride.toml", "KEYBOARD_NAV_CONFIG": "/tmp/old.toml"]).path, "/tmp/vimstride.toml")
        XCTAssertEqual(NavigationConfig.configURL(environment: ["XDG_CONFIG_HOME": "/tmp/settings"]).path, "/tmp/settings/vimstride/config.toml")
    }
}
