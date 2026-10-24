# Repository instructions

## Architecture

- This project is now entirely Swift; do not reintroduce Kotlin, Gradle, a JVM or a helper-process protocol.
- Keep mode state, geometry, keybinding interpretation, hint generation, and motion calculation in `shared-core/Sources/NavigationCore`.
- Keep operating-system handles and APIs behind the `MacNavigation` platform adapter. Never expose native accessibility handles from an adapter.
- Keep the native app as a single background process with a menu bar Settings entry and Spotlight launch support.
- Free mode is momentary: releasing its activation key must clear all held movement state immediately.

## Safety and privacy

- Capture only the input required by the currently active mode.
- Never persist or transmit keystrokes, accessibility labels, screen content, or application content.
- A native input hook must always be released during normal shutdown and recover from the operating system disabling it.
- Do not change Karabiner configuration without explicit authorization.

## Verification

- Add pure Swift tests for state machines and algorithms.
- Run `swift test` and `bash scripts/build-app.sh` before claiming macOS build support.
- Verify that ordinary HJKL input is untouched while free mode is inactive.
- Distinguish compiled/in-memory test coverage from live app verification with Accessibility permission.
