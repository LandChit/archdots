# SimplyChit rewrite

## Rules

- Use the `rewrite` branch for all changes.
- Update [TODO.md](TODO.md) after every completed task: tick it, and note
  what is left or where it moved.
- The active dotfiles are in `~/archdots`; `~/.config` and `~/.zshrc` are
  stowed from there. This repo (`~/archdots_rewrite`) is the development
  rewrite, so editing it never changes the running desktop.
- Work through TODO.md phase by phase, in order.

## Name

- The dots are **SimplyChit** (renamed from archdots). Prose and UI say
  SimplyChit; paths and ids are lowercase `simplychit` (`~/.config/simplychit/`,
  `qs -c simplychit`, `simplychit doctor`, layer namespaces `simplychit-*`).
- Not renamed: the GitHub repo URL (`LandChit/archdots`, until the owner
  renames it there) and the owner's own folders `~/archdots` (live clone) and
  `~/archdots_rewrite`. install.sh's `retire_old_name` migrates an existing
  install from the old name.

## Layout

- `home/` is the only stowed tree (`stow --dir=<repo> --target=$HOME home`).
  Paths in docs and code are `home/.config/...`; repo-only things (install.sh,
  docs, `simplychit_docker/`, `wallpapers/`, `kvantum/`, `.themes_sddm/`) sit at
  the root. The root `.stow-local-ignore` ignores everything on purpose (a
  guard against old installers' `stow .`).
- User files live in `~/.config/simplychit/` (`hypr/<module>.lua`, `local/`),
  never in the repo. GTK user files stay in `~/.config/gtk-{3,4}.0/`.
  `config/custom/` is the legacy override folder, still loaded first.
  User-facing guide: [CUSTOMIZING.md](CUSTOMIZING.md).
- `~/archdots` (live) is still on the old root layout and the fabric shell
  until it updates. In this repo fabric is gone: the shell is Quickshell,
  `home/.config/quickshell/simplychit/` (`qs -c simplychit`).

## Testing without touching the live desktop

- Nothing here is live, so test against this repo's files, not `~/.config`.
- `SIMPLYCHIT_REPO=$PWD ./simplychit_docker/runscript.sh --fast` runs install.sh
  in a container (repo mounted read-only). It ends with exit 1 at
  "could not set gtk-theme" on every commit; that is a container limit, not
  a regression. Check the post-run "repo dirtied" list stays clean.
- No passwordless sudo. To try a package, download it from the mirror into
  the scratchpad and extract it there instead of installing.
- Anything that could dim, lock, suspend or blank the screen (hypridle,
  `hl.dsp.dpms`): test with the commands swapped for `echo >> log` and
  long or harmless timeouts.

## Hyprland (Lua config)

- `hyprctl dispatch` takes a Lua expression: `'hl.dsp.dpms({ action = "disable" })'`,
  `'hl.dsp.exit()'`. The old `dpms off` form is a Lua syntax error.
- `hyprctl dispatch` answers `ok` to anything; it does not validate arguments.
- `hyprctl eval <code>` runs Lua in the live session. API stubs:
  `/usr/share/hypr/stubs/hl.meta.lua`.
- Check syntax with `luac -p`.
- Binding a combo twice keeps both binds (both fire). `hl.unbind(combo)`
  removes all of them; `config/helpers/bind.lua` has `rebind`/`remove`.
- To test a bind live, use a throwaway combo (SUPER+SHIFT+CTRL+F12, modmask 69)
  and remove it after; `hyprctl binds -j` shows `description`.
- Test the override loader without Hyprland: set `hl` to a table whose
  metatable returns a callable stub for every key, put `home/.config/hypr` on
  `package.path`, and `dofile` hyprland.lua under plain `lua` with a fake
  `HOME` holding the override files.

## Quickshell (0.3.2)

- The shell is `home/.config/quickshell/simplychit/` (README inside). Test with
  `qs -p <that path>`, which runs beside the live desktop, with a scratch
  `HOME` and every `XDG_*_HOME`.
- Notifications and polkit can't register while the live session's daemon /
  agent holds the name: run the test copy under `dbus-run-session` for
  notifications; polkit only via `ipc call polkit preview`.
- Never let a test run real `wal` against `~/.cache/wal` (re-themes the live
  desktop), real `hyprctl reload`, `wl-copy` (overwrites the clipboard), or a
  real session lock. Use scratch XDG dirs and PATH shims that echo.
- Send `qs` output to a file, not a pipe, or the log is lost when `timeout`
  stops it; `Qt.quit()` does not exit.
- Check exact APIs in `/usr/lib/qt6/qml/Quickshell/**/*.qmltypes`; the
  website docs are for older versions.
- `writeAdapter()` drops unknown keys: use `Config.set()`.
- `font.pixelSize` takes whole pixels only (load error otherwise).
- `show`/`hide` cannot be IPC function names (`qs ipc show` is a subcommand).
- `Hyprland.activeToplevel` is null until the first focus change.
- An enabled `IdleMonitor` ignores later `timeout` changes; toggle `enabled`
  to make it re-register (services/IdleTimers.qml).
- Idle tests only fire while the user is not touching the machine: put a
  fixed 3 s control `IdleMonitor` next to what is tested to tell "not idle"
  from "broken".
- Screenshot a region with `grim -g "x,y wxh"`; eDP-1 starts at x=1080.
- Nerd Font glyphs in the BMP private-use area (U+E000–F8FF) get lost when
  writing files from here. Use Material Design ones (U+F0000+), written as
  `\U000f....` escapes from Python, and check code points after writing.
- A fake `HOME` is not enough isolation: tools follow `XDG_CACHE_HOME`
  (set here), so set every `XDG_*_HOME` too, and check where a tool will
  write before storing test data. cliphist once wrote test entries into the
  real history this way. Never list the user's clipboard history.
- Drive panels with IPC (`ipc call launcher open "<text>"`), not wtype: if
  the panel has not grabbed the keyboard, wtype types into the editor.
- A handler on a property can run before bindings that depend on the same
  property update; defer with `Qt.callLater` when it reads them.
- A module folder nested inside a folder that holds QML files is not found
  (`qs.widgets.form` "not installed"); keep shared controls flat in `widgets/`.
- Don't name a component after a QtQuick type (`Row` shadowed QtQuick's).
- `parent` inside a `Connections`, or a control placed into another
  component's default property, is not the item you expect: use an `id`.
- An item's `visible` is false whenever its parent is hidden, so a Loader
  can't take its visibility from `item.visible` (stuck hidden). The bar's
  islands expose `wanted` for that.
- A settings page compiles on first open and takes over a second: wait 3 s
  or more before a screenshot.
- Monitor changes apply live with `hyprctl eval 'hl.monitor({ output =
  "desc:…", … })'`. Testing on the real screens: note the current rule
  first and `trap` a restore of it, keep the change small (move 10 px), and
  rely on the 15 s auto-revert. A scratch shell whose settings.json holds
  `displays.profiles` applies them on start: use a scratch home without them.

- cage (the greeter's compositor) has no layer-shell: a `PanelWindow` never
  shows there. The greeter is a `FloatingWindow`.
- Typing into a test with `wtype` is only safe inside a nested compositor:
  run a nested `cage` (extracted to the scratchpad with `wlroots0.20`,
  `LD_LIBRARY_PATH`) and call `wtype` from a script that cage itself runs.
  A fake greetd socket for the greeter: `scratchpad/fakegreetd.py` pattern
  in DEVELOPMENT.md ("The greeter").
- `hypr-vm` (libvirt, qemu:///session) has no disk any more. The greeter test
  VM is `~/.cache/simplychit-greeter-vm/`: Arch with the rewrite installed,
  qcow2 snapshot `base` (bare Arch, before install.sh). `./boot.sh` starts
  it headless (SSH on 127.0.0.1:2222, user tester/test, key `vmkey`;
  `qmp.py shot|type|key` for the screen and keyboard). Keep VM disks out of
  /tmp: the scratchpad is tmpfs with a quota, and filling it broke the VM.
- Hooks: a commit in the same command as `--no-aur` (any `--no-…`) is
  blocked as `--no-verify`; commit in its own command.

## Gotchas found so far

- stow folds directories. Without a real `~/.config`, it links the whole
  folder to the repo and anything created there lands in the clone.
  install.sh creates `~/.config` first.
- alacritty loads the importing file *last*, so `alacritty.toml` holds only
  the import list and the settings live in `simplychit.toml`.
- GTK 4's `gtk.css` can only import files in its own directory (flatpaks).

## Commits

Conventional commits (`feat(scope): …`, `fix(…)`, `chore(…)`), one per
sub-step, body explains why.
