#!/bin/bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $# == 0 ]] || exit 2
DEST='/Library/Application Support/battctl'
[[ -d "$DEST" && ! -L "$DEST" ]] || { echo 'No valid CLI installation.' >&2; exit 1; }
if launchctl print system/com.geoochi.battctl >/dev/null 2>&1; then
 echo 'Legacy SMC daemon detected; stop and restore it separately before removing its binary.' >&2; exit 1
fi
if [[ -e "/Library/Application Support/battctl-adapter/config.plist" ]]; then
 "$DEST/battctl" adapter-stop
fi
# Restore before removing the executable; retain it if restoration cannot be verified.
STATE='/Library/Application Support/battctl-reboot-test'
if [[ -e "$STATE" || -L "$STATE" ]]; then
 "$DEST/battctl" restore
else
 echo 'No original-limit backup exists; removing the CLI without changing battery settings.'
fi
if [[ -L /usr/local/bin/battctl && $(readlink /usr/local/bin/battctl) == "$DEST/battctl" ]]; then
 rm /usr/local/bin/battctl
fi
ADAPTER="/Library/Application Support/battctl-adapter"
if [[ -d "$ADAPTER" && ! -L "$ADAPTER" ]]; then
 rm -f "$ADAPTER/battctl" "$ADAPTER/controller.log"
 rmdir "$ADAPTER" || echo "Retained nonempty adapter directory."
fi
rm "$DEST/battctl"
rmdir "$DEST"
echo 'Removed CLI. Any original-limit backup and test logs are retained. Stop the optional user recorder separately with scripts/record-test.sh stop.'
