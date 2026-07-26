# Greenhollow

A 3D action-adventure in the Zelda mould, built in **Godot 4.7** with GDScript.
Solo hobby project, made to learn gamedev.

![Godot](https://img.shields.io/badge/Godot-4.7.1-478cbf)
![Language](https://img.shields.io/badge/GDScript-355570)
![Licence](https://img.shields.io/badge/licence-MIT-green)

---

## What's in it

**Level one — the forest clearing.** An enclosed bowl of woodland with a village
of hollow-stump houses, a stream you cross by a wooden bridge, a climbable rock
lookout, and a Great Tree that owns the skyline. Roughly 1,400 nodes, holding
60 fps on integrated graphics.

**It's playable, not just walkable:**

- Rupees scattered around, auto-collected on contact
- Signs you can read
- Chests that open, one holding a small key
- A locked forest gate that consumes the key and swings open

That lock-and-key loop is the whole point — it's the atom of Zelda design, and
the smallest thing that turns a space into a level.

**Character controller** with camera-relative movement, coyote time, jump
buffering, variable jump height and asymmetric gravity. Every value that
affects feel is an `@export`, tunable live from the remote inspector.

**Art direction** is flat-colour toon with a screen-space outline pass
(Roberts-cross edge detection over the depth and normal buffers). Screen-space
rather than inverted-hull, because hulls tear open at the corners of box
geometry and this world is mostly boxes.

## Running it

Needs [Godot 4.7.x](https://godotengine.org/download) **Standard** (not .NET).

```bash
godot --path .
```

Or open `project.godot` in the editor and press F5.

| Input | Action |
| --- | --- |
| WASD | Move |
| Mouse / right stick | Camera |
| Space | Jump |
| E | Interact |
| Esc | Release mouse |

## Layout

```
actors/player/     controller, camera rig, animation state machine
autoload/          GameState singleton (rupees, keys, opened chests)
components/        Interactable base
items/             rupee, chest, sign, gate
art/               models, shared toon materials, outline shader
world/rooms/       level scenes
tools/             build_clearing.gd — generates the level scene
ui/                HUD and debug overlay
```

### About the level generator

`tools/build_clearing.gd` emits `world/rooms/greenhollow_clearing.tscn`:

```bash
godot --headless --path . --script res://tools/build_clearing.gd
```

The output is a **real, hand-editable scene** — open it and move things around.
Re-running overwrites it, so past a certain point the generator gets retired and
editing happens by hand.

## Credits

3D models by [Kenney](https://kenney.nl), used under CC0 and MIT:

- [Nature Kit](https://kenney.nl/assets/nature-kit) — CC0
- [Starter Kit 3D Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) — MIT

Licence files are committed alongside the assets. The Kenney starter kit also
shaped the scene structure here (`Main -> World -> instanced props`).

Not affiliated with Nintendo. No Nintendo assets, code or trademarks are used —
this is an original game that takes design inspiration from the genre.

## Licence

MIT — see [LICENSE](LICENSE). Applies to the code; bundled art keeps its own
licences noted above.
