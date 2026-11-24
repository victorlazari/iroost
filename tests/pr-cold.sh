#!/bin/sh
# A panel with no pull-request list yet (cold) still shows its sessions while GitHub is slow: a refresh publishes a
# healthy profile's rows while the first PR search is still running, and ends once that search does.
# Fake gh and ssh (no network); tmux on this test's own socket; only this test's processes are checked or ended.
P=$(cd "$(dirname "$0")/.." && pwd)/bin/iroost
fail=0
say() { echo "FAIL: $*"; fail=1; }
command -v tmux >/dev/null || { echo "skip: needs tmux"; exit 0; }
T=$(mktemp -d); HOME=$T/home; export HOME; unset XDG_CONFIG_HOME XDG_CACHE_HOME TMUX TMUX_PANE GITHUB_TOKEN GH_TOKEN
mkdir -p "$HOME/.config/iroost/profiles" "$T/bin" "$T/w"
export IROOST_PRS=1 IROOST_POKEMON=off IROOST_SPOTIFY=off
SOCK=$T/tmux.sock RT=$(command -v tmux)
printf '#!/bin/sh\nexec "%s" -S "%s" "$@"\n' "$RT" "$SOCK" >"$T/bin/tmux"
# gh: records its pid, then hangs until the test lets it answer (one PR). ssh: no network, no key.
printf '#!/bin/sh\necho $$ >>"%s/gh.pids"\nwhile [ ! -e "%s/gh.go" ]; do sleep 0.05; done\n' "$T" "$T" >"$T/bin/gh"
printf 'printf "me\\037gh\\\\no/r\\0371\\037t\\037https://x/1\\037false\\037b\\037\\037\\0372026-01-01T00:00:00Z\\\\n"\n' >>"$T/bin/gh"
printf '#!/bin/sh\nexit 255\n' >"$T/bin/ssh"
chmod +x "$T/bin/tmux" "$T/bin/gh" "$T/bin/ssh"
PATH=$T/bin:$PATH; export PATH
tm() { "$RT" -S "$SOCK" -f /dev/null "$@"; }
printf 'type=local\nrepos=%s\nonly=%s\n' "$T/w" "$T/w" >"$HOME/.config/iroost/profiles/fx.conf"
tm new-session -d -s s1 -c "$T/w" /bin/sh; tm set-option -t "=s1:" @iroost_agent term
S=$HOME/.cache/iroost
cleanup() {
  : >"$T/gh.go"; i=0; while [ -d "$S/1.rflock" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  for p in $(cat "$T/gh.pids" 2>/dev/null); do kill "$p" 2>/dev/null; done
  tm kill-server 2>/dev/null; rm -rf "$T"
}
trap cleanup EXIT
waitfor() { i=0; while ! eval "$1" && [ $i -lt "$2" ]; do sleep 0.1; i=$((i+1)); done; eval "$1"; }
keys() { { tr '\0' '\n' <"$S/1.cache"; } 2>/dev/null | cut -f1; }
hung() { for p in $(cat "$T/gh.pids" 2>/dev/null); do kill -0 "$p" 2>/dev/null && return 0; done; return 1; }

# Cold (no list yet), on the quiet periodic refresh (no spinner, so no panel needs to listen on the port): the
# session shows while the search hangs, and the refresh's last redraw, once the search answers, has the PR too.
zsh "$P" _refresh 1 9 tick
waitfor '[ -s "$T/gh.pids" ]' 50 || say "the cold refresh never asked GitHub (fixture)"
waitfor 'keys | grep -qx fx/s1' 80 || say "cold: the session never showed while the PR search hung"
hung || say "fixture: the PR search was not still running when the session showed"
keys | grep -q '^+pr/https' && say "fixture: a PR showed before GitHub answered"
: >"$T/gh.go"
waitfor '[ ! -d "$S/1.rflock" ]' 80 || say "cold: the refresh never ended after the PR search answered"
keys | grep -qx '+pr/https://x/1' || say "cold: the refresh ended without the PR GitHub sent: $(keys | tr '\n' ' ')"

# Warm (a list, due for a new search): the refresh ends while the search still hangs; the last list stays shown.
rm -f "$T/gh.go" "$T/gh.pids"; touch -t 197001010000 "$S/prs"
tm new-session -d -s s2 -c "$T/w" /bin/sh; tm set-option -t "=s2:" @iroost_agent term
zsh "$P" _refresh 1 9 tick
waitfor '[ -s "$T/gh.pids" ]' 50 || say "the warm refresh never asked GitHub (fixture)"
waitfor '[ ! -d "$S/1.rflock" ]' 80 || say "warm: the refresh waited for the hung PR search"
hung || say "fixture: the PR search had ended before the refresh did"
keys | grep -qx fx/s2 || say "warm: the new session did not show"
keys | grep -qx '+pr/https://x/1' || say "warm: the last PR list was not shown"
[ $fail = 0 ] && echo ok
exit $fail
