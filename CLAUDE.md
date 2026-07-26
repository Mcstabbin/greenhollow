# Ocarina — project context for AI assistants

3D Zelda-like action-adventure. Godot 4.7.1 (Standard build, **not** .NET), GDScript,
Forward+ renderer, Windows desktop. Single-player, local. Built for learning.

Godot lives at `C:\tools\godot\Godot_v4.7.1-stable_win64.exe`
(use the `_console.exe` variant when you need stdout).

---

## Rule 1: Steal from proven templates — every time, not once

**Before building ANY system, level, or mechanic, go find a real, well-regarded,
actively-maintained project that already solved it, and read how they did it.**
Not a blog post, not a tutorial fragment, not a Reddit answer — a shipped,
iterated-on codebase with stars, recent commits, and real users. Prefer a project
revised over years to one posted once.

**This is a recurring obligation, not a one-time setup step.** Search GitHub and
the Godot Asset Library again at the start of every new feature. Combat, save
systems, dialogue, room transitions, enemy AI, inventory, Z-targeting — each one
has a mature open-source implementation worth reading *before* the first line
gets written. Re-check even for things looked at before; these projects move.

Do it *first*, not after getting stuck. The goal is to inherit structure, naming,
and node layout that already survived contact with real users, and to follow
quality patterns rather than reinventing worse ones. When something looks
hand-rolled here and a standard pattern exists, the standard pattern wins.

Concrete checklist for any new feature:
1. Search GitHub (`godot 4 <feature>`, sort by stars, filter to recent pushes).
2. Check [awesome-godot](https://github.com/godotengine/awesome-godot) and the
   [Asset Library](https://godotengine.org/asset-library/asset) for an addon that
   already does it — an actively-maintained addon beats bespoke code.
3. Check the [official demo projects](https://github.com/godotengine/godot-demo-projects)
   for the engine-idiomatic version.
4. Read at least one real implementation end-to-end before designing ours.
5. Name the source in the commit message.

Prefer permissive licences (MIT / CC0 / Apache-2.0) and record the licence file in
the repo alongside anything vendored.

### 1a. Language- and engine-level pattern sources

Write GDScript the way good GDScript is written. Consult these when choosing how
to express something, not just what to build:

- [Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
  and [best practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/index.html) — naming,
  static typing, signal direction, when a node vs. a resource vs. an autoload
- [GDQuest](https://github.com/GDQuest) — the widest body of idiomatic Godot code
  (state machines, component composition, tool scripts)
- [awesome-godot](https://github.com/godotengine/awesome-godot) — plugins and libraries
- Signals up, method calls down. Composition over inheritance. Static types
  everywhere. Prefer engine features over hand-rolled equivalents.

### 1b. Look at real shipped games, not just code

Before designing a mechanic or a space, look at how released games actually did
it. Reference the real thing:

- **The source material first.** For any Zelda mechanic, go look at how Zelda
  does it — `C:\projects\zelda` is a playable Ocarina of Time (Ship of Harkinian).
  Play the relevant bit. Kokiri Forest's layout, the way the Deku Tree dominates
  the skyline, how the exit is gated — that's primary reference, free to study.
- Shipped Godot 3D titles for what the engine can actually carry: Cruelty Squad,
  Road to Vostok, Cassette Beasts, Brotato, Dome Keeper.
- Genre peers worth studying for stylised 3D adventure: Wind Waker, Link's
  Awakening (2019), A Short Hike, Tunic, Death's Door.

Study the *design decision*, then implement it ourselves — reference and learn
from these, never copy their assets or code.

Known-good sources for this project, in order of usefulness:

| Source | Use it for |
|---|---|
| [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) (MIT) | Level scene layout, prop-scene conventions, CC0 art. **Already the basis for this project's structure.** |
| [gdquest-demos/godot-4-3d-third-person-controller](https://github.com/gdquest-demos/godot-4-3d-third-person-controller) (MIT) | AnimationTree/state-machine patterns, melee combat, camera rigs |
| [godotengine/awesome-godot](https://github.com/godotengine/awesome-godot) | Index — check here before searching the open web |
| [Godot official demo projects](https://github.com/godotengine/godot-demo-projects) | Canonical engine-idiomatic usage of any node |
| [Phantom Camera](https://phantom-camera.dev/) | Cinemachine-style camera work (consider at Z-targeting) |

Concretely: the level scene follows Kenney's `Main -> World -> instanced prop
scenes` layout, and props are `.tscn` wrappers around a `.glb` with their own
`StaticBody3D` + collision. That came from reading `scenes/main.tscn` in their
repo, not from inventing it.

When you adopt a pattern, say which project it came from in the commit message.

## Rule 2: Space before systems

No stat, inventory dictionary, damage formula, XP curve, or save schema exists
until a space is fun to walk in. This project's predecessor
(`C:\projects\video_game`) built a 27-skill RPG system and a character sheet
before it had a single designed room, and was abandoned in a day. Do not repeat
that. No backend, no multiplayer, no database, no auth — ever.

## Rule 3: Verify by running, not by reasoning

Hand-authored `.tscn` and shader code is easy to get subtly wrong. Every visual
or behavioural change gets checked by actually running the engine:

- **Behaviour** — a throwaway test driven with `Input.action_press`, run
  **headless**. Headless is mandatory: a windowed run captures the real mouse
  and silently rotates the camera mid-test.
- **Anything touching an autoload must run as a SCENE**
  (`godot --headless --path . res://_test.tscn`), not via `--script`. Autoloads
  are *not* instantiated when a bare script is the main loop, so `GameState`
  resolves to null and the test spins forever.
- **Screenshots are for judging feel, not for identifying geometry.** Twice now
  a "fix had no visible effect" turned out to be me misreading which object a
  region of the image was. If a change should have moved pixels and didn't,
  stop editing and go query the scene tree for real positions and sizes.
- **Looks** — run windowed, `root.get_texture().get_image().save_png(...)`, then
  actually look at the PNG.
- Measure before theorising. Several bugs this project hit (SpringArm pitch sign,
  missing texture, non-looping clips) were diagnosed in one step by printing real
  values, after wrong guesses.

Delete throwaway scripts when done, and their orphaned `.uid` files.

## Rule 4: Commit every session

A repo whose last commit is day one is the failure signature.

---

## Engine gotchas already paid for

- `Transform3D(...)` in `.tscn` text is **row-major**.
- `SpringArm3D` places children along **+Z**; negative `rotation.x` raises the camera.
- glTF clips import with `loop_mode = NONE`. Force `LOOP_LINEAR` for locomotion.
- Kenney `.glb` files reference `Textures/colormap.png` by **external URI**. Copy the
  `Textures/` folder too, and delete `.godot/imported` + the `.import` file to force
  a re-import — copying the texture alone is not enough.
- Kenney models import with standard shading; switch materials to toon to match.
- Godot's own `--import` won't notice a changed *external* dependency.

## Layout

```
actors/player/     player.tscn + player.gd   (controller, camera, anim state)
art/materials/     shared toon StandardMaterial3D resources
art/models/        .glb + Textures/colormap.png (Kenney, CC0/MIT)
art/shaders/       outline_post.gdshader (screen-space edge detect)
world/props/       prop .tscn wrappers (mesh + StaticBody3D + collision)
world/rooms/       level scenes
ui/                debug_overlay, HUD
```

Art direction: Wind Waker — flat colour, toon shading, black outlines. No PBR, no
textures beyond Kenney's colormap atlas, no SDFGI/SSR/volumetrics (the dev machine
is an Intel UHD 770 iGPU with no discrete card).
