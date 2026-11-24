#!/bin/sh
# The session scan (LIST_SCRIPT) on a real tmux server of its own: a plain terminal's screen is not read, and Git
# runs once per folder however many sessions share it, while every row still shows its own branch and changes.
P=$(cd "$(dirname "$0")/.." && pwd)/bin/iroost
fail=0
say() { echo "FAIL: $*"; fail=1; }
command -v tmux >/dev/null && command -v git >/dev/null || { echo "skip: needs tmux and git"; exit 0; }
T=$(mktemp -d); HOME=$T/home; export HOME; unset XDG_CONFIG_HOME XDG_CACHE_HOME TMUX TMUX_PANE
mkdir -p "$HOME" "$T/bin"
export IROOST_PRS=0 IROOST_POKEMON=off IROOST_SPOTIFY=off
SOCK=$T/tmux.sock CALLS=$T/calls RT=$(command -v tmux) RG=$(command -v git)
# Stand-ins that count calls and keep tmux on this test's own socket (never the machine's default server).
printf '#!/bin/sh\nprintf "tmux %%s\\n" "$1" >>"%s"; exec "%s" -S "%s" "$@"\n' "$CALLS" "$RT" "$SOCK" >"$T/bin/tmux"
printf '#!/bin/sh\n[ "$1" = -C ] && printf "git %%s %%s\\n" "$3" "$2" >>"%s"; exec "%s" "$@"\n' "$CALLS" "$RG" >"$T/bin/git"
chmod +x "$T/bin/tmux" "$T/bin/git"
PATH=$T/bin:$PATH; export PATH
tm() { "$RT" -S "$SOCK" -f /dev/null "$@"; }

# main: a clean repository; wt: a linked worktree of it, detached, with one new file; plain: no repository at all.
W=$T/w; mkdir -p "$W/main" "$W/plain"
g() { "$RG" -C "$W/main" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
g init -q -b trunk; g commit -q --allow-empty -m one; g worktree add -q --detach "$W/wt"
: >"$W/wt/new"
mkdir -p "$HOME/.config/iroost/profiles"
printf 'type=local\nrepos=%s\nonly=%s\n' "$W" "$W" >"$HOME/.config/iroost/profiles/fx.conf"

term() { tm new-session -d -s "$1" -c "$2" /bin/sh; tm set-option -t "=$1:" @iroost_agent term; }
term m1 "$W/main"; term m2 "$W/main"; term m3 "$W/main"
term w1 "$W/wt"
term p1 "$W/plain"; term p2 "$W/plain"
# gone: a folder removed under its sessions; Git fails there, and the rows say nothing rather than something wrong.
mkdir "$W/gone"; term x1 "$W/gone"; term x2 "$W/gone"
# An untagged session is read as an agent: its screen must still be captured and classified.
tm new-session -d -s a1 -c "$W/wt" "printf 'esc to interrupt\\n'; exec sleep 600"
sleep 0.3
rm -rf "$W/gone"

: >"$CALLS"
zsh "$P" _list 1 >/dev/null 2>"$T/err" || say "_list failed: $(cat "$T/err")"
R=$HOME/.cache/iroost/raw-fx
[ -r "$R" ] || say "no raw rows written"
# row NAME: "state branch changed" of NAME's record (fields 2, 9 and 10).
row() { awk -F "$(printf '\037')" -v n="$1" '$1 == n { print $2 " " $9 " " $10 }' "$R"; }
for s in m1 m2 m3; do [ "$(row $s)" = "idle trunk 0" ] || say "$s: want 'idle trunk 0' got '$(row $s)'"; done
[ "$(row w1)" = "idle detached 1" ] || say "w1: want 'idle detached 1' got '$(row w1)'"
[ "$(row a1)" = "work detached 1" ] || say "a1: want 'work detached 1' got '$(row a1)'"
for s in p1 p2 x1 x2; do [ "$(row $s)" = "idle  " ] || say "$s: want no branch and no count got '$(row $s)'"; done
[ "$(wc -l <"$R" | tr -d ' ')" = 9 ] || say "want 9 rows got $(wc -l <"$R")"

n() { grep -c "$1" "$CALLS"; }
[ "$(n '^tmux capture-pane')" = 1 ] || say "want 1 pane capture (the agent only) got $(n '^tmux capture-pane')"
[ "$(n '^git branch')" = 4 ] || say "want 4 branch lookups (one per folder) got $(n '^git branch')"
[ "$(n '^git status')" = 2 ] || say "want 2 status runs (one per repository folder) got $(n '^git status')"
[ "$(n "^git status $W/main\$")" = 1 ] && [ "$(n "^git status $W/wt\$")" = 1 ] ||
  say "a worktree's status was taken from another folder's: $(grep '^git status' "$CALLS" | tr '\n' ';')"

tm kill-server 2>/dev/null
rm -rf "$T"
[ $fail = 0 ] && echo ok
exit $fail
