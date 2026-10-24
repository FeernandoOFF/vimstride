import XCTest
@testable import NavigationCore

final class ConfigurationFileTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testMissingFileUsesDefaultsAndSaveCreatesIt() throws {
        let url = directory.appendingPathComponent("nested/config.toml")
        let file = ConfigurationFile(url: url)
        XCTAssertEqual(try file.load(), NavigationConfig())
        var changed = NavigationConfig(); changed.hintLabelSize = 21
        try file.save(changed)
        XCTAssertEqual(try ConfigurationFile(url: url).load(), changed)
    }
    func testExternalEditCannotBeOverwrittenWithoutReload() throws {
        let url = directory.appendingPathComponent("config.toml")
        let file = ConfigurationFile(url: url)
        _ = try file.load()
        let external = "[general]\nhint_label_size = 25\n"
        try external.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try file.save(NavigationConfig()))
        XCTAssertEqual(try String(contentsOf: url), external)
        XCTAssertEqual(try file.load().hintLabelSize, 25)
        try file.save(NavigationConfig())
        XCTAssertEqual(try file.load(), NavigationConfig())
    }
    func testMalformedConfigCanBeRepairedByExplicitSave() throws {
        let url = directory.appendingPathComponent("config.toml")
        try "[general]\ninvalid = true\n".write(to: url, atomically: true, encoding: .utf8)
        let file = ConfigurationFile(url: url)
        XCTAssertThrowsError(try file.load())
        try file.save(NavigationConfig())
        XCTAssertEqual(try file.load(), NavigationConfig())
    }
    func testRepairDoesNotOverwriteANewerExternalEdit() throws {
        let url = directory.appendingPathComponent("config.toml")
        try "invalid".write(to: url, atomically: true, encoding: .utf8)
        let file = ConfigurationFile(url: url)
        XCTAssertThrowsError(try file.load())
        try "changed".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try file.save(NavigationConfig()))
        XCTAssertEqual(try String(contentsOf: url), "changed")
    }
    func testSavingPreservesDotfileSymlink() throws {
        let target = directory.appendingPathComponent("dotfiles/navigation.toml")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try NavigationConfig().toml.write(to: target, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let file = ConfigurationFile(url: link)
        var config = try file.load(); config.clickSound = false
        try file.save(config)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        XCTAssertFalse(try ConfigurationFile(url: target).load().clickSound)
    }
    func testRenamedAppReusesLegacyConfigUnlessNewConfigExists() throws {
        let legacy = directory.appendingPathComponent("keyboard-navigation/config.toml")
        let preferred = directory.appendingPathComponent("vimstride/config.toml")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try NavigationConfig().toml.write(to: legacy, atomically: true, encoding: .utf8)
        let environment = ["XDG_CONFIG_HOME": directory.path]
        XCTAssertEqual(NavigationConfig.configURL(environment: environment), legacy)
        try FileManager.default.createDirectory(at: preferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        try NavigationConfig().toml.write(to: preferred, atomically: true, encoding: .utf8)
        XCTAssertEqual(NavigationConfig.configURL(environment: environment), preferred)
    }

}
