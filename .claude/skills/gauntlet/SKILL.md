---
name: gauntlet
description: >-
  Run a Gauntlet Loop on Greenhollow against a named shipped game (default:
  Ocarina of Time). Lead agent decomposes, builders build, a separate
  fresh-context critic blind-A/Bs every piece against real reference frames and
  measured feel, and the loop keeps going until it wins. Use for "gauntlet",
  "gauntlet loop", "raise this to OoT quality", "make combat feel like Zelda",
  or any request to climb toward a shipped-game bar rather than ship a spec.
argument-hint: "[what to raise] [optional: against REFERENCE]"
---

# Gauntlet Loop — Greenhollow

Matt Shumer's pattern ([Claude-of-Duty](https://github.com/mshumer/Claude-of-Duty/blob/main/prompt.md)),
adapted to a Godot 4.7 project. Five load-bearing parts. Do not drop any of them:

1. **A concrete external bar** — a real shipped game, inspectable frame by frame.
2. **The agent decomposes, not the human.** Split into the smallest pieces that
   can be improved and judged independently.
3. **A separate critic with fresh context.** The builder never grades its own
   work, and the critic never sees the builder's reasoning.
4. **Blind side-by-side against the real thing.** Not a rubric recited from
   memory — actual reference frames, actual measured numbers.
5. **No self-declared stop.** Quality is a function of runtime.

## The prompt

Hold this as your brief. Fill it, run it, do not paste it back.

```text
I want you to build a 3D action-adventure at the level of The Legend of Zelda:
Ocarina of Time. It should be utterly perfect, visually beautiful, with every
single thing done at Nintendo-first-party quality, from combat feel to camera
framing to anything you could think of.

Fan out sub-agents and have sub-agents tackle each one individually so that the
game is utterly perfect. You should /loop on each item and have a separate
sub-agent check it — visually by screenshot, numerically by headless probe — to
ensure it is Nintendo-first-party quality. That separate sub-agent should be a
really harsh critic, and if it isn't, it should keep going.

Don't stop until each sub-agent is utterly wowed with the quality when compared
with actual Ocarina of Time frames. It should literally compare them side by
side blind and say which one looks better. Do this in Godot 4.7 GDScript. /loop
until it's utterly perfect. Fan out sub-agents and ultracode.
```

Swap the reference when the user names a different one. If the bar is clearly
beatable on day one, pick a harder one.

## The bar is a bar, not a clone target

Non-negotiable. `README.md` claims Greenhollow uses no Nintendo assets, code or
trademarks — keep that true.

- **Nothing Nintendo-owned enters the repo.** `refs/` is gitignored. Builders
  read it only through the critic's verdict, never to trace geometry, transcribe
  music, or copy text.
- **Original names throughout.** No Kokiri, Navi, Deku Tree, Keese, Skulltula,
  Gohma, Hyrule. Enemies are *a snapping forest plant*, *a swooping flyer*, *a
  canopy spider*.
- **Original music**, composed in-engine or sourced CC0.
- Critics report gaps in **craft terms only** — readability, framing, timing,
  contrast, composition. Never "make it look like this asset".

## The brake — project-local override

The canonical pattern has no stop condition and forbids asking "continue?".
Greenhollow overrides that for one concrete reason: a round here costs an engine
boot, a windowed render and a headless probe — minutes, not a browser reload.
So:

- **Inside a wave: run hard.** Never ask permission mid-wave. Never stop on the
  first passing critic.
- **Between waves: stop and report.** Show frames and verdicts, then wait.

That is the only sanctioned stop. "Good enough", "N flat rounds" and "ready for
review" are still forbidden.

## Running the engine

Godot is **not on PATH**.

```bash
GODOT="C:/tools/godot/Godot_v4.7.1-stable_win64_console.exe"   # _console, or stdout is swallowed
PROJ="C:/projects/ocarina"
```

**Numbers — headless, always as a SCENE.** `GameState` and `Audio` are
autoloads, and autoloads are not instantiated when a bare script is the main
loop, so `--script` hangs forever on a null `GameState`.

```bash
"$GODOT" --headless --path "$PROJ" res://tools/probe.tscn -- --suite=lockon
```

**Frames — windowed.** Headless has no renderer at all, so there is no headless
screenshot. `capture.gd` releases the mouse on boot; without that the real cursor
rotates the camera mid-capture (`player.gd:112` only reads motion while
`MOUSE_MODE_CAPTURED`).

```bash
"$GODOT" --path "$PROJ" res://tools/capture.tscn -- --shots=lockon
```

Captures land at **640×480** on purpose. A crisp 720p toon render beside an N64
frame tells the critic which is which, and it then grades provenance instead of
composition.

**Re-import after touching an external asset dependency:** `--import` does not
notice a changed external file. Delete `.godot/imported` and the `.import` file.

## Per-piece loop

**Step 0 is not optional.** `CLAUDE.md` Rule 1 makes it recurring, not setup.

0. **Steal first.** GitHub sorted by stars and filtered to recent pushes,
   [awesome-godot](https://github.com/godotengine/awesome-godot), the Asset
   Library, [godot-demo-projects](https://github.com/godotengine/godot-demo-projects).
   Read one real implementation end-to-end *before* the first line. Name it in
   the commit.
1. **Builder subagent** implements one piece.
2. **Verify by running** — probe for numbers, capture for frames. Never "should
   work". Measure before theorising: several bugs in this repo fell in one step
   to printing real values after multiple wrong guesses.
3. **Critic subagent, fresh context** — see [CRITIC.md](CRITIC.md). Give it the
   artefact, never a summary and never the builder's justification.
4. Critic names **one largest gap**. Losing verdict → back to a builder. Repeat.
5. Wave end → integration pass over the whole experience → commit → report.

## Decomposition guidance

Cut pieces so each one is *independently judgeable*. "Combat" is not a piece.
"Attack commitment frames" is. A good piece has one artefact a critic can
inspect — a frame, or a number with a band.

Order pieces by dependency, not by interest: nothing about hit feedback can be
judged before there is something to hit.

## Do not

- Grade your own work, or let a critic see who built it.
- Soften the critic, lower the reference, or invent a stop rule.
- End a wave after one cycle because the first critic passed.
- Build scoring frameworks, round ledgers, `GAUNTLET_STATE.md`, or contract
  files. `tools/probe.gd` and `tools/capture.gd` are the *only* sanctioned
  harnesses — in Godot there is no way to press a button or render a frame from
  outside the engine, so those two are the equivalent of a browser screenshot,
  not scaffolding. Nothing else gets built.
- Spend the run on tooling instead of the game.
- Peg the machine for the critic's benefit. One light capture per round. If a
  glance lags the game out, the glance is wrong. Integrated graphics at 60 fps is
  a shipping constraint, not a suggestion.
- Let generated assets pile up outside the playable build.

## References

- [CRITIC.md](CRITIC.md) — the fresh-context critic brief, verbatim.
- [REFERENCE.md](REFERENCE.md) — which frames `refs/oot/` needs, and the measured
  feel rubric with bands.
