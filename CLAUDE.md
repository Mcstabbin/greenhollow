# Greenhollow — project context for AI assistants

3D action-adventure. Godot 4.7.x (Standard build, **not** .NET), GDScript,
Forward+ renderer, Windows desktop. Single-player, local. Built for learning.

---

## Rule 1: Steal from proven templates — every time, not once

**Before building ANY system, level, or mechanic, go find a real, well-regarded,
actively-maintained project that already solved it, and read how they did it.**
Not a blog post, not a tutorial fragment, not a forum answer — a shipped,
iterated-on codebase with stars, recent commits, and real users. Prefer a project
revised over years to one posted once.

**This is a recurring obligation, not a one-time setup step.** Search GitHub and
the Godot Asset Library again at the start of every new feature. Combat, save
systems, dialogue, room transitions, enemy AI, inventory, lock-on — each one has
a mature open-source implementation worth reading *before* the first line gets
written. Re-check even for things looked at before; these projects move.

Do it *first*, not after getting stuck. The goal is to inherit structure, naming
and node layout that already survived contact with real users, and to follow
quality patterns rather than reinventing worse ones. When something here looks
hand-rolled and a standard pattern exists, the standard pattern wins.

Checklist for any new feature:

1. Search GitHub (`godot 4 <feature>`, sort by stars, filter to recent pushes).
2. Check [awesome-godot](https://github.com/godotengine/awesome-godot) and the
   [Asset Library](https://godotengine.org/asset-library/asset) — an actively
   maintained addon beats bespoke code.
3. Check the [official demo projects](https://github.com/godotengine/godot-demo-projects)
   for the engine-idiomatic version.
4. Read at least one real implementation end-to-end before designing ours.
5. Name the source in the commit message.

Prefer permissive licences (MIT / CC0 / Apache-2.0) and commit the licence file
alongside anything vendored.

Sources already drawn on here:

| Source | Used for |
|---|---|
| [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) (MIT) | Level scene layout (`Main -> World -> instanced props`), pickup pattern, CC0 art |
| [gdquest-demos/godot-4-3d-third-person-controller](https://github.com/gdquest-demos/godot-4-3d-third-person-controller) (MIT) | AnimationTree/state-machine patterns, camera rigs |
| [sempitern0/interaction-kit-3d](https://github.com/sempitern0/interaction-kit-3d) | Area3D-based interactable pattern |
| [awesome-godot](https://github.com/godotengine/awesome-godot) | Index — check before searching the open web |

### 1a. Language- and engine-level patterns

Write GDScript the way good GDScript is written:

- [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
  and [best practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/index.html)
- [GDQuest](https://github.com/GDQuest) — the widest body of idiomatic Godot code
- Signals up, method calls down. Composition over inheritance. Static types
  everywhere. Prefer engine features to hand-rolled equivalents.

### 1b. Look at shipped games, not just code

Before designing a mechanic or a space, look at how released games solved it.
Study the *design decision*, then implement it independently — reference and
learn, never copy assets or code, and use only legally obtained copies.

- Shipped Godot 3D titles, for what the engine carries: Cruelty Squad, Road to
  Vostok, Cassette Beasts, Dome Keeper.
- Genre peers for stylised 3D adventure: The Wind Waker, Link's Awakening (2019),
  A Short Hike, Tunic, Death's Door.

## Rule 2: Space before systems

No stat, inventory, damage formula, XP curve or save schema exists until a space
is fun to walk in. Build the room, then the systems that live in it — not the
reverse. Deep simulation layered onto a world that is still grey boxes is the
classic way a solo 3D project stalls.

Scope guards for this project: single-player and local. No backend, no
multiplayer, no database, no accounts.

## Rule 3: Verify by running, not by reasoning

Hand-authored `.tscn` and shader code is easy to get subtly wrong. Every visual
or behavioural change gets checked by actually running the engine.

The engine is **not on PATH**:

```bash
GODOT="C:/tools/godot/Godot_v4.7.1-stable_win64_console.exe"   # _console, or stdout is swallowed
```

- **Behaviour** — a throwaway test driven with `Input.action_press`, run
  **headless**. Headless is mandatory: a windowed run captures the real mouse and
  silently rotates the camera mid-test.
- **Anything touching an autoload must run as a SCENE**
  (`godot --headless --path . res://_test.tscn`), not via `--script`. Autoloads
  are *not* instantiated when a bare script is the main loop, so `GameState`
  resolves to null and the test spins forever.
- **Looks** — run windowed, `root.get_texture().get_image().save_png(...)`, then
  actually look at the PNG.
- **Measure before theorising.** Several bugs here (SpringArm pitch sign, a
  missing texture, non-looping clips, ambient being ignored) were each diagnosed
  in one step by printing real values, after several wrong guesses.
- **Screenshots judge feel, not identity.** More than once a "fix had no visible
  effect" turned out to be misreading which object a region of the image was. If
  a change should have moved pixels and didn't, stop editing and query the scene
  tree for real positions and sizes.

Delete throwaway scripts when done, along with their orphaned `.uid` files.

Two exceptions, both **permanent** and both committed — in Godot there is no way
to press a button or render a frame from outside the engine, so these are the
tooling the rest of Rule 3 assumes:

- `tools/probe.tscn` — headless, scene-based, drives input and prints measured
  numbers as JSON. `--suite=<name>`.
- `tools/capture.tscn` — windowed, releases the mouse so the real cursor cannot
  rotate the camera, saves PNGs from a JSON shot list. `--shots=<name>`.

Both are used by the `/gauntlet` skill (`.claude/skills/gauntlet/`), which runs
quality loops against a shipped-game bar.

## Rule 4: Commit every session

A repo whose last commit is day one is the failure signature.

---

## Engine gotchas already paid for

- `Transform3D(...)` in `.tscn` text is **row-major**.
- `SpringArm3D` places children along **+Z**; negative `rotation.x` raises the camera.
- A directional light only lights camera-facing (+Z normal) surfaces when
  `basis.z.z > 0`, i.e. `|rotation.y| < 90`.
- `Environment.ambient_light_sky_contribution` defaults to **1.0**, so
  `ambient_light_color` and `ambient_light_energy` are silently ignored until it
  is set to 0.
- `DIFFUSE_TOON` collapses every away-facing surface to flat ambient and turns
  dense foliage grey. Use `DIFFUSE_LAMBERT_WRAP` for foliage; the outline shader
  supplies the toon read.
- Property changes on nodes **inside an instanced `.glb`** are dropped when
  packing unless the node is owned. Build static props as plain `MeshInstance3D`
  nodes from the source meshes instead.
- glTF clips import with `loop_mode = NONE`. Force `LOOP_LINEAR` for locomotion.
- Kenney `.glb` files may reference `Textures/colormap.png` by **external URI**.
  Copy the `Textures/` folder too, then delete `.godot/imported` and the
  `.import` file to force a re-import — copying the texture alone is not enough.
- `--import` does not notice a changed *external* dependency.
- Kenney models import with standard shading; switch materials to toon to match.

## Layout

```
actors/player/     player.tscn + player.gd (controller, camera, anim states)
autoload/          GameState singleton
components/        Interactable base
items/             rupee, chest, sign, gate
art/materials/     shared toon StandardMaterial3D resources
art/models/        .glb assets (Kenney, CC0/MIT)
art/shaders/       outline_post.gdshader (screen-space edge detect)
world/rooms/       level scenes
tools/             level generators
ui/                HUD, debug overlay
```

Art direction: flat colour, toon-ish shading, black outlines. No PBR, no textures
beyond the Kenney colormap atlas. Avoid SDFGI, SSR and volumetrics — the target
is integrated graphics.
