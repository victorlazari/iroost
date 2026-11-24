#!/usr/bin/env bash
# iroost installer, for macOS and Linux. Safe to run again: every step checks before it changes anything.
#
#   ./install.sh              install and configure everything, asking before anything big
#   ./install.sh --yes        same, answering yes (Claude Code and Ghostty installs included)
#   ./install.sh --no-shell   leave your shell rc files alone
#   ./install.sh --uninstall  remove the links, the shell hook and the Claude skill (profiles stay)
#
# What it sets up: zsh, tmux, fzf (0.74+), curl, openssl, git, gh and jq; ttyd and Go if you want the panel in a browser;
# Claude Code if it is missing; Ghostty on macOS if you want it; the iroost command in ~/.local/bin; the Claude
# Code skill that creates profiles; a shell hook with cl-* helpers and (optionally) the panel opening with Ghostty;
# Ctrl+C copying in Ghostty; ImageMagick (the Pokémon sprites) and terminal-notifier (alerts) on request; GitHub sign-in;
# your first profile, with a name and a repositories folder it suggests (Enter, Enter) and an offer to add more
# machines over SSH; then iroost doctor checks it all.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=$HOME/.local/bin
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}/iroost
SKILLS=$HOME/.claude/skills
FZF_MIN=0.74
# Tools installed below land in ~/.local/bin, which a fresh account often has off PATH: make them visible to this run.
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac
YES=0 SHELL_HOOK=1 UNINSTALL=0
for a in "$@"; do
  case $a in
    --yes|-y) YES=1 ;;
    --no-shell) SHELL_HOOK=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

c_ok=$'\e[32m' c_dim=$'\e[90m' c_warn=$'\e[33m' c_bold=$'\e[1m' c_off=$'\e[0m'
step() { printf '\n%s▸ %s%s\n' "$c_bold" "$*" "$c_off"; }
ok()   { printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
info() { printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*"; }
# No terminal to answer (cannot open /dev/tty) is a no, not an empty answer's yes.
ask()  { [[ $YES == 1 ]] && return 0; local r; read -r -p "  $1 [Y/n] " r </dev/tty || return 1; [[ -z $r || $r == [Yy]* ]]; }
have() { command -v "$1" >/dev/null 2>&1; }

OS=$(uname -s)
HOOK_BEGIN='# >>> iroost >>>'
HOOK_END='# <<< iroost <<<'

# remove_hook RCFILE [BEGIN END]: the managed block between the markers (this version's by default)
remove_hook() {
  local rc=$1 b=${2:-$HOOK_BEGIN} e=${3:-$HOOK_END}
  [[ -f $rc ]] && grep -qF "$b" "$rc" || return 0
  local tmp; tmp=$(mktemp)
  awk -v b="$b" -v e="$e" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$rc" >"$tmp" && cat "$tmp" >"$rc" && rm -f "$tmp"
}

# migrate_from_lzr1_panel: iroost was called lzr1-panel. Move what a person has built (profiles, layout, remote settings,
# cached state) to the new names, and drop the old command link, skill link and shell hook. Nothing is deleted that has not
# been moved or replaced; a run on an account that never had the old name does nothing.
migrate_from_lzr1_panel() {
  local cfg=${XDG_CONFIG_HOME:-$HOME/.config} cache=${XDG_CACHE_HOME:-$HOME/.cache} moved=0 old new rc
  for pair in "$cfg/lzr1-panel:$CONFIG" "$cache/lzr1-panel:$cache/iroost" "$cache/lzr1-panel-viewer:$cache/iroost-viewer"; do
    old=${pair%%:*} new=${pair#*:}
    [[ -d $old ]] || continue
    if [[ -e $new ]]; then warn "left $old: $new already exists (merge by hand, then delete it)"; continue; fi
    mkdir -p "$(dirname "$new")" && mv "$old" "$new" && ok "moved $old → $new" && moved=1
  done
  for old in "$BIN/lzr1-panel" "$SKILLS/lzr1-panel-profiles"; do
    [[ -L $old ]] && rm -f "$old" && ok "removed the old link $old" && moved=1
  done
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    grep -qsF '# >>> lzr1-panel >>>' "$rc" || continue
    remove_hook "$rc" '# >>> lzr1-panel >>>' '# <<< lzr1-panel <<<' && ok "removed the old shell hook from $rc" && moved=1
  done
  if grep -qs 'lzr1-panel/install.sh' "$GCONF_FILE"; then
    sed -i.bak 's#Added by lzr1-panel/install.sh#Added by iroost/install.sh#' "$GCONF_FILE" && rm -f "$GCONF_FILE.bak"
  fi
  [[ $moved == 1 ]] && info "your own shell files may still say lzr1-panel or LZR1_*: they are now iroost and IROOST_* (see README, Moving from lzr1-panel)"
  return 0
}

GCONF_FILE="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"

if [[ $UNINSTALL == 1 ]]; then
  step "Uninstalling iroost"
  rm -f "$BIN/iroost" && ok "removed $BIN/iroost"
  rm -f "$SKILLS/iroost-profiles" && ok "removed the Claude skill link"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do remove_hook "$rc"; done
  ok "removed the shell hook"
  GCONF="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  if grep -qs -e 'iroost/install.sh' -e 'lzr1-panel/install.sh' "$GCONF"; then
    grep -v -e 'Added by iroost/install.sh' -e 'Added by lzr1-panel/install.sh' -e '^keybind = performable:ctrl+c=copy_to_clipboard$' "$GCONF" >"$GCONF.tmp" || true
    mv "$GCONF.tmp" "$GCONF" && ok "removed the Ghostty Ctrl+C copy key"
  fi
  info "profiles kept in $CONFIG (delete that folder to remove them)"
  exit 0
fi

printf '%s\n' "${c_bold}iroost installer${c_off} ${c_dim}($OS, from $REPO)${c_off}"

# ---- packages -------------------------------------------------------------------------------------------------------

pkg_install() {  # pkg_install NAME...: through the system's package manager
  if [[ $OS == Darwin ]]; then
    have brew || { warn "Homebrew is needed on macOS: https://brew.sh — install it, then run ./install.sh again"; exit 1; }
    brew install "$@"
  elif have apt-get; then sudo apt-get update -qq && sudo apt-get install -y "$@"
  elif have dnf; then sudo dnf install -y "$@"
  elif have pacman; then sudo pacman -S --noconfirm "$@"
  elif have zypper; then sudo zypper install -y "$@"
  elif have apk; then sudo apk add "$@"
  else warn "no known package manager: install $* yourself, then run ./install.sh again"; exit 1
  fi
}

version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

step "Checking tools"
for t in zsh tmux curl openssl git; do
  if have "$t"; then ok "$t"; else info "installing $t"; pkg_install "$t"; ok "$t installed"; fi
done

# gh lists your pull requests under the sessions; jq reads them when gh is not signed in. Neither is required.
for t in gh jq; do
  if have "$t"; then ok "$t"; continue; fi
  pkg=$t
  [[ $t == gh ]] && { have pacman || have apk; } && pkg=github-cli
  info "installing $t"
  if ( pkg_install "$pkg" ) >/dev/null 2>&1; then ok "$t installed"
  else warn "could not install $t: your pull requests need it (https://cli.github.com)"; fi
done

fzf_version() { fzf --version 2>/dev/null | awk '{print $1}'; }
if have fzf && version_ge "$(fzf_version)" "$FZF_MIN"; then
  ok "fzf $(fzf_version)"
else
  info "fzf $FZF_MIN or newer is needed (found: $(fzf_version || true))"
  if [[ $OS == Darwin ]]; then
    have fzf && brew upgrade fzf || pkg_install fzf
  else
    # Distribution packages lag behind; take the latest release binary.
    arch=$(uname -m); case $arch in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; armv7l) arch=armv7 ;; esac
    tag=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)
    [[ -n $tag ]] || { warn "could not find the latest fzf release"; exit 1; }
    mkdir -p "$BIN"
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${tag}/fzf-${tag}-linux_${arch}.tar.gz" | tar -xz -C "$BIN" fzf
    hash -r
  fi
  version_ge "$(fzf_version)" "$FZF_MIN" && ok "fzf $(fzf_version)" || { warn "fzf is still older than $FZF_MIN"; exit 1; }
fi

if have claude || [[ -x $HOME/.local/bin/claude ]]; then
  ok "Claude Code"
else
  warn "Claude Code is not installed on this machine"
  if ask "Install Claude Code now (official installer from claude.ai)?"; then
    curl -fsSL https://claude.ai/install.sh | bash
    ok "Claude Code installed — run 'claude' once to sign in"
  else
    info "skipped: local profiles need it; remote machines need their own install"
  fi
fi

if [[ $OS == Darwin ]]; then
  if [[ -d /Applications/Ghostty.app ]] || have ghostty; then
    ok "Ghostty"
  elif ask "Install Ghostty (the panel opens as a split there; without it, it uses a tmux layout)?"; then
    brew install --cask ghostty && ok "Ghostty installed"
  else
    info "skipped: iroost will use its tmux layout"
  fi
  # Ghostty reads this file as well as ~/.config/ghostty; "performable" passes Ctrl+C on when nothing is selected.
  GCONF="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  GBIND='keybind = performable:ctrl+c=copy_to_clipboard'
  if [[ -d /Applications/Ghostty.app ]]; then
    if grep -qsF "$GBIND" "$GCONF"; then
      ok "Ghostty: Ctrl+C copies selected text"
    elif ask "Let Ctrl+C copy selected text in Ghostty (with nothing selected it still stops Claude)?"; then
      mkdir -p "$(dirname "$GCONF")"
      printf '\n# Added by iroost/install.sh: Ctrl+C copies a selection, and is Ctrl+C otherwise.\n%s\n' "$GBIND" >>"$GCONF"
      ok "Ghostty: Ctrl+C copies selected text (reload Ghostty's config, Cmd+Shift+,)"
    fi
  fi
fi

# iroost remote (the panel in a browser on your tailnet) needs ttyd, Go (to build its gateway) and Tailscale; the
# panel works without them. Tailscale is a system VPN app: never installed from here. remote is set when they were
# there or the answer was yes: the gateway is built only then (a built gateway counts as a set-up remote in doctor).
remote=
if have ttyd && have go; then ok "ttyd and Go"; remote=1
elif ask "Install ttyd and Go for iroost remote (the panel in a browser on your tailnet)?"; then
  remote=1
  for t in ttyd go; do
    have "$t" && { ok "$t"; continue; }
    pkg=$t
    if [[ $t == go ]] && [[ $OS != Darwin ]]; then
      if have apt-get; then pkg=golang-go; elif have dnf; then pkg=golang; fi
    fi
    info "installing $pkg"
    if ( pkg_install "$pkg" ) >/dev/null 2>&1; then hash -r; ok "$t installed"
    else warn "could not install $pkg: iroost remote needs it"; fi
  done
else
  info "skipped: iroost remote needs ttyd and Go"
fi
have tailscale || [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]] ||
  info "no Tailscale: iroost remote also needs it (https://tailscale.com/download)"

# The Pokémon theme (sprites beside each session, and the strip in a browser; on by default) cuts the art with curl and
# ImageMagick, through brew on macOS. Declining leaves text tags.
if have magick || have convert; then ok "ImageMagick"
elif ask "Install ImageMagick for the Pokémon sprites (on by default; without it the panel shows text tags)?"; then
  info "installing imagemagick"
  if ( pkg_install imagemagick ) >/dev/null 2>&1; then hash -r; ok "ImageMagick installed"
  else warn "could not install imagemagick: Pokémon stay as text tags (brew install imagemagick)"; fi
else
  info "skipped: the Pokémon sprites need ImageMagick (text tags until then)"
fi

# Alerts on macOS: terminal-notifier groups a session's notifications; without it the panel uses osascript.
if [[ $OS == Darwin ]]; then
  if have terminal-notifier; then ok "terminal-notifier"
  elif ask "Install terminal-notifier (groups the alert notifications per session; optional)?"; then
    info "installing terminal-notifier"
    if ( pkg_install terminal-notifier ) >/dev/null 2>&1; then hash -r; ok "terminal-notifier installed"
    else warn "could not install terminal-notifier: alerts use osascript"; fi
  else
    info "skipped: alerts use osascript"
  fi
fi

# ---- iroost itself ----------------------------------------------------------------------------------------------

step "Installing iroost"
migrate_from_lzr1_panel
chmod +x "$REPO/bin/iroost"
mkdir -p "$BIN" "$CONFIG/profiles"
chmod 700 "$CONFIG" "$CONFIG/profiles"
ln -sfn "$REPO/bin/iroost" "$BIN/iroost"
ok "$BIN/iroost → $REPO/bin/iroost"
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on your PATH yet: the shell hook below adds it" ;; esac

# iroost remote's login gateway (gateway/, Go standard library only); remote on builds it too when missing.
if [[ -z $remote ]]; then :  # declined above
elif have go; then
  # On failure, go's own last line (a Go too old says so), not the "could not build" that follows it.
  if out=$("$REPO/bin/iroost" remote build 2>&1); then ok "remote gateway built (go build)"
  else
    last=$(printf '%s\n' "$out" | grep -v -e '^iroost: ' -e '^building the gateway' | tail -1 || true)
    warn "could not build the remote gateway: ${last:-${out##*$'\n'}} (cd $REPO/gateway && go build .)"
  fi
else
  info "no Go: iroost remote builds its gateway with it (brew install go, or your distribution's golang)"
fi

if [[ -d $HOME/.claude ]] || have claude; then
  mkdir -p "$SKILLS"
  ln -sfn "$REPO/skills/iroost-profiles" "$SKILLS/iroost-profiles"
  ok "Claude Code skill: ask Claude to \"create a new iroost profile\""
fi

# ---- shell hook -----------------------------------------------------------------------------------------------------

if [[ $SHELL_HOOK == 1 ]]; then
  step "Shell hook"
  autoopen=0
  if [[ $OS == Darwin && ( -d /Applications/Ghostty.app ) ]] && ask "Open the panel automatically when you open Ghostty?"; then autoopen=1; fi
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f $rc || $rc == "$HOME/.zshrc" ]] || continue
    remove_hook "$rc"
    {
      echo "$HOOK_BEGIN"
      echo "# Managed by iroost/install.sh; ./install.sh --uninstall removes it."
      echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
      echo "# cl-<profile>-opus / -sonnet / -agy / -opencode NAME: start a session on a profile without opening the panel"
      echo 'for _p in ${XDG_CONFIG_HOME:-$HOME/.config}/iroost/profiles/*.conf; do'
      echo '  [ -e "$_p" ] || continue; _p=${_p##*/}; _p=${_p%.conf}'
      echo '  eval "cl-$_p-opus() { iroost start $_p opus \"\$@\"; }; cl-$_p-sonnet() { iroost start $_p sonnet \"\$@\"; }"'
      echo '  eval "cl-$_p-agy() { iroost start $_p agy \"\$@\"; }; cl-$_p-opencode() { iroost start $_p opencode \"\$@\"; }"'
      echo 'done; unset _p'
      echo "# cl-opus / cl-sonnet [claude args], cl-agy [agy args], cl-opencode [opencode args]: Claude, agy or opencode in a"
      echo "# new tmux session in this folder; the panel lists it inside a profile's repositories folder. Your own,"
      echo "# defined earlier in this file, wins."
      echo 'type cl-opus >/dev/null 2>&1 || function cl-opus { iroost run --model opus "$@"; }'
      echo 'type cl-sonnet >/dev/null 2>&1 || function cl-sonnet { iroost run --model sonnet "$@"; }'
      echo 'type cl-agy >/dev/null 2>&1 || function cl-agy { iroost run --agy "$@"; }'
      echo 'type cl-opencode >/dev/null 2>&1 || function cl-opencode { iroost run --opencode "$@"; }'
      if [[ $autoopen == 1 && $rc == "$HOME/.zshrc" ]]; then
        echo "# Opens the panel in the first Ghostty shell; IROOST_PANEL=0 (in ~/.zshenv) turns it off."
        echo 'if [[ -o interactive && $TERM_PROGRAM == ghostty && ${IROOST_PANEL:-1} == 1 && -z $TMUX ]] &&'
        echo '   ! pgrep -f "iroost _panel" >/dev/null; then'
        echo '  iroost open'
        echo 'fi'
      fi
      echo "$HOOK_END"
    } >>"$rc"
    ok "hook in $rc"
  done
fi

# ---- first profile --------------------------------------------------------------------------------------------------

# A profile is one machine whose Claude Code sessions the panel lists. The first one is this computer: the name comes from
# its hostname and the folder from the usual places for repositories, so most of the time it is Enter, Enter.
ask_no() { [[ $YES == 1 ]] && return 1; local r; read -r -p "  $1 [y/N] " r </dev/tty || return 1; [[ $r == [Yy]* ]]; }
prompt() {  # prompt VAR "question" default: Enter takes the default
  local r; read -r -p "  $2 [$3]: " r </dev/tty || r=; printf -v "$1" '%s' "${r:-$3}"
}
first_profile() {
  local hn name n dir pick i=0 repos
  local -a cands=()
  hn=$(hostname -s 2>/dev/null | tr '[:upper:]_' '[:lower:]-' | tr -c 'a-z0-9-\n' '-')
  [[ $hn == [a-z0-9]* ]] || hn=my-computer
  for dir in "$HOME/github" "$HOME/Github" "$HOME/GitHub" "$HOME/code" "$HOME/Code" "$HOME/dev" "$HOME/Developer" \
             "$HOME/src" "$HOME/projects" "$HOME/Projects" "$HOME/work" "$HOME/repos" "$HOME/Documents/GitHub"; do
    [[ -d $dir ]] || continue
    for n in "${cands[@]+"${cands[@]}"}"; do [[ $n -ef $dir ]] && continue 2; done  # github and Github: one folder on a Mac
    cands+=("$dir")
  done
  info "A profile is one machine whose Claude Code sessions the panel lists. This computer first:"
  if [[ $YES == 1 ]]; then
    name=$hn
    [[ ${#cands[@]} -gt 0 ]] && repos=${cands[0]} || repos=
  else
    prompt name "Name for this computer" "$hn"
    if [[ ${#cands[@]} -gt 0 ]]; then
      info "Where do your repositories live? (the panel lists the sessions started inside this folder)"
      for dir in "${cands[@]}"; do i=$((i + 1)); info "  $i) $dir ($(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ') folders)"; done
      info "  or type another folder"
      prompt pick "Choose" 1
      if [[ $pick == [0-9]* && $pick -ge 1 && $pick -le ${#cands[@]} ]]; then repos=${cands[$((pick - 1))]}; else repos=$pick; fi
    else
      read -r -p "  Folder with your repositories (e.g. ~/code): " repos </dev/tty || repos=
    fi
  fi
  repos=${repos/#\~/$HOME}
  if [[ -z $repos ]]; then
    info "no repositories folder found: run 'iroost profile add' when you know it (it asks, with suggestions)"
    return 0
  fi
  if "$BIN/iroost" profile add "$name" --local --repos "$repos"; then
    ok "profile $name created (this computer)"
  else
    warn "profile not created: run 'iroost profile add' later (it asks, with suggestions)"
  fi
}
step "Profiles"
if compgen -G "$CONFIG/profiles/*.conf" >/dev/null; then
  "$BIN/iroost" profile list | sed 's/^/  /'
elif [[ -t 0 || $YES == 1 ]] && ask "Create your first profile now (this computer)?"; then
  first_profile
else
  info "none yet: run 'iroost profile add' (it asks, with suggestions), or ask Claude to create a new iroost profile"
fi
# More machines are the same: a server over SSH takes a user@host and, if you use one, a key.
if [[ -t 0 && $YES == 0 ]] && compgen -G "$CONFIG/profiles/*.conf" >/dev/null &&
   ask_no "Add another machine (a server over SSH) now?"; then
  while :; do
    "$BIN/iroost" profile add || warn "profile not created: run 'iroost profile add' later"
    ask_no "Add one more?" || break
  done
fi

# ---- GitHub ---------------------------------------------------------------------------------------------------------

step "GitHub (your pull requests under the sessions)"
if ! have gh; then
  info "no gh: the panel falls back to your SSH key's account (public PRs only)"
elif gh auth status >/dev/null 2>&1; then
  ok "gh is signed in as $(gh api user -q .login 2>/dev/null)"
elif [[ -t 0 && $YES == 0 ]] && ask "Sign in to GitHub now (gh auth login), so the panel lists your pull requests?"; then
  gh auth login </dev/tty || warn "not signed in: run 'gh auth login' later"
else
  info "not signed in: run 'gh auth login' to list your pull requests"
fi

[[ -t 1 ]] && "$BIN/iroost" splash --install || true

step "Checking everything"
"$BIN/iroost" doctor || warn "fix the items marked ✗ above (docs/troubleshooting.md explains each)"

step "Done"
info "1. open a new terminal (or: source ~/.zshrc), then run: iroost open"
info "2. start a session: n (Opus), s (Sonnet), a (Agy) or c (opencode) in the panel, or click [≡ menu]; click a session to see it"
info "3. the Pokémon theme is on: p picks a session's Pokémon, [≡ menu] in the footer turns the theme on or off"
info "4. the panel in a browser or on your phone: iroost remote on (needs Tailscale; docs/remote.md)"
info "keys: iroost keys · profiles: iroost profile help · anything wrong: iroost doctor"
