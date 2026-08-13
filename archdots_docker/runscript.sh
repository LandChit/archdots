#!/usr/bin/env bash
#
# Test archdots/install.sh in a throwaway Arch container.
#
#   ./runscript.sh                    interactive shell, repo at ~/archdots
#   ./runscript.sh --fast             structural run: no packages, ~10s
#   ./runscript.sh --full             the real thing: every package, slow
#   ./runscript.sh --hypr             --full, then start Hyprland and the shell
#                                     in a nested window, check it, screenshot
#   ./runscript.sh --ui               same, but leaves the session up so you can
#                                     click around. INSERT is the leader key.
#   ./runscript.sh --rebuild          force an image rebuild
#   ./runscript.sh -- --yes --no-aur  pass anything after -- to install.sh
#
# The repo is mounted read-only and copied to a writable path inside, so your
# working tree cannot be modified by a test and edits need no image rebuild.

set -euo pipefail

REPO="${ARCHDOTS_REPO:-$HOME/archdots}"
IMAGE="archdots-tester"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MODE="shell"
PASSTHRU=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast)    MODE="fast" ;;
        --full)    MODE="full" ;;
        --hypr)    MODE="hypr" ;;
        --ui)      MODE="ui" ;;
        --shell)   MODE="shell" ;;
        --rebuild) REBUILD=1 ;;
        --)        shift; PASSTHRU=("$@"); MODE="custom"; break ;;
        -h|--help) sed -n '3,11p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[[ -f "$REPO/install.sh" ]] || {
    echo "no install.sh at $REPO — set ARCHDOTS_REPO to the repo root" >&2
    exit 1
}

# Rebuild only when asked or when the image is missing; the base layer is ~1.7GB.
if [[ -n "${REBUILD:-}" ]] || ! docker image inspect "$IMAGE" &>/dev/null; then
    echo "==> building $IMAGE"
    docker build -t "$IMAGE" "$HERE"
fi

case "$MODE" in
    fast)   ARGS=(--yes --skip-packages --skip-venv) ;;
    full)   ARGS=(--yes) ;;
    # --no-aur on purpose: nothing in the AUR set (browser, editor, LSP, the
    # SDDM theme) affects whether the compositor and shell come up, and paru's
    # source build alone costs ~3 minutes. --full is the package-fidelity test;
    # this one is about the session.
    hypr|ui) ARGS=(--yes --no-aur) ;;
    custom) ARGS=("${PASSTHRU[@]}") ;;
    shell)  ARGS=() ;;
esac

# Nested-session plumbing. Only for --hypr, because handing a container the
# host's Wayland socket and /dev/dri is a real grant, not a default.
WL=()
if [[ "$MODE" == hypr || "$MODE" == ui ]]; then
    [[ -n "${WAYLAND_DISPLAY:-}" && -S "${XDG_RUNTIME_DIR:?}/$WAYLAND_DISPLAY" ]] || {
        echo "--hypr needs a running Wayland session on the host" >&2
        echo "  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}" >&2
        exit 1
    }
    [[ "$(id -u)" == 1000 ]] || echo "warning: host uid $(id -u) != container uid 1000; the socket may be unreadable" >&2
    # Mounted under a distinct name so it cannot collide with the socket the
    # nested Hyprland is about to create in the same directory.
    WL=(
        -v "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY":/run/user/1000/wayland-host
        --device /dev/dri
        -e XDG_RUNTIME_DIR=/run/user/1000
        -e WAYLAND_DISPLAY=wayland-host
        -e XDG_SESSION_TYPE=wayland
        -e ARCHDOTS_HYPR=1
    )
    # --ui keeps the compositor up and hands you a shell instead of tearing it
    # down after the checks.
    [[ "$MODE" == ui ]] && WL+=(-e ARCHDOTS_UI=1)
fi

echo "==> mode: $MODE ${ARGS[*]-}"

# -it only when there actually is a terminal; docker refuses otherwise, which
# would make this unusable from a script or a CI step.
TTY=()
[[ -t 0 && -t 1 ]] && TTY=(-it)
# An interactive shell is pointless without one.
if [[ ( "$MODE" == shell || "$MODE" == ui ) && ${#TTY[@]} -eq 0 ]]; then
    echo "$MODE mode needs a terminal; use --fast, --full or --hypr here" >&2
    exit 2
fi

FAST=0; [[ "$MODE" == fast ]] && FAST=1

# Docker creates a missing mount source as root-owned, which the container's
# unprivileged user then cannot write to.
mkdir -p "$HERE/artifacts"
# Stale artifacts from an earlier run would read as this run's results.
rm -f "$HERE/artifacts/hyprland.png" "$HERE/artifacts/after-retheme.png" "$HERE/artifacts/hypr.log"

# `|| rc=$?` rather than a bare `rc=$?`: under `set -e` a failing container
# would end this script before the exit code could be recorded or reported.
rc=0
docker run --rm ${TTY[@]+"${TTY[@]}"} \
    --name "archdots-test-$$" \
    -e ARCHDOTS_FAST="$FAST" \
    ${WL[@]+"${WL[@]}"} \
    -v "$REPO":/src:ro \
    -v "$HERE/checks.sh":/checks.sh:ro \
    -v "$HERE/ui-input.lua":/ui-input.lua:ro \
    -v "$HERE/artifacts":/artifacts \
    "$IMAGE" \
    bash /checks.sh ${ARGS[@]+"${ARGS[@]}"} || rc=$?

echo
echo "==> exit $rc"
[ -s "$HERE/artifacts/hyprland.png" ] && echo "==> screenshot:  $HERE/artifacts/hyprland.png" || true
[ -s "$HERE/artifacts/hypr.log" ]     && echo "==> session log: $HERE/artifacts/hypr.log"     || true
exit $rc
