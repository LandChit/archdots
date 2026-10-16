# Do this

What only you can do or check, in order. Everything here was built and tested
as far as possible without touching your running desktop; these steps need the
real session. Tick them off as you go. Details for each are in TODO.md.

Your desktop runs from `~/archdots` (branch `testing`, with a local change to
`.zshrc`). All the new work is on the `rewrite` branch in `~/archdots_rewrite`.

## 1. Switch your desktop to the rewrite

- [x] Save your `.zshrc` change somewhere the new setup reads it:
  ```bash
  mkdir -p ~/.config/simplychit/local
  git -C ~/archdots diff .zshrc          # see what you changed
  # copy those lines into ~/.config/simplychit/local/zshrc, then:
  git -C ~/archdots checkout -- .zshrc
  ```
- [x] Bring the `rewrite` branch into `~/archdots` and run its installer
  (update mode). Have a TTY ready (Ctrl+Alt+F2) in case the session needs a
  hand:
  ```bash
  git -C ~/archdots fetch ~/archdots_rewrite rewrite:rewrite
  git -C ~/archdots checkout rewrite
  ~/archdots/install.sh update
  ```
  It installs the new packages (quickshell, upower, hypridle, the zsh
  plugins), moves your untracked files across the `home/` move, relinks,
  removes the old fabric shell's venv, and disables hyprpolkitagent's unit
  (it becomes the fallback). Say yes to `tlp-pd` if it asks.
- [x] Log out and back in.

**Going back** if something is badly wrong (from a TTY if needed):
```bash
stow -D -d ~/archdots -t ~ home          # unlink the new layout
git -C ~/archdots checkout testing
cd ~/archdots && stow --restow .         # old layout
~/archdots/install.sh update             # rebuilds fabric's venv
systemctl --user enable --now hyprpolkitagent
```

## 1b. The new name (SimplyChit)

The update moves everything named archdots on its own. Afterwards:

- [ ] The update printed "moved ~/.config/archdots to ~/.config/simplychit"
  (and the same for `~/.local/state`), with no "left in place" warning
- [ ] `qs list -c simplychit` shows the shell; `qs list -c archdots` shows nothing
- [ ] `ls -l ~/.local/bin ~/.config/quickshell ~/.themes`: no links named
  archdots left
- [ ] GTK apps still have the theme (`gsettings get
  org.gnome.desktop.interface gtk-theme` is `'simplychit'`)
- [ ] Optional, outside the repo: rename the GitHub repo to `simplychit`
  (GitHub redirects the old URL), then change `REPO_URL_DEFAULT` in
  install.sh and the two URLs in README.md. Renaming your `~/archdots`
  folder is optional too: run `stow -D -d ~/archdots -t ~ home` first, move
  it, then `install.sh update` from the new place

## 2. Check the basics (phase 1)

- [x] zsh: autosuggestions (grey text as you type) and syntax colours work
- [x] `pkexec true` asks for your password (in the shell's dialog, see 4)
- [x] Idle: leave the machine and watch dim → lock → screens off. On battery
  it happens sooner (1/2/2.5 min)
- [ ] SUPER+SHIFT+I: a "Staying awake" notification and a coffee mark in the
  bar; press again to undo
- [x] Your own settings in `~/.config/simplychit/local/` (zshrc,
  alacritty.toml) and `~/.config/gtk-{3,4}.0/` still apply

## 3. Check the layout (phase 2)

- [ ] `git -C ~/archdots status` is clean apart from your own changes
- [x] Your old `~/.config/hypr/config/custom/*.lua` still applies (it is
  read before `~/.config/simplychit/hypr/`); move it there when convenient
- [ ] A bind changed with `bind.rebind` in
  `~/.config/simplychit/hypr/keybind.lua` replaces the default (does not add a
  second one)

## 4. Check the shell (phases 3 and 4)

- [ ] The bar, wallpaper and every panel come up at login
  (`qs -c simplychit ipc show` lists 12 targets)
- [x] `notify-send hi` shows a shell card
- [x] `pkexec true` shows the shell's polkit dialog
  (`qs -c simplychit ipc call polkit registered` prints `true`)
- [x] Volume keys show the OSD; brightness keys change brightness
- [x] Power profiles toggle in the control centre (needs `tlp-pd` running:
  `sudo systemctl enable --now tlp-pd`)
- [ ] Wi-Fi: join a network that needs a password, from the control centre
- [ ] Bluetooth: scan and pair something, from the control centre
- [ ] Audio tab: switch the output; one app's own volume
- [x] Wallpaper: SUPER+W, pick one (re-themes live); Shift+Enter sets it on
  one screen only
- [x] Launcher: `=2+2`, `/somefile`, `@`, `>` (try "Light mode", then back)
- [x] Caps Lock / Num Lock and a VPN coming up show toasts
- [ ] A special workspace shows its chip in the bar
- [ ] On battery: set `battery.lowPercent` above the current charge in
  `~/.config/simplychit/settings.json` to see a warning; the 30 s countdown at
  `battery.actionPercent` (Cancel works)
- [x] An external monitor's brightness with `ddcutil` installed (needs the
  `i2c-dev` module and the `i2c` group)
- [x] Lock screen (optional): `qs -c simplychit ipc call lock preview`, then
  `"lock": {"enabled": true}` in settings.json, with a TTY ready. Recovery
  steps are at the top of `~/.config/quickshell/simplychit/modules/lock/Lock.qml`

## 5. Check the settings app (phase 5)

Open it with SUPER+, (comma). Every page writes
`~/.config/simplychit/settings.json`; keep a copy first
(`cp ~/.config/simplychit/settings.json{,.bak}`) so you can go back.

- [x] SUPER+, opens a floating "SimplyChit settings" window; the launcher's `>`
  Settings and the gear in the control centre open it too
- [x] The standalone copy opens while the shell runs or not:
  `qs -p ~/.config/quickshell/simplychit/settings.qml`
- [~] **Displays** (have a TTY ready the first time):
  - [x] Drag a screen to a new place, Apply: a "Keep these display
    settings?" card shows on every screen. Do nothing: after 15 s it goes
    back on its own
  - [x] Apply again and press Keep: the layout stays after a logout and login
  - [ ] Change the mode or the scale, Apply, Revert
  - [ ] Identify shows each screen's name on it
  - [x] Unplug and replug the external screen: the kept layout comes back
  - [ ] Put workspace 2 on the external screen; it movexs there
- [x] **Appearance**: change the opacity (the bar and panels get more
  see-through), light/dark, the wallpaper folder
- [x] **Bar**: move an island to the other side, remove one, add it back;
  turn the bar off on one screen
- [x] **Idle & power**: set the AC lock to 1 minute, wait a minute
  without touching anything: the screen locks. Set it back
- [ ] **Default apps**: change the terminal, Apply; SUPER+RETURN starts the
  new one
- [ ] **Notifications**: set a do-not-disturb schedule that covers now: the
  bar shows the DND mark within 30 s; turn the schedule off
- [ ] **Input**: add a second layout (`us,de`), Apply; the keyboard-layout
  toast shows when you switch. Touchpad options change after Apply
- [ ] **Keybinds**: give one bind new keys, Apply; the new keys work and
  the old ones don't. Turn one off, then Reset both. SUPER+/ shows the new keys
- [x] **About**: the doctor list is all green apart from things you don't
  use. Also from a terminal: `simplychit doctor`
- [ ] Break the file on purpose (delete a `}` in settings.json), then
  `hyprctl reload`: a notification names the line, nothing crashes, and the
  settings app refuses to save over it. Fix it and everything comes back

## 6. Check the installer, settings checks and greeter (phase 6)

- [ ] `simplychit check-settings` says "fine". Then misspell a key in
  settings.json (`"showCPU"`): a toast "settings.json: 1 problem … did you
  mean showCpu?" shows as you save. Fix it
- [ ] Optional, editor completion: add
  `"$schema": "../quickshell/simplychit/config/settings.schema.json"` as the
  first key of settings.json and open it in VS Code
- [ ] If you have a VM or a spare machine with **another distribution**
  (EndeavourOS, CachyOS, Garuda, Manjaro): run the installer there. "Looking
  at this system" names it and the AUR helper it found; a GDM/LightDM or
  iwd/systemd-networkd setup is asked about (answer no first, then yes on a
  second run)

**The greeter.** Already tested in a fresh VM (TODO.md has what was
covered). `hypr-vm`'s disk is gone; the test VM is in
`~/.cache/simplychit-greeter-vm/` (`boot.sh` starts it; about 9 GB, delete the
folder when done). Left for you: the buttons, and real hardware. In a VM
first if you want to see it yourself:

- [ ] Snapshot the VM first:
  `virsh -c qemu:///session snapshot-create-as hypr-vm before-greeter`
- [ ] In the VM: get the `rewrite` branch, then
  `./install.sh install --greeter`. It shows `/etc/greetd/config.toml`
  before writing it, then asks to switch the login screen (default no)
- [ ] Before saying yes: check a text login works (Ctrl+Alt+F2), then come
  back (Ctrl+Alt+F1)
- [ ] Say yes and reboot. The greeter shows your wallpaper and colours:
  - [ ] a wrong password says "Wrong password"; the right one starts Hyprland
  - [ ] the session button cycles the sessions; the last user and session are
    remembered at the next boot
  - [ ] Restart and Shut down work
- [ ] Undo it from a console: `sudo systemctl disable greetd && sudo systemctl
  enable sddm && sudo reboot`: SDDM is back. If anything goes wrong,
  `virsh -c qemu:///session snapshot-revert hypr-vm before-greeter`
- [ ] Only after all that: the same on real hardware, with a TTY ready

## 7. Check phase 7 and the extras

The update installs the new packages (khal, vdirsyncer, btop, wf-recorder,
qrencode, zbar, sound-theme-freedesktop, and python-pywalfox if you take the
AUR list). Then:

- [ ] Calendar: set up vdirsyncer + khal (CUSTOMIZING.md, Calendar), then
  click the clock: today's events are under the month; click another day.
  `simplychit events` prints what the panel sees
- [ ] Lock the screen (hyprlock): the input field and clock use the
  wallpaper's colours, and the field turns the accent colour while it checks
  the password. Change the wallpaper (SUPER+W) and lock again: the colours follow
- [ ] VS Code: pick the colour theme "Wal" (Ctrl+K Ctrl+T); it follows the
  wallpaper from then on
- [ ] Browser: add the Pywalfox add-on (addons.mozilla.org) in Zen, press
  "Fetch Pywal colors" once
- [ ] `btop`: in the wallpaper's colours
- [ ] SUPER+SHIFT+N: the notepad; type, close, reopen: the text is still there
- [ ] SUPER+SHIFT+R, drag a box: a red dot and a timer in the bar; click it.
  "Recording saved" names a file in ~/Videos/recordings that plays. Try
  "Record screen" from the screenshot menu, and `recording.audio: "desktop"`
- [ ] Launcher `>` "QR code of the clipboard" with a link copied: your phone
  reads it. "Scan a QR code" on a code on screen copies what it says
- [ ] Sounds: a tick when you change the volume (once per press, not a burst
  while held) and a chime on `notify-send hi`; both switch off on the
  Notifications page; nothing under do not disturb

## When it all works

- [ ] Merge `rewrite` into `main` (and push) when you are happy with it
