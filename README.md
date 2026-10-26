# Vimstride

Vim-style navigation for your Mac.

A native Swift macOS menu bar app for navigating with your keyboard. Launch **Vimstride** from Spotlight or Applications. No Java, Gradle, terminal session, or helper process is required at runtime.

## Install

Requires macOS 13 or newer. Building requires Xcode command-line tools with Swift 5.9 or newer.

```sh
git clone https://github.com/feernandooff/vimstride.git
cd vimstride
swift test
bash scripts/install-app.sh
open "$HOME/Applications/Vimstride.app"
```

The installer creates `~/Applications/Vimstride.app` and registers it with Launch Services. `VIMSTRIDE_APPLICATIONS_DIR` (or the legacy `KEYBOARD_NAV_APPLICATIONS_DIR`) overrides that folder. Existing app installations are backed up. When an older Kotlin installation has the matching user LaunchAgent, the installer disables and stops that legacy service while preserving its plist and installation for rollback. This avoids two input hooks competing for the same shortcuts.

Enable the app in **System Settings → Privacy & Security → Accessibility**; its menu bar Settings window includes a button to open that page. Permission is checked again automatically. Enable **Launch at login** in Settings if desired.

The macOS bundle identifier remains `dev.fernando.keyboard-navigation` for continuity with existing Accessibility and login-item registrations; the app, executable, package and window are named Vimstride.

The build is signed locally with an ad-hoc signature. Set `CODE_SIGN_IDENTITY` to your Developer ID to sign for distribution; notarization is a separate release step. A rebuilt ad-hoc app may require renewing its Accessibility grant. Build on each desired Mac architecture; the default build targets the current machine.

## Default shortcuts

**Super means Command+Control+Shift**, matching the existing Karabiner Caps Lock mapping. The app does not remap Caps Lock or change Karabiner.

| Action | Shortcut |
| --- | --- |
| Move pointer | Hold Super + H/J/K/L |
| Left-click / drag | Super + Space; hold Space while moving to drag |
| Right-click | Super + R |
| Faster movement | Add Right Shift |
| Precise movement | Add Right Control |
| Click hints | Super + F, then release Super and type the label |
| Focus-only hints | Super + V, then release Super and type the label |
| Browse hint targets | Tab / Shift+Tab |
| Click browsed target | Return |
| Focus without clicking | Option+Return |
| Right-click target | Shift+Return |
| Command-click target | Command+Return |
| Resize hint labels | Equal / Minus |
| Correct hint / exit | Backspace / Escape |
| Scroll mode | Super + G, then release Super |
| Scroll | H/J/K/L; Shift to dash faster |
| Half-page scroll | U / D |
| Scroll toward top / bottom | T / B (bounded 5,000-point steps) |
| Next / previous container | Tab / Shift+Tab |
| Select container | 1–9 |
| Exit scroll mode | Escape or an unrelated key |

Releasing Super immediately clears movement and releases any held mouse button. Ordinary HJKL input passes through when movement is inactive. Click and scroll overlays do not activate the app or steal keyboard focus. Physical pointer clicks or scrolling cancel navigation. Click sounds use an original, bundled synthesized tick, and can be disabled or adjusted.

## Settings and dotfiles

Open Settings from the menu bar or launch the app again from Spotlight. All mode and navigation bindings are editable in **Keybindings**; **Save & Apply** validates them and applies changes immediately. **Use Super Defaults** stages defaults without overwriting anything until saved.

Settings and the TOML file share one source of truth:

```text
~/.config/vimstride/config.toml
```

`VIMSTRIDE_CONFIG` and `XDG_CONFIG_HOME` override the location; `--config /path/to/config.toml` can override it when launching the executable directly. The legacy `KEYBOARD_NAV_CONFIG` override is also accepted. If the new default file does not exist but `~/.config/keyboard-navigation/config.toml` does, the app continues using that existing file. Missing settings use defaults. Existing Kotlin-era TOML files remain readable, preserving their old shortcuts. A first launch with no config uses the new Super defaults. Save creates the file. After external changes choose **Reload TOML**; conflicting external changes are never silently overwritten. Saving follows dotfile symlinks and rewrites the file in canonical format (comments are not retained).

Bindings accept lowercase keys, side-specific modifiers, `cmd`, `ctrl`, `alt`, `esc`, and `super` / `hyper` aliases. Here both aliases mean the user's three-modifier Karabiner mapping, not the conventional four-modifier Hyper chord. Movement/click bindings omit the already-held activation modifiers. Invalid config disables hooks and opens Settings rather than running with unexpected shortcuts.

```sh
"build/Vimstride.app/Contents/MacOS/Vimstride" --print-default-config
"build/Vimstride.app/Contents/MacOS/Vimstride" --config config.example.toml --check-config
```

To diagnose missing hints, run the installed executable with `--check-accessibility PID`, using the target application's process ID. This checks the diagnostic process's Accessibility permission and prints only activation status and target counts by role, never labels or application content. A command launched from a terminal or another app can have a different permission context from the background app; check Vimstride Settings for the running app's permission status.

After replacing an ad hoc signed build, macOS can show Vimstride's Accessibility switch enabled while the app reports access denied. Quit Vimstride, remove its old Accessibility entry, add the installed app again, enable access, then relaunch it.

Launch at login uses Apple's `SMAppService.mainApp`. It is optional and reflects the system's actual registration/approval state rather than a TOML flag.

## Architecture and verification

- `shared-core/Sources/NavigationCore`: pure Swift movement state, motion math, geometry, hint generation/filtering/focus, scrolling, keybinding validation and TOML.
- `native/macos/Sources/MacNavigation`: AppKit/Accessibility/Core Graphics adapters, typed controllers, settings, menu bar and lifecycle. Native accessibility handles stay inside this target.
- `Sources/Vimstride`: app entry point.
- `Tests`: core algorithms plus in-memory native input routing tests. Native tests neither install a hook nor post system input.

```sh
swift test
bash scripts/build-app.sh
```

The app uses no network services and never saves or transmits keystrokes, labels, screen content or app content. The old `diagnostics` field is accepted for config compatibility but does not log typed input. Native hooks are invalidated during normal shutdown; disabled hooks clear held input and are re-enabled. Hint, focus and scroll modes request Electron's accessibility tree using its documented `AXManualAccessibility` attribute, allowing a short warm-up on first activation. Secure Input and the quality of an application's Accessibility tree affect available targets; apps without accessible scroll regions still receive a window-level scroll fallback.

This implements the requested movement, dragging, scrolling, element focus and click feedback workflow. It does not claim complete Homerow parity: text search, Mission Control navigation, click chaining, double-click hints and app-specific compatibility tuning remain future work.
