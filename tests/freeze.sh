#!/bin/sh
# Behaviour that keeps the sidebar from freezing: a slow helper is cut off, and a closed panel leaves nothing polling.
P=$(cd "$(dirname "$0")/.." && pwd)/bin/lzr1-panel
fail=0
say() { echo "FAIL: $*"; fail=1; }

# _timeout SECS CMD...: CMD's output, or exit 124 when it ran longer than SECS (and it is killed).
start=$(date +%s)
zsh "$P" _timeout 1 sleep 31; rc=$?
took=$(( $(date +%s) - start ))
[ "$rc" = 124 ] || say "_timeout of a slow command: want rc 124 got $rc"
[ "$took" -le 3 ] || say "_timeout of a slow command took ${took}s, want <= 3"
out=$(zsh "$P" _timeout 5 echo hi); rc=$?
[ "$rc" = 0 ] && [ "$out" = hi ] || say "_timeout of a fast command: want 'hi' rc 0 got '$out' rc $rc"
[ -z "$(pgrep -f 'sleep 31')" ] || say "_timeout left the slow command running"

# _spotpoll ID PORT PANELPID: ends at once when the panel was told to quit (its .quit flag), though the panel lives.
export XDG_CACHE_HOME=$(mktemp -d)
S=$XDG_CACHE_HOME/lzr1-panel; mkdir -p "$S"
sleep 60 >/dev/null 2>&1 & panel=$!
: >"$S/77.quit"
zsh "$P" _spotpoll 77 1 $panel
sleep 3
[ -z "$(pgrep -f '_spotpoll 77 1')" ] || say "_spotpoll kept running after the panel's quit flag"
kill $panel 2>/dev/null; rm -rf "$XDG_CACHE_HOME"
# _reap: a panel left alive after its layout died (its parent is gone) is ended; a live panel is left alone.
( zsh -c 'sleep 62; :' "$P" _panel 99991 >/dev/null 2>&1 & )
zsh -c 'sleep 63; :' "$P" _panel 99992 >/dev/null 2>&1 & livepanel=$!
sleep 1
zsh "$P" _reap
sleep 1
[ -z "$(pgrep -f '_panel 99991')" ] || say "_reap left an orphaned panel running"
[ -n "$(pgrep -f '_panel 99992')" ] || say "_reap ended a panel that still has its parent"
kill $livepanel 2>/dev/null; pkill -f '_panel 9999' 2>/dev/null
[ $fail = 0 ] && echo ok
exit $fail
