#!/usr/bin/env python3
"""Assert a probe run against a committed baseline.

    godot --headless --fixed-fps 60 --path . res://tools/probe.tscn -- --suite=movement \
        | python tools/check_baseline.py tools/baselines/movement.json

Reads probe output on stdin, finds the JSON between the probe's markers, and
compares each measurement against the baseline within its stated tolerance.

Why this exists: the 302-to-530-line state machine refactor preserved all seven
movement measurements exactly, and that was verified by hand. Nothing stops the
next refactor from quietly changing how the character jumps. Feel is allowed to
change -- but deliberately, in a commit that also edits the baseline.

Exits 1 on any drift, a missing measurement, a probe timeout, or a script error
in the engine output.
"""

import json
import sys

BEGIN = "##PROBE-BEGIN##"
END = "##PROBE-END##"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_baseline.py <baseline.json>", file=sys.stderr)
        return 2

    raw = sys.stdin.read()

    # An engine-level error can coexist with well-formed probe output, so look
    # for it explicitly rather than trusting the exit code.
    for line in raw.splitlines():
        if "SCRIPT ERROR" in line or "Parse Error" in line:
            print(f"FAIL  engine reported an error:\n      {line.strip()}")
            return 1

    if BEGIN not in raw or END not in raw:
        print("FAIL  no probe output found between markers. Engine output was:")
        print("\n".join(f"      {line}" for line in raw.splitlines()[-25:]))
        return 1

    payload = json.loads(raw.split(BEGIN, 1)[1].split(END, 1)[0])
    if "error" in payload:
        print(f"FAIL  probe reported: {payload['error']}")
        return 1

    with open(sys.argv[1], encoding="utf-8") as handle:
        baseline = json.load(handle)

    measured = {m["name"]: m for m in payload.get("measurements", [])}
    expect = baseline["expect"]

    if payload.get("physics_hz") != baseline.get("physics_hz"):
        print(
            f"FAIL  physics_hz is {payload.get('physics_hz')}, baseline assumes "
            f"{baseline.get('physics_hz')}. Every timing below is meaningless "
            f"until that matches -- run with --fixed-fps 60."
        )
        return 1

    failures = []
    for name, want in expect.items():
        got = measured.get(name)
        if got is None:
            failures.append(f"{name}: MISSING from probe output")
            continue
        if got.get("timed_out"):
            failures.append(f"{name}: probe TIMED OUT (feature missing or broken)")
            continue
        drift = abs(got["value"] - want["value"])
        status = "ok  " if drift <= want["tolerance"] else "DRIFT"
        print(
            f"  {status} {name:24s} {got['value']:>10.3f} {want['unit']:5s}"
            f" (baseline {want['value']:.3f}, drift {drift:.3f},"
            f" allowed {want['tolerance']:.3f})"
        )
        if drift > want["tolerance"]:
            failures.append(
                f"{name}: {got['value']:.3f} vs baseline {want['value']:.3f} "
                f"({want['unit']}), drift {drift:.3f} > {want['tolerance']:.3f}"
            )

    unexpected = sorted(set(measured) - set(expect))
    if unexpected:
        print(f"  note  measured but not baselined: {', '.join(unexpected)}")

    if failures:
        print(f"\nFAIL  {len(failures)} measurement(s) drifted:")
        for line in failures:
            print(f"      {line}")
        print(
            "\n      If this change was intended, edit the baseline in the same "
            "commit and say why in the message."
        )
        return 1

    print(f"\nPASS  {len(expect)} measurement(s) match the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
