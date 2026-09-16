#!/bin/bash
# Read-only sampling at login and every minute while awake; does not keep Mac awake.
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run as your normal login user, without sudo.' >&2; exit 1; }
[[ $# == 1 && ( $1 == start || $1 == stop || $1 == status ) ]] || { echo 'Usage: record-test.sh start|stop|status' >&2; exit 2; }
LABEL=com.geoochi.battctl.monitor
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DEST="$HOME/Library/Application Support/battctl-monitor"
LOGDIR="$HOME/Library/Logs/battctl"
JOB="gui/$UID/$LABEL"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ $1 == status ]]; then
 launchctl print "$JOB"
 exit
fi
if [[ $1 == stop ]]; then
 if launchctl print "$JOB" >/dev/null 2>&1; then launchctl bootout "$JOB"; fi
 rm -f "$PLIST"
 echo "Recorder stopped; battery policy unchanged. Logs retained: $LOGDIR/monitor.jsonl"
 exit
fi
[[ ! -L "$DEST" && ! -L "$LOGDIR" && ! -L "$PLIST" ]] || { echo 'Refusing symlink output paths.' >&2; exit 1; }
mkdir -p "$DEST" "$LOGDIR" "$HOME/Library/LaunchAgents"
# Replace atomically so an existing sampling process can finish its current read.
RECORDER_TMP=$(mktemp "$DEST/.battctl.XXXXXX")
trap 'rm -f "$RECORDER_TMP"' EXIT
install -m 755 "$ROOT/build/battctl" "$RECORDER_TMP"
mv -f "$RECORDER_TMP" "$DEST/battctl"
if launchctl print "$JOB" >/dev/null 2>&1; then
 launchctl kickstart "$JOB"
 echo "Recorder updated; follows the saved requested target. Logs: $LOGDIR/monitor.jsonl"
 exit
fi
rm -f "$PLIST"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert Label -string "$LABEL" "$PLIST"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$PLIST"
/usr/bin/plutil -insert ProgramArguments.0 -string "$DEST/battctl" "$PLIST"
/usr/bin/plutil -insert ProgramArguments.1 -string verify "$PLIST"
/usr/bin/plutil -insert ProgramArguments.2 -string --json "$PLIST"
/usr/bin/plutil -insert RunAtLoad -bool YES "$PLIST"
/usr/bin/plutil -insert StartInterval -integer 60 "$PLIST"
/usr/bin/plutil -insert ProcessType -string Background "$PLIST"
/usr/bin/plutil -insert StandardOutPath -string "$LOGDIR/monitor.jsonl" "$PLIST"
/usr/bin/plutil -insert StandardErrorPath -string "$LOGDIR/monitor.error.log" "$PLIST"
chmod 600 "$PLIST"
/usr/bin/plutil -lint "$PLIST"
launchctl bootstrap "gui/$UID" "$PLIST"
echo "Read-only recorder started (once/minute while awake). Logs: $LOGDIR/monitor.jsonl"
echo 'Stop: ./scripts/record-test.sh stop'
