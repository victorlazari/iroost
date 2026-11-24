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
[ "$(zsh "$P" --help 2>&1)" = "$out" ] || say "--help differs from help"

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
