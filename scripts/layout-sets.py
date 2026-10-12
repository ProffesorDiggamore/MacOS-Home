#!/usr/bin/env python3
"""Writes a widgets.json that places a given set of widgets on a grid (used by smoke-test.sh).

Usage: layout-sets.py <set-number> <screen-width> <screen-height> <output-path>
"""
import json
import sys
import uuid

UNIT, GAP, MARGIN, MENU_BAR = 164, 16, 20, 25

# (kind, size, column, row, extra config)
SETS = {
    1: [
        ("clock", "small", 0, 0, {}), ("analogClock", "small", 1, 0, {}), ("worldClock", "medium", 2, 0, {}),
        ("calendar", "small", 4, 0, {}),
        ("countdown", "small", 0, 1, {}), ("yearProgress", "medium", 1, 1, {}), ("cpu", "small", 3, 1, {}),
        ("gpu", "small", 4, 1, {}),
        ("memory", "small", 0, 2, {}), ("storage", "small", 1, 2, {}), ("network", "medium", 2, 2, {}),
        ("battery", "small", 4, 2, {}),
    ],
    2: [
        ("systemStats", "medium", 0, 0, {}), ("topProcesses", "medium", 2, 0, {}), ("systemInfo", "small", 4, 0, {}),
        ("claude", "medium", 0, 1, {}), ("appShortcuts", "medium", 2, 1, {}), ("quickActions", "small", 4, 1, {}),
        ("focusTimer", "small", 0, 2, {}),
        ("note", "small", 1, 2, {"text": {"string": {"_0": "Youth group at 7\nFinish chem lab ✏️"}}}),
        ("weather", "small", 2, 2, {"city": {"string": {"_0": "Dallas"}}}),
        ("verse", "medium", 3, 2, {}),
    ],
    3: [
        ("cpu", "large", 0, 0, {}), ("claude", "large", 2, 0, {}), ("moonPhase", "small", 4, 0, {}),
        ("nowPlaying", "small", 4, 1, {}),
        ("weather", "medium", 0, 2, {"city": {"string": {"_0": "Tokyo"}}}),
        ("reminders", "small", 2, 2, {}), ("folder", "small", 3, 2, {}), ("photo", "small", 4, 2, {}),
    ],
}


def main():
    number, width, height, out = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    top = height - MENU_BAR - MARGIN
    records = []
    for kind, size, column, row, config in SETS[number]:
        records.append({
            "id": str(uuid.uuid4()).upper(),
            "kind": kind,
            "size": size,
            "x": MARGIN + column * (UNIT + GAP),
            "y": top - row * (UNIT + GAP),
            "config": {"values": config},
        })
    with open(out, "w") as handle:
        json.dump(records, handle, indent=2)


if __name__ == "__main__":
    main()
