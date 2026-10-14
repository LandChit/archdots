#!/usr/bin/env python3
"""Write the JSON schema for ~/.config/simplychit/settings.json.

Config.qml is the one list of settings: every key, its type, its default and
the comment above it. This reads it and writes config/settings.schema.json next
to it, so editors can complete and check settings.json and `simplychit doctor`
can validate it. Run it after adding or changing a setting:

    tools/gen-settings-schema.py          # rewrite the schema
    tools/gen-settings-schema.py --check  # exit 1 if it is out of date
"""

import json
import re
import sys
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "home/.config/quickshell/simplychit"
CONFIG = SHELL / "config/Config.qml"
SCHEMA = SHELL / "config/settings.schema.json"

# What the QML types cannot say. Keyed by dotted path.
ISLANDS = ["workspaces", "special", "title", "media", "resources", "clock"]
EXTRA = {
    "bar.left": {"items": {"type": "string", "enum": ISLANDS}},
    "bar.right": {"items": {"type": "string", "enum": ISLANDS}},
    "bar.titleChars": {"minimum": 1},
    "bar.mediaChars": {"minimum": 1},
    "appearance.opacity": {"minimum": 0.5, "maximum": 1},
    "battery.lowPercent": {"minimum": 0, "maximum": 100},
    "battery.criticalPercent": {"minimum": 0, "maximum": 100},
    "battery.actionPercent": {"minimum": 0, "maximum": 100},
    "battery.criticalAction": {"enum": ["suspend", "hibernate", "poweroff", "none"]},
    "theme.mode": {"enum": ["dark", "light"]},
    "theme.backend": {"enum": ["wal", "colorthief", "colorz", "haishoku", "fast_colorthief",
                               "modern_colorthief", "okthief"]},
    "wallpaper.cycleMinutes": {"minimum": 0},
    "wallpaper.transitionMs": {"minimum": 0},
    "notifications.timeout": {"minimum": 0},
    "notifications.schedule.from": {"pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"},
    "notifications.schedule.to": {"pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"},
    "input.sensitivity": {"minimum": -1, "maximum": 1},
    "keybinds.remap": {"additionalProperties": {"type": "string"}},
    "audio.scrollStep": {"minimum": 1, "maximum": 50},
    "audio.maxVolume": {"minimum": 1, "maximum": 3},
}
for side in ("ac", "battery"):
    for step in ("dim", "lock", "screenOff", "suspend"):
        EXTRA[f"idle.{side}.{step}"] = {"minimum": 0}

# Keys only Hyprland reads (hypr/config/input.lua), so Config.qml never
# declares them. Keep in step with the `known` tables there.
HYPR_ONLY = {
    "input": {
        "kb_model": {"type": "string", "description": "xkb model (Hyprland's input.kb_model)"},
        "follow_mouse": {"type": "integer", "minimum": 0, "maximum": 3,
                         "description": "Hyprland's input.follow_mouse"},
        "accel_profile": {"type": "string", "enum": ["", "flat", "adaptive", "custom"],
                          "description": "pointer acceleration"},
        "numlock_by_default": {"type": "boolean"},
    },
    "input.touchpad": {
        "scroll_factor": {"type": "number", "minimum": 0},
        "clickfinger_behavior": {"type": "boolean",
                                 "description": "two-finger click is a right click"},
        "drag_lock": {"type": "boolean"},
    },
}

TYPES = {"bool": "boolean", "int": "integer", "real": "number", "string": "string"}

OPEN = re.compile(r"^\s*property JsonObject (\w+): JsonObject \{")
LEAF = re.compile(r"^\s*(?:readonly )?property (list<string>|\w+) (\w+): (.+?)\s*$")


def default(qml_type, text):
    if qml_type == "var":
        return json.loads(text.strip("()"))
    return json.loads(text)


def parse():
    lines = CONFIG.read_text().splitlines()
    start = next(i for i, l in enumerate(lines) if "JsonAdapter" in l)
    root = {"type": "object", "properties": {}}
    stack = [root]
    path = []
    comment = []
    for line in lines[start + 1:]:
        stripped = line.strip()
        if stripped.startswith("//"):
            comment.append(stripped[2:].strip())
            continue
        m = OPEN.match(line)
        if m:
            node = {"type": "object", "properties": {}, "additionalProperties": False}
            if comment:
                node["description"] = " ".join(comment)
            stack[-1]["properties"][m.group(1)] = node
            stack.append(node)
            path.append(m.group(1))
            comment = []
            continue
        m = LEAF.match(line)
        if m and len(stack) > 1:
            qml_type, name, value = m.groups()
            if qml_type == "list<string>":
                node = {"type": "array", "items": {"type": "string"}}
            elif qml_type == "var":
                node = {"type": "object"}
            else:
                node = {"type": TYPES[qml_type]}
            node["default"] = default(qml_type, value)
            if comment:
                node["description"] = " ".join(comment)
            node.update(EXTRA.get(".".join(path + [name]), {}))
            stack[-1]["properties"][name] = node
            comment = []
            continue
        if stripped == "}":
            if len(stack) == 1:
                break
            stack.pop()
            path.pop()
        comment = []
    return root


def schema():
    root = parse()
    for where, keys in HYPR_ONLY.items():
        node = root
        for part in where.split("."):
            node = node["properties"][part]
        node["properties"].update(keys)
    return {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "SimplyChit settings (~/.config/simplychit/settings.json)",
        "description": "Generated from config/Config.qml by tools/gen-settings-schema.py; do not edit.",
        "type": "object",
        "properties": {"$schema": {"type": "string"}, **root["properties"]},
        "additionalProperties": False,
    }


def main():
    text = json.dumps(schema(), indent=2) + "\n"
    if "--check" in sys.argv:
        if not SCHEMA.exists() or SCHEMA.read_text() != text:
            print(f"{SCHEMA} is out of date: run tools/gen-settings-schema.py", file=sys.stderr)
            return 1
        return 0
    SCHEMA.write_text(text)
    print(f"wrote {SCHEMA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
