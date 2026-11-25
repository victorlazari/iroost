#!/bin/sh
# Behaviour that keeps the sidebar from freezing: a slow helper is cut off, and a closed panel leaves nothing polling.
# It runs a private copy of iroost (its own path, so _reap only ever matches this test's processes) and checks and
# kills only processes it started itself: safe on a machine with real panels open.
R=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/iroost-freeze.XXXXXX")" && pwd -P)
mkdir -p "$T/bin" "$T/cache/iroost"; cp "$R/bin/iroost" "$T/bin/"; cp -R "$R/lib" "$T/"
P=$T/bin/iroost
export XDG_CACHE_HOME=$T/cache XDG_CONFIG_HOME=$T/config
fail=0
say() { echo "FAIL: $*"; fail=1; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
mine() { cat "$T"/*.pid 2>/dev/null; }  # every process this test started (each records its own PID)
trap 'for p in $(mine); do kill -KILL "$p" 2>/dev/null; done; rm -rf "$T"' EXIT

# _timeout SECS CMD...: CMD's output, or exit 124 when it ran longer than SECS (and it is killed).
start=$(date +%s)
zsh "$P" _timeout 1 sh -c 'echo $$ >"$0"; exec sleep 31' "$T/slow.pid"; rc=$?
took=$(( $(date +%s) - start ))
[ "$rc" = 124 ] || say "_timeout of a slow command: want rc 124 got $rc"
[ "$took" -le 3 ] || say "_timeout of a slow command took ${took}s, want <= 3"
slow=$(cat "$T/slow.pid" 2>/dev/null)
[ -n "$slow" ] || say "_timeout never started the slow command"
alive "$slow" && say "_timeout left the slow command running"
out=$(zsh "$P" _timeout 5 echo hi); rc=$?
[ "$rc" = 0 ] && [ "$out" = hi ] || say "_timeout of a fast command: want 'hi' rc 0 got '$out' rc $rc"

# _spotpoll ID PORT PANELPID: ends at once when the panel was told to quit (its .quit flag), though the panel lives.
sh -c 'echo $$ >"$0"; exec sleep 60' "$T/spotpanel.pid" >/dev/null 2>&1 &
sleep 0.2; panel=$(cat "$T/spotpanel.pid")
: >"$T/cache/iroost/77.quit"
zsh "$P" _spotpoll 77 1 "$panel"
sleep 3
[ -z "$(pgrep -f "$P _spotpoll 77 1")" ] || say "_spotpoll kept running after the panel's quit flag"

# _reap: a panel left alive after its layout died (its parent is gone, so whatever adopts orphans here took it: PID 1,
# or a user service manager such as systemd --user) is ended. Left alone: a panel that still has its parent, another
# install's orphaned panel (another path), and an orphan that is not iroost at all.
fake() {  # fake NAME ARGV...: a stand-in whose command line is ARGV; NAME.pid and NAME-sleep.pid record its PIDs
  exec zsh -c 'echo $$ >"$0.pid"; sleep 62 & echo $! >"$0-sleep.pid"; wait' "$T/$@" >/dev/null 2>&1
}
( fake orphan "$P" _panel 99991 & )
( fake other "$T/elsewhere/bin/iroost" _panel 99993 & )
( sh -c 'echo $$ >"$0"; exec sleep 62' "$T/stray.pid" >/dev/null 2>&1 & )
fake live "$P" _panel 99992 &
sleep 1
orphan=$(cat "$T/orphan.pid") live=$(cat "$T/live.pid") other=$(cat "$T/other.pid") stray=$(cat "$T/stray.pid")
parent() { ps -o ppid= -p "$1" | tr -d ' '; }
adopter=$(parent "$orphan")
for p in $$ $(mine); do  # the orphan's parent is none of this test's processes, nor the test itself
  [ "$adopter" != "$p" ] || say "fixture: the orphaned panel still has a parent here ($p)"
done
[ "$(parent "$live")" = $$ ] || say "fixture: the live panel's parent is not this test"
ms=$(zsh -c 'zmodload zsh/datetime; s=$EPOCHREALTIME; zsh "$0" _reap; print ${$(( (EPOCHREALTIME - s) * 1000 ))%.*}' "$P")
[ "$ms" -lt 1000 ] || say "_reap took ${ms}ms, want < 1000 (every layout start waits for it)"
sleep 1
alive "$orphan" && say "_reap left an orphaned panel running (adopted by $adopter: $(ps -o args= -p "$adopter"))"
alive "$live" || say "_reap ended a panel that still has its parent"
alive "$other" || say "_reap ended another install's orphaned panel"
alive "$stray" || say "_reap ended an orphan that is not iroost"
[ $fail = 0 ] && echo ok
exit $fail
