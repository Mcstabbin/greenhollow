# Prior art — read before building combat

> Companion docs: [PRIOR-ART-VISUAL.md](PRIOR-ART-VISUAL.md) for outlines, trails,
> hit feedback and state legibility — read that one before touching anything meant
> to be *seen*. Architecture, style and testing prior art is at the bottom of this
> file.

`CLAUDE.md` Rule 1 requires reading a real, maintained implementation end-to-end
before writing any of a new system. This is the result of that pass for combat,
lock-on and hit feedback, so the next session starts from here instead of from a
search box. **Re-check anyway** — these projects move.

## Ranked candidates

| # | Repo | Stars | Last push | Licence | Solves |
|---|---|---|---|---|---|
| 1 | [Snaiel/Godot4ThirdPersonCombatPrototype](https://github.com/Snaiel/Godot4ThirdPersonCombatPrototype) | 228 | 2024-11 | MIT | Lock-on + camera FSM, hierarchical player FSM, attack windows. **The lock-on reference.** |
| 2 | [cluttered-code/godot-health-hitbox-hurtbox](https://github.com/cluttered-code/godot-health-hitbox-hurtbox) | 161 | 2026-07 | MIT | Health/HitBox3D/HurtBox3D addon. Typed, unit-tested, CI, in awesome-godot. **Use it, don't rebuild it.** |
| 3 | [catprisbrey/Cats-Godot4-Modular-Souls-like-Template](https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template) | 409 | 2025-12 | Unlicense | Strafe camera, reticle, parry/i-frames, simpler timer-driven attacks |
| 4 | [gdquest-demos/godot-4-juicy-attack](https://github.com/gdquest-demos/godot-4-juicy-attack) | 7 | 2026-05 | MIT (code) | Hitstop, flash, knockback. **The hit-feedback reference.** |
| 5 | [gdquest-demos/godot-4-3d-third-person-controller](https://github.com/gdquest-demos/godot-4-3d-third-person-controller) | 996 | 2026-06 | MIT (code) | Already a source here. Camera rig, melee area activate/deactivate. No lock-on. |
| 6 | [bitbrain/beehave](https://github.com/bitbrain/beehave) | 3205 | 2026-07 | MIT | Behaviour trees, for enemy AI later |

`godot-demo-projects` has **nothing** for combat, targeting or camera rigs.
awesome-godot has nothing for lock-on. Asset Library #1259 "G4 Super 3D
Targeting System" is CC0 but untouched since 2022 and ported from VisualScript —
not usable.

**LimboAI** (MIT, 2917 stars) is excellent but v1.8.0 ships a GDExtension for
**4.6 only**; 4.7 needs their custom engine build, which breaks the "Standard
build, not .NET" constraint. Skip it. Snaiel's ~60-line state machine is
copyable in an afternoon and needs no binary.

## The load-bearing design decision

Snaiel acquires targets by **screen-space distance from the viewport centre**,
not by 3D distance:

```gdscript
var viewport_center := Vector2(get_viewport().size / 2)
for t in _get_targets_in_frustum():
    var dist := viewport_center.distance_to(cam.unproject_position(t.global_position))
    if closest_target == null or dist < closest_dist:
        closest_dist = dist
        closest_target = t
```

That is why Ocarina-style targeting feels right — it locks what you are *looking
at*, not what you are *nearest to*. Copy the idea, not the file.

Broad phase is an `Area3D` sphere that teleports to the player each frame and
keeps a persistent `_targets_nearby` array via `area_entered`/`area_exited`;
scoring only runs on the button press. The targetable marker is an `Area3D` with
a **0.1 m** sphere that tracks a chest bone — a point, not a volume.

Validity is a frustum test plus a ray **from the camera**, not from the player,
masked to world geometry only. Strict `is_position_in_frustum()` for initial
acquisition, looser `not is_position_behind()` for switching, so you can flick to
something just off-screen.

Locked-camera pitch is the other good idea: it does not aim at the target, it
projects the *desired screen position* back into the world and solves for the
pitch that puts the target there — framed at (½ width, ¼ height), so the player
stays readable below it.

Locked movement rotates input into **target** space rather than camera space,
which is what makes strafing orbit the enemy.

## Numbers from shipped projects

Useful as sanity checks, **not** as our values — Greenhollow's whole play area is
±24 m, so Snaiel's 20 m acquire radius would lock onto half the level. Scale
against our player capsule (r 0.4, h 1.8). Our own bands live in
[REFERENCE.md](REFERENCE.md).

| Thing | Snaiel | catprisbrey | GDQuest |
|---|---|---|---|
| Lock acquire / retain | 20 m / 25 m | ~14 m forward box | — |
| Target-switch threshold | 60 px mouse, 0.2 stick, 0.5 s debounce | 300 px, 0.6 s | — |
| Camera spring | 2.0 m, +1.5 m height, FOV 75 | 2.0 → 0.7 guarding | — |
| Player yaw toward target | `lerp_angle` 0.2 (0.1 running) | slerp 0.4 strafing | — |
| Hitbox active window | animation method track | **30%→80% of the clip** | — |
| Parry window | 0.25 s at the end of a 0.8 s hit reaction | 0.3 s | — |
| I-frames | 0.8 s hit-reaction lock | from 70% of the dodge clip | — |
| Hitstop | — | — | `Engine.time_scale = 0.07`, ~0.3 s real |
| Knockback | speed 3, friction 5 | — | impulse 300, decay `delta*10` |

Snaiel authors attack windows as **AnimationPlayer Call Method Tracks**, not code
— `receive_can_damage()`, `receive_can_attack_again()`, `receive_secondary_movement()`
have no GDScript callers at all. Commitment is a flag flipped by a keyframe. That
is the right pattern for us: it puts timing in the same place as the animation
that has to match it.

## What to avoid — observed in these repos, not hypothetical

1. **Framerate-dependent smoothing.** All of them use bare `lerp(a, b, 0.1)` in
   `_physics_process`. Fine at a fixed 60 Hz, broken the moment ticks change.
   Use `1.0 - exp(-rate * delta)` — which `player.gd:212` already does correctly.
2. **The double lerp.** Snaiel's locked camera does
   `lerp(rot.y, lerp_angle(rot.y, target, 0.05), 0.8)` — 0.04 effective weight
   expressed confusingly, and the outer `lerp` on an angle can take the long way
   round near ±π. One `lerp_angle`, one weight.
3. **`await` inside physics for gameplay windows.** Untestable, uninterruptible.
   catprisbrey awaits a timer to flip `monitoring`. Use method tracks.
4. **Signals wired by string name through exports.** A typo is silence, not an
   error. Typed signals catch it at parse time.
5. **God-object autoload as service locator.** Snaiel's `LockOnSystem` reaches
   five levels deep into `_dizzy_system.dizzy_victim.instability_component.…`,
   which is why it can't be tested or reused. Keep acquisition/scoring pure and
   feed it targets.
6. **Feature special-cases inside generic components.** Snaiel's
   `HitboxComponent._process` carries a 15-line dizzy-system exception. At that
   point it is not a component.
7. **LOS checked only at acquisition.** None of these break the lock when the
   target goes behind cover. Ocarina does. If we want that, the check has to run
   continuously — with a grace period, or ducking behind a tree is infuriating.
8. **`AnimationNodeTransition` won't restart a clip already playing** — that
   gotcha forced Snaiel's whole duplicate-animation scheme. Decide up front
   between `AnimationNodeStateMachine.travel()` (handles re-entry) and duplicated
   transition nodes.

## Multi-hit prevention, worth stealing outright

Snaiel's `DamageSource.instance: int` increments per swing; the hitbox records
`_successful_hits[damage_source] = instance`. The same sword re-entering during
one swing is ignored; the next swing lands.

---

# Prior art — architecture, style, testing

Second Rule 1 pass, into how strong Godot 4 codebases structure things we do by
hand. Verified via the GitHub API 2026-07-31.

| Repo | ★ | Licence | Take |
|---|---|---|---|
| [godot-demo-projects `finite_state_machine`](https://github.com/godotengine/godot-demo-projects/tree/master/2d/finite_state_machine) | 9268 | MIT | The **pushdown stack**. `finished.emit(PLAYER_STATE.previous)` makes its whole attack state two lines and it does not know Idle exists |
| [MewPurPur/GodSVG](https://github.com/MewPurPur/GodSVG) | 2648 | MIT | Cleanest large GDScript codebase. The only one with an enforced *written* style contract. 3 autoloads |
| [ramokz/phantom-camera](https://github.com/ramokz/phantom-camera) | 3481 | MIT | Registry-autoload pattern: nodes self-register into a typed array behind a read-only getter |
| [Orama-Interactive/Pixelorama](https://github.com/Orama-Interactive/Pixelorama) | 10028 | MIT | Its CI recipe, adopted here. Also the **cautionary tale** — `Global.gd` is 73 KB and leaf data classes reach through it to retitle tabs. Stars do not certify architecture; read the leaf classes |
| [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) | 1176 | MIT | Explicitly supports 4.7/4.7.1. `scene_runner` + `simulate_action_pressed` is the standard for input-driven integration tests — `tools/probe.gd` is a hand-rolled version of it |
| [bitbrain/beehave](https://github.com/bitbrain/beehave) | 3205 | MIT | Pure GDScript, 4.7 in CI. The de-facto enemy-AI answer for sub-wave B |
| [Scony/godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit) | 1585 | MIT | `gdlint` / `gdformat`. In CI here |
| [Nodragem/top-down-action-adventure-starter-kit](https://github.com/Nodragem/top-down-action-adventure-starter-kit) | 528 | CC0 | **Anti-pattern, our exact genre.** `@export var ui_hearts: Array[TextureRect]` inside the health component, and `if body is PlayerEntity` in the enemy weapon. Result: three incompatible health systems and enemies that cannot hurt each other |

## What we deliberately do NOT change

1. **Keep the hand-rolled FSM.** LimboAI still ships a GDExtension for **4.6 only**
   (4.7 needs their custom engine build, which breaks the Standard-build rule);
   gd-YAFSM is going stale; the newest graph FSM is self-declared alpha. The
   **996★ GDQuest 3D third-person controller has no gameplay FSM at all** — it is a
   flat `_physics_process` plus an `AnimationNodeStateMachine` for visuals only.
   Every strong project hand-rolls this.
2. **Keep typed `@export` transitions and `physics_update` returning the next
   state.** Both references resolve transitions by *string name*, so a broken wire
   is a runtime `printerr`, not a load error. One 226★ project does
   `states[child.name.to_lower()]`. Our typed version is strictly better on the axis
   it was chosen for.
3. **Keep the windowed screenshot harness.** `--headless` has no renderer,
   off-screen rendering is still only a proposal, and there is no Xvfb on Windows.
   The only two Godot VRT tools in existence have 21 and 0 stars. We are ahead of
   the ecosystem here.
4. **Keep `probe.gd` as a scene-based harness.** Port *assertions* into gdUnit4 if
   useful; do not dissolve the measurement harness into it.
5. **Keep the feature-first folder layout.** It matches the engine's own
   `3d/platformer`. Type-folder layouts (`Scenes/`, `Scripts/`) are the Godot 3
   legacy you can date a project by.
6. **Do not chase `untyped_declaration=2`.** Popular advice; **zero** large shipped
   codebases run it. GodSVG mandates static typing in prose and enforces it by
   review, not by the compiler.

## The one real coupling flaw to fix

`PlayerAttackState` carries three `@export`s (`idle_state`, `move_state`,
`air_state`) whose only job is answering *"where do I go back to"*. Both references
solve this without the state knowing: the official demo pushes onto `states_stack`
and returns with `PLAYER_STATE.previous`; Snaiel calls
`parent_state.transition_to_previous_state()`. Keep typed exports for **deliberate**
transitions; use a stack for **returns**.

## The animation façade convention

`class_name CharacterSkin extends Node3D` with intention-named methods — `jump()`,
`fall()`, `punch()` — wrapping the `AnimationTree`, so **no gameplay code ever
contains a `"parameters/…"` string.** The same `*_skin.gd` pattern appears
independently in four well-starred repos (GDQuest's 3D controller and 3D-Characters,
`godot-4-new-features`, gtibo/Godot-Plush-Character). `gdlint`'s
`max-public-methods` on `player.gd` flagged the same refactor independently.

## Signal routing without a god object — a ladder, not one answer

1. Direct connection at composition time. The docs: *"If at all possible, you should
   design scenes to have no dependencies."*
2. **Registry autoload** — nodes self-register into a typed array.
3. **Domain-scoped typed relay**, forwarding with `Signal.emit` as a `Callable`:
   `root.xnodes_added.connect(layout_changed.emit.unbind(1))`. No hand-written
   forwarders.
4. Observable `Resource` (`value` + `changed`), injected by `@export`. Its edge over
   a bus: a bus has no *current* value.
5. Scoped bus named for its boundary — `UIEventBus`, not `EventBus`.
6. Global `Events` singleton — last resort. GDQuest, who popularised it, warn you
   end up searching the whole codebase to trace one signal.

Autoload counts, measured: GodSVG 3, Reia 10, Material Maker 10, Pixelorama 12. The
escape route is `class_name`'d **stateless static classes** — globally reachable, no
global state, no autoload slot.

`class_name` cyclic-dependency fear is **stale**: it resolves through the global
class table, so two classes can mutually type-reference each other and compile.
Residual cycle errors come from `const X = preload(...)` chains and autoloads.

## Generating resources from code

Our headless CLI generators are a legitimate pattern with live precedent, **but they
cannot write UIDs** — see the hazards section in `CLAUDE.md`. Well-regarded
programmatic generators mostly use `EditorScript` + File▸Run
([Inspiaaa/ThemeGen](https://github.com/Inspiaaa/ThemeGen), 248★) and **nobody
generates an `AnimationLibrary` from a headless CLI** — every real instance does it
inside an `EditorImportPlugin` or `GLTFDocumentExtension` at import time, so the
output is never committed and the UID problem never arises.

The escape hatch, if UIDs start hurting: run the **headless editor**
(`godot --editor --headless res://Scene.tscn` with a `@tool` root), which restores
`EditorFileSystem` — UIDs, rescan, real rendering servers — and stays one CI-able
command.

Worth stealing regardless: an owner recursion that stops at instanced-scene
boundaries, which is our `.glb` gotcha generalised.

```gdscript
func set_owner_on_new_nodes(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		if child.scene_file_path.is_empty():
			set_owner_on_new_nodes(child, scene_owner)
```
