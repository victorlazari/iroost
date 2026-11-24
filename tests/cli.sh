#!/bin/sh
# What a person sees typing iroost: bare, it suggests what to do; help lists everything; a typo says where to look.
P=$(cd "$(dirname "$0")/.." && pwd)/bin/iroost
fail=0
say() { echo "FAIL: $*"; fail=1; }
HOME=$(mktemp -d); export HOME; unset XDG_CONFIG_HOME XDG_CACHE_HOME

# iroost (no arguments): a short list of suggestions that names `iroost open`, exit 0.
out=$(zsh "$P" 2>&1); rc=$?
[ "$rc" = 0 ] || say "bare iroost: want rc 0 got $rc"
echo "$out" | grep -q 'iroost open' || say "bare iroost does not suggest 'iroost open'"
echo "$out" | grep -q 'iroost help' || say "bare iroost does not point to 'iroost help'"
[ "$(echo "$out" | wc -l)" -le 16 ] || say "bare iroost is a wall of text ($(echo "$out" | wc -l) lines), want <= 16"

# iroost help: every command, including the ones the suggestions leave out.
out=$(zsh "$P" help 2>&1); rc=$?
[ "$rc" = 0 ] || say "iroost help: want rc 0 got $rc"
echo "$out" | grep -q 'iroost remote on' || say "iroost help does not list 'remote on'"
echo "$out" | grep -q 'iroost splash' || say "iroost help does not list 'splash'"
echo "$out" | grep -q 'iroost close' || say "iroost help does not list 'close'"
[ "$(zsh "$P" --help 2>&1)" = "$out" ] || say "--help differs from help"

# iroost close with nothing open: says so, rc 0, and the machines' tmux sessions stay (it never touches them).
out=$(zsh "$P" close 2>&1); rc=$?
[ "$rc" = 0 ] || say "close: want rc 0 got $rc"
echo "$out" | grep -qi 'keep running' || say "close does not say the tmux sessions keep running: $out"

# iroost close ends a running panel/viewer process (here a stand-in with the same command line), not a bystander.
sh -c "exec -a 'zsh $P _viewer 4242' sleep 60" & v=$!
sleep 30 & b=$!
zsh "$P" close >/dev/null 2>&1; sleep 0.5
kill -0 $v 2>/dev/null && say "close left a viewer running" && kill $v
kill -0 $b 2>/dev/null || say "close killed a bystander"
kill $b 2>/dev/null

# iroost profile add (local): all three lookups in one go, the file written; remove takes it away.
mkdir -p "$HOME/r"
zsh "$P" profile add t1 --local --repos "$HOME/r" --claude /bin/sh >/dev/null 2>&1
grep -q '^claude=/bin/sh' "$HOME/.config/iroost/profiles/t1.conf" || say "profile add did not write the profile"
zsh "$P" profile remove t1 >/dev/null 2>&1; [ ! -e "$HOME/.config/iroost/profiles/t1.conf" ] || say "profile remove left the file"

# The panel never freezes on a reload: no fzf action waits for every machine (reload-sync does).
grep -v '^ *#' "$P" | grep -q 'reload-sync(' && say "an fzf action uses reload-sync: the sidebar freezes while machines answer"

# iroost nonsense: nothing on stdout, a pointer on stderr, rc 1.
out=$(zsh "$P" nonsense 2>/dev/null); rc=$?
[ "$rc" = 1 ] || say "unknown command: want rc 1 got $rc"
[ -z "$out" ] || say "unknown command wrote to stdout: $out"
zsh "$P" nonsense 2>&1 >/dev/null | grep -q "iroost help" || say "unknown command does not point to 'iroost help'"

# The old name is gone from everything it prints.
for a in "" help version doctor; do
  zsh "$P" $a 2>&1 | grep -qi 'lzr1' && say "'iroost $a' still prints the old name"
done

# iroost version: "iroost X.Y.Z".
zsh "$P" version | grep -Eq '^iroost [0-9]+\.[0-9]+\.[0-9]+' || say "version: want 'iroost X.Y.Z'"

rm -rf "$HOME"
[ $fail = 0 ] && echo ok
exit $fail
