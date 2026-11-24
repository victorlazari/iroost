# For AI assistants

- Asked to **create, register or set up an iroost profile**: follow [docs/profiles.md](docs/profiles.md)
  exactly. Ask for the name, the target and the repositories folder; never guess them; confirm before running
  `iroost profile add`.
- Profiles (`~/.config/iroost/profiles/*.conf`) hold hosts and key paths: never copy them into this repository,
  commit them, or print key contents.
- The code is zsh (`bin/iroost`, `lib/splash.zsh`) and bash (`install.sh`, which must run on macOS's bash 3.2).
  Check with `zsh -n bin/iroost lib/splash.zsh` and `bash -n install.sh`.
- Scripts sent to a profile's machine go through `on` as POSIX `sh`: no bashisms or zsh syntax inside them.
- Asked to **fix a problem with the panel**: run `iroost doctor` first, then follow
  [docs/troubleshooting.md](docs/troubleshooting.md). Add any new problem and its fix there.

# Releases

- Every commit merged into `main` is released by `.github/workflows/release.yml` (tag `vX.Y.Z` + GitHub release).
  The bump comes from the squash-merge title: `type!:` major, `feat` minor, anything else patch. Rules and tests:
  `.github/scripts/next-version.sh`, `tests/next-version.sh`.
