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
    4: [
        ("github", "medium", 0, 0, {}), ("contributions", "medium", 2, 0, {}), ("cairn", "small", 4, 0, {}),
        ("mail", "small", 0, 1, {}), ("news", "medium", 1, 1, {}), ("hackerNews", "medium", 3, 1, {}),
        ("stocks", "medium", 0, 2, {}), ("crypto", "small", 2, 2, {}), ("currency", "small", 3, 2, {}),
        ("serviceStatus", "small", 4, 2, {}),
    ],
    5: [
        ("sports", "medium", 0, 0, {"league": {"string": {"_0": "nfl"}}}), ("uptime", "small", 2, 0, {}),
        ("todo", "small", 3, 0, {}), ("weather", "tall", 4, 0, {"city": {"string": {"_0": "Dallas"}}}),
        ("habits", "medium", 0, 1, {}), ("links", "small", 2, 1, {}), ("calculator", "small", 3, 1, {}),
        ("counter", "small", 0, 2, {}), ("stopwatch", "small", 1, 2, {}), ("sunArc", "medium", 2, 2, {"city": {"string": {"_0": "Dallas"}}}),
        ("binaryClock", "small", 4, 2, {}),
    ],
    6: [
        ("flipClock", "medium", 0, 0, {}), ("wordClock", "small", 2, 0, {}), ("lavaLamp", "small", 3, 0, {}),
        ("digitalRain", "small", 4, 0, {}),
        ("aquarium", "medium", 0, 1, {}), ("nightSky", "medium", 2, 1, {}), ("lifeGame", "small", 4, 1, {}),
        ("bounce", "medium", 0, 2, {}), ("moodGradient", "small", 2, 2, {}), ("plant", "small", 3, 2, {}),
        ("dice", "small", 4, 2, {}),
    ],
    7: [
        ("palette", "medium", 0, 0, {}), ("crabPet", "medium", 2, 0, {}), ("sticker", "small", 4, 0, {}),
        ("claude", "medium", 0, 1, {"display": {"string": {"_0": "mascot"}}}), ("text", "medium", 2, 1, {}),
        ("volume", "small", 4, 1, {}),
        ("diskActivity", "small", 0, 2, {}), ("wifi", "small", 1, 2, {}), ("clipboard", "medium", 2, 2, {}),
        ("quickActions", "small", 4, 2, {}),
    ],
    8: [
        ("appShortcuts", "wide", 0, 0, {}), ("text", "tall", 4, 0, {"text": {"string": {"_0": "Be strong and of a good courage 💪"}}}),
        ("nightSky", "extraLarge", 0, 1, {}), ("clock", "small", 4, 2, {}),
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
