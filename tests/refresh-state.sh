#!/bin/sh
# What a refresh concludes from the session scan (LIST_SCRIPT through _list) on a real tmux server of its own:
# - the server cannot be reached (its socket refuses this user): the profile is down, its last rows stay (stale) and
#   its sessions keep their alert state; nothing reads as "no sessions";
# - the server is gone (no server running, or no socket at all): a fresh, positively empty answer, so the profile is
#   online with no rows and its ended sessions leave no state behind.
P=$(cd "$(dirname "$0")/.." && pwd)/bin/iroost
fail=0
say() { echo "FAIL: $*"; fail=1; }
command -v tmux >/dev/null || { echo "skip: needs tmux"; exit 0; }
[ "$(id -u)" = 0 ] && { echo "skip: root ignores the socket's permissions"; exit 0; }
T=$(mktemp -d); HOME=$T/home; export HOME; unset XDG_CONFIG_HOME XDG_CACHE_HOME TMUX TMUX_PANE
mkdir -p "$HOME" "$T/bin" "$T/sock" "$T/w"
export IROOST_PRS=0 IROOST_POKEMON=off IROOST_SPOTIFY=off
SOCK=$T/sock/tmux.sock RT=$(command -v tmux)
# A stand-in that keeps tmux on this test's own socket (never the machine's default server).
printf '#!/bin/sh\nexec "%s" -S "%s" "$@"\n' "$RT" "$SOCK" >"$T/bin/tmux"; chmod +x "$T/bin/tmux"
PATH=$T/bin:$PATH; export PATH
tm() { "$RT" -S "$SOCK" -f /dev/null "$@"; }
mkdir -p "$HOME/.config/iroost/profiles"
printf 'type=local\nrepos=%s\nonly=%s\n' "$T/w" "$T/w" >"$HOME/.config/iroost/profiles/fx.conf"
for s in s1 s2; do tm new-session -d -s $s -c "$T/w" /bin/sh; tm set-option -t "=$s:" @iroost_agent term; done
S=$HOME/.cache/iroost
heading() { tr '\0' '\n' <"$T/out" | grep '^fx/	' | sed 's/\x1b\[[0-9;]*m//g'; }

zsh "$P" _list 1 >"$T/out" 2>/dev/null || say "first _list failed"
[ "$(wc -l <"$S/raw-fx" | tr -d ' ')" = 2 ] || say "seed: want 2 rows, got $(wc -l <"$S/raw-fx")"
[ -e "$S/seen/fx/s1" ] || say "seed: no alert state recorded for s1"
cp "$S/raw-fx" "$T/raw.seed"

chmod 000 "$T/sock"
zsh "$P" _list 1 >"$T/out" 2>/dev/null || say "_list failed with the socket refused"
chmod 700 "$T/sock"
cmp -s "$S/raw-fx" "$T/raw.seed" || say "socket refused: the last rows were replaced by: '$(cat "$S/raw-fx")'"
[ -e "$S/down-fx" ] || say "socket refused: the profile was not marked down"
heading | grep -q 'stale · 2' || say "socket refused: heading is not 'stale · 2': '$(heading)'"
[ -e "$S/seen/fx/s1" ] && [ -e "$S/seen/fx/s2" ] || say "socket refused: the sessions' alert state was dropped"

rm -f "$S/down-fx"
tm kill-server
zsh "$P" _list 1 >"$T/out" 2>/dev/null || say "_list failed with no server"
[ "$(grep -c . "$S/raw-fx")" = 0 ] || say "no server: want no rows, got '$(cat "$S/raw-fx")'"
[ -e "$S/down-fx" ] && say "no server: a machine with no tmux running was marked down"
heading | grep -q 'online · 0' || say "no server: heading is not 'online · 0': '$(heading)'"
[ -e "$S/seen/fx/s1" ] && say "no server: an ended session kept its alert state"

# Never started (no socket file at all, as on a machine where tmux has not run yet): fresh and empty too.
rm -f "$SOCK"
zsh "$P" _list 1 >"$T/out" 2>/dev/null || say "_list failed with no socket"
[ -e "$S/down-fx" ] && say "no socket: a machine where tmux never ran was marked down"
heading | grep -q 'online · 0' || say "no socket: heading is not 'online · 0': '$(heading)'"

tm kill-server 2>/dev/null
rm -rf "$T"
[ $fail = 0 ] && echo ok
exit $fail
