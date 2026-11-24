---
name: iroost-profiles
description: Create, test, list or remove iroost profiles (the machines whose Claude Code sessions iroost shows). Use when the user asks to create, register, add or set up an iroost profile, for this computer or a server over SSH.
---

# iroost profiles

A profile is one machine whose Claude Code sessions iroost lists: this computer (`--local`) or another one
over SSH (`--ssh user@host`). Profiles cover Claude Code sessions only, for now.

Follow the full guide in `docs/profiles.md` of the iroost repository. Find it next to this skill:
`readlink -f ~/.claude/skills/iroost-profiles` (macOS: `realpath`), then `../../docs/profiles.md`.

The short version:

1. Ask, one question at a time, waiting for each answer:
   - the profile **name** (lowercase, digits, dashes; a `_` becomes a dash; check `iroost profile list` for
     clashes);
   - the **target**: this computer, or SSH with `user@host`, an optional key **file path** and an optional port
     (never ask for passwords or key contents);
   - the **repositories folder** on that machine. Always ask; suggest a path shaped like theirs, such as
     `/Users/<them>/Github/my-repositories`, and use exactly what they answer. The profile opens and lists only the
     sessions inside it, so several profiles can share one machine.
2. Show a one-line summary and get a yes.
3. Run one of:
   - `iroost profile add NAME --local --repos PATH`
   - `iroost profile add NAME --ssh USER@HOST [--key FILE] [--port N] --repos 'PATH'`
     (single-quote remote paths that start with `~`).
4. Read the `profile test` lines it prints back to the user, and fix anything marked missing with them
   (`docs/profiles.md` lists the fixes).
5. Tell them the panel shows it on its next refresh, and that new shells get `cl-NAME-opus` / `cl-NAME-sonnet`.

Never write profile files into a git repository: they hold hosts and key paths, and live in
`~/.config/iroost/profiles/`.
