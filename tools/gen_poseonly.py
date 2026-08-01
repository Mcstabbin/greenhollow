#!/usr/bin/env python3
"""Regenerate tools/shots/poseonly.json from tools/shots/legibility.json.

    python tools/gen_poseonly.py

`poseonly.json` is the legibility set with every VFX node switched off, so the
question "does the POSE alone read as an action" can be answered rather than
argued -- the test a critic settled by saying *"legibility and correctness are
inversely correlated: the effects you can't miss are the ones that read as
objects; the one that reads as a genuine action is carried by the pose."*

It exists as a generator because the file has already drifted once by hand: three
weapon pairs were added to `legibility.json` and not mirrored across, so the pose
test silently covered 7 pairs while the judged set had 10. Two shot lists that
must agree, maintained separately, is a bug waiting for a quiet round.

The transform is deliberately the whole of it: copy every shot, add
`hide_effects`. Anything that needs to differ per shot belongs in
`legibility.json` where it can be read next to the frame it describes.
"""

import collections
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "shots", "legibility.json")
TARGET = os.path.join(HERE, "shots", "poseonly.json")

COMMENT = (
    "GENERATED FROM legibility.json -- do not hand-edit; regenerate with"
    " `python tools/gen_poseonly.py` instead. The same frames with every VFX node"
    " disabled, so the question 'does the POSE alone read as an action' can be answered"
    " rather than argued. That question is the one a critic settled by saying"
    " \"legibility and correctness are inversely correlated -- the effects you can't"
    " miss are the ones that read as objects; the one that reads as a genuine action is"
    " carried by the pose.\" This file had drifted once, which is why it is now"
    " generated: three weapon pairs were added to legibility.json and not mirrored"
    " here, so the pose test silently covered 7 pairs while the judged set had 10."
    " NOTE on the lock-on pairs: `hide_effects` finds MeshInstance3D and OmniLight3D"
    " nodes under the PLAYER, so it switches off the trail, the rings and the charge"
    " glow but not the lock-on reticle, which is a Control in the HUD. That is"
    " deliberate rather than an oversight -- the reticle is not VFX carrying an action,"
    " it is the HUD stating a state, and a locked frame with the reticle removed would"
    " be answering a question nobody asked."
)


def main() -> int:
    with io.open(SOURCE, encoding="utf-8") as handle:
        doc = json.load(handle, object_pairs_hook=collections.OrderedDict)

    out = collections.OrderedDict()
    out["_comment"] = COMMENT
    shots = []
    for shot in doc["shots"]:
        copy = collections.OrderedDict(shot)
        copy["hide_effects"] = True
        shots.append(copy)
    out["shots"] = shots

    with io.open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print("wrote %s: %d shots" % (os.path.relpath(TARGET), len(shots)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
