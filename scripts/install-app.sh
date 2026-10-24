#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
# Retire the previous installation's KeepAlive agent without deleting it.
# Otherwise both generations can compete for the same global input shortcuts.
legacy_plist="$HOME/Library/LaunchAgents/dev.fernando.keyboard-navigation.plist"
if [ -f "$legacy_plist" ]; then
    legacy_program=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$legacy_plist" 2>/dev/null || true)
    case "$legacy_program" in
        */keyboard-navigation/bin/keyboard-navigation)
            legacy_service="gui/$(id -u)/dev.fernando.keyboard-navigation"
            launchctl disable "$legacy_service"
            if launchctl print "$legacy_service" >/dev/null 2>&1; then
                launchctl bootout "$legacy_service"
            fi
            printf 'Disabled the legacy Kotlin login service; its files were preserved.\n'
            ;;
    esac
fi
destination="${VIMSTRIDE_APPLICATIONS_DIR:-${KEYBOARD_NAV_APPLICATIONS_DIR:-$HOME/Applications}}"
mkdir -p "$destination"
# Keep only the current app name discoverable; preserve the old bundle outside
# Applications so it cannot win Spotlight searches for the shared bundle ID.
old_app="$destination/Keyboard Navigation.app"
if [ -e "$old_app" ]; then
    backup_root="$HOME/Library/Application Support/Vimstride/Backups"
    mkdir -p "$backup_root"
    mv "$old_app" "$backup_root/Keyboard Navigation.app.backup.$(date +%Y%m%d-%H%M%S)"
fi
app="$destination/Vimstride.app"
if [ -e "$app" ]; then
    backup="$app.backup.$(date +%Y%m%d-%H%M%S)"
    mv "$app" "$backup"
    printf 'Previous app saved to %s\n' "$backup"
fi
cp -R "build/Vimstride.app" "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
printf 'Installed %s\n' "$app"
