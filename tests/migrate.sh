#!/bin/bash
# An account that had lzr1-panel keeps its profiles, layout and cache under the new name, and loses the old links and hook.
R=$(cd "$(dirname "$0")/.." && pwd)
fail=0
say() { echo "FAIL: $*"; fail=1; }
HOME=$(mktemp -d); export HOME; unset XDG_CONFIG_HOME XDG_CACHE_HOME
BIN=$HOME/.local/bin SKILLS=$HOME/.claude/skills CONFIG=$HOME/.config/iroost
HOOK_BEGIN='# >>> iroost >>>' HOOK_END='# <<< iroost <<<'
ok() { :; }; warn() { echo "warn: $*"; }; info() { :; }
eval "$(sed -n '/^# remove_hook/,/^GCONF_FILE=/p' "$R/install.sh")"

mkdir -p "$HOME/.config/lzr1-panel/profiles" "$HOME/.cache/lzr1-panel" "$HOME/.cache/lzr1-panel-viewer" "$BIN" "$SKILLS"
echo "type=local" >"$HOME/.config/lzr1-panel/profiles/me.conf"; echo "order=me" >"$HOME/.config/lzr1-panel/layout.conf"
echo x >"$HOME/.cache/lzr1-panel/prs"
ln -s "$R/bin/lzr1-panel" "$BIN/lzr1-panel"; ln -s "$R/skills/lzr1-panel-profiles" "$SKILLS/lzr1-panel-profiles"
printf 'export KEEP=1\n# >>> lzr1-panel >>>\nlzr1-panel open\n# <<< lzr1-panel <<<\nexport ALSO=1\n' >"$HOME/.zshrc"

# A bare `iroost` run before the move leaves empty new folders: they must not block it.
mkdir -p "$CONFIG/profiles" "$HOME/.cache/iroost"

migrate_from_lzr1_panel

[ -f "$CONFIG/profiles/me.conf" ] && [ -f "$CONFIG/layout.conf" ] || say "profiles or layout were not moved to $CONFIG"
[ -f "$HOME/.cache/iroost/prs" ] && [ -d "$HOME/.cache/iroost-viewer" ] || say "cache was not moved"
[ ! -e "$HOME/.config/lzr1-panel" ] && [ ! -e "$HOME/.cache/lzr1-panel" ] || say "old folders are still there"
[ ! -L "$BIN/lzr1-panel" ] && [ ! -L "$SKILLS/lzr1-panel-profiles" ] || say "old links are still there"
grep -q lzr1 "$HOME/.zshrc" && say "the old hook is still in .zshrc"
grep -q KEEP=1 "$HOME/.zshrc" && grep -q ALSO=1 "$HOME/.zshrc" || say "the migration ate the person's own lines in .zshrc"

# Run again, and on an account that never had the old name: nothing changes, nothing fails.
migrate_from_lzr1_panel || say "second run failed"
[ -f "$CONFIG/profiles/me.conf" ] || say "second run lost the profile"
# A new folder that already exists is never overwritten.
mkdir -p "$HOME/.config/lzr1-panel"; echo old >"$HOME/.config/lzr1-panel/x"
out=$(migrate_from_lzr1_panel); echo "$out" | grep -q 'already exists' || say "no warning when both config folders exist"
[ -f "$CONFIG/profiles/me.conf" ] && [ -f "$HOME/.config/lzr1-panel/x" ] || say "an existing new config was overwritten or the old one lost"

rm -rf "$HOME"
[ $fail = 0 ] && echo ok
exit $fail
