import Foundation

/// Settings and dotfiles share one source of truth. The last observed contents
/// include malformed files, so an explicit Save can repair them without losing
/// protection against intervening external edits.
public final class ConfigurationFile {
    public let url: URL
    private var observedText: String?
    private var hasLoaded = false
    public init(url: URL) { self.url = url }
    public func load() throws -> NavigationConfig {
        let text = try read()
        observedText = text
        hasLoaded = true
        return try text.map { try NavigationConfig.parse($0, source: url.path) } ?? NavigationConfig()
    }
    @discardableResult public func save(_ draft: NavigationConfig) throws -> NavigationConfig {
        let config = try draft.validated()
        guard hasLoaded, try read() == observedText else {
            throw ConfigurationError("The TOML file changed outside the app. Reload it before saving.")
        }
        let destination = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.toml.write(to: destination, atomically: true, encoding: .utf8)
        observedText = config.toml
        return config
    }
    private func read() throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
