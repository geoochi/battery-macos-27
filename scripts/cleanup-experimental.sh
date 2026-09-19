#!/bin/bash
# Upgrade-only cleanup. No power-control implementation is shipped in v0.2.1.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $# == 0 ]] || exit 2
OLD='/Library/Application Support/battctl-adapter'
PLIST=/Library/LaunchDaemons/com.geoochi.battctl.adapter.plist
JOB=system/com.geoochi.battctl.adapter
safe_path() {
 [[ ! -L "$1" && $(stat -f %u "$1") == 0 ]] || return 1
 local mode
 mode=$(stat -f %Lp "$1")
 (( (8#$mode & 0022) == 0 ))
}
old_processes() {
 pgrep -f '^/Library/Application Support/battctl-adapter/battctl (adapter-daemon|adapter-guard)$' >/dev/null
}
if [[ ! -e "$OLD" && ! -L "$OLD" && ! -e "$PLIST" ]] && ! launchctl print "$JOB" >/dev/null 2>&1 && ! old_processes; then
 exit 0
fi
for path in /Library '/Library/Application Support'; do
 safe_path "$path" || { echo 'Unsafe parent directory; cleanup refused.' >&2; exit 1; }
done
[[ -d "$OLD" ]] && safe_path "$OLD" || { echo 'Experimental controller directory is missing or unsafe; recovery files retained.' >&2; exit 1; }
if [[ -e "$OLD/config.plist" || -L "$OLD/config.plist" || -e "$PLIST" || -L "$PLIST" ]] || launchctl print "$JOB" >/dev/null 2>&1 || old_processes; then
 [[ -x "$OLD/battctl" ]] && safe_path "$OLD/battctl" || { echo 'The old recovery executable is missing or unsafe. Stop and restore the old controller before upgrading.' >&2; exit 1; }
 echo 'Stopping the experimental controller and restoring adapter power; the existing native limit may resume charging.'
 "$OLD/battctl" adapter-stop
fi
if launchctl print "$JOB" >/dev/null 2>&1 || old_processes; then
 echo 'Recovery is still running; retry after it finishes. No recovery files removed.' >&2; exit 1
fi
[[ ! -e "$OLD/config.plist" && ! -e "$PLIST" ]] || { echo 'Controller cleanup incomplete; files retained.' >&2; exit 1; }
# Remove only files belonging to the old controller. Preserve unknown files.
rm -f "$OLD/battctl" "$OLD/controller.log" "$OLD/status.json"
rmdir "$OLD" || echo 'Retained unknown files in the former controller directory.'
echo 'Experimental controller removed. Native target and original-limit backup preserved.'
