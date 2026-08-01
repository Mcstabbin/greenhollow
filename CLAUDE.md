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
- **Typed node exports in a `.tscn` need `node_paths=PackedStringArray("field", …)`
  in the node header.** Without it Godot stores the NodePath and never resolves
  it: every reference arrives `null` and **nothing is printed**. Symptom was a
  state machine that silently never left its first state. Found by packing the
  same wiring in code and reading back what the engine writes.
- **`art/models/character.glb` has no `Skeleton3D`.** The rig is seven plain
  `Node3D`/`MeshInstance3D` nodes and the shipped clips are ordinary
  `POSITION_3D`/`ROTATION_3D` tracks against node paths. Authoring new animation
  is writing more of the same track type — no skinning, no bone mapping.
- **Input → AnimationPlayer method track is three frames**: one for
  `just_pressed`, two more for the AnimationTree advancing after the player in
  the same tick. Keyframe method tracks three frames early and say so at the
  constant, or the window opens late and every measurement is off.
- **An attachment's transform must be keyed in *every* clip, including
  locomotion.** Key it only in the attack clips and it snaps to whatever the last
  clip left it at. The sword grip was cancelled by the idle clip posing
  `arm-right` 32° down.
- **New `class_name` globals do not resolve until an `--import` pass has run.**
  A script that references one fails to parse until then, which reads as a typo.
- **GDScript cannot infer a type through a loosely typed reference.**
  `var x := player.max_speed` is a *parse error* when `player` is typed
  `CharacterBody3D`, because `max_speed` is an `@export` the analyser cannot see.
  Write the type out.
- **Re-enabling `monitoring` on an `Area3D` makes it re-report areas already
  overlapping it.** That is a feature for combat: it is what lets a second swing
  hit a target the blade never physically left.
- `--fixed-fps 60` decouples the physics step from wall time, so headless runs are
  fast *and* deterministic. Without it, measured numbers drift with machine load.
- **Headless has no renderer at all** — there is no headless screenshot, ever.
  Screenshots require a real window, and `RenderingServer.frame_post_draw` is the
  only moment the viewport texture holds a complete frame.
- A windowed run inherits `player.gd`'s captured mouse and the real cursor
  silently rotates the camera. Set `MOUSE_MODE_VISIBLE` **every frame**, not once
  — the pause menu and the player both touch it.
- Drop a `.gdignore` in any directory of generated PNGs, or the engine imports
  your own screenshots as game textures on every `--import`.
- `N resources still in use at exit` from a headless run is the `Audio` autoload's
  pooled players holding stream playbacks. Pre-existing and benign — confirmed
  against a clean checkout. Don't chase it.
- **`--check-only --script <file>` is useless as a parse check here.** Same
  autoload rule as above: every file touching `GameState` or `Audio` fails with
  `Identifier not found`. Measured 14 false positives, zero true ones. Run the
  probe *scene* instead — it compiles the same code with autoloads present and
  exercises it. This was tried in CI and removed.
- **Resources generated by a `--script` run get no UID.** `ResourceSaver` can only
  write `uid://` when `EditorFileSystem` has installed its callback, and that
  never runs headless ([godot#105062](https://github.com/godotengine/godot/issues/105062),
  declined). Consequence: every re-run of a generator *deletes* any UID the editor
  added. `ResourceUID.create_id_for_path()` is deterministic if one is needed.
- **The headless dummy renderer silently ignores `MultiMesh.set_instance_transform()`.**
  Instances all stack at the origin and the saved resource is a fraction of its
  real size. Relevant the moment foliage moves to `MultiMeshInstance3D` for
  performance — same family as the `.glb` override trap.
- `PackedScene.pack()` drops unowned nodes **silently**. At 1,400 nodes the only
  way to notice is a node-count round-trip after packing.
- The Asset Library is being superseded by [store.godotengine.org](https://store.godotengine.org/).
  Check both when following Rule 1.
- **The depth and normal-roughness buffers are captured *before* the transparent
  pass, so a transparent material can never be outlined by `outline_post`.** Not at
  any setting. This is the single most consequential fact about our art direction:
  in a world where everything carries a black contour, an un-contoured shape reads
  as a *rendering artefact*. Effects that must read (trails, rings, slashes) belong
  in the opaque pipeline — `ALPHA_HASH`, or `ALPHA_SCISSOR` with a threshold.
  Corollary: **never alpha-blend or `visible`-toggle the player** for i-frames or
  flashes; it drops the character's own outline on every off phase. Toggle a tint.
- Our outline's `normal_edge` term has **no distance attenuation** while
  `depth_edge` does (`dd / max(dc, 0.001)`). Normal differences are
  distance-invariant, so distant foliage emits full-strength crease lines — and
  since the canopies sway, that hatch shimmers. Also `render_mode` includes
  `fog_disabled`, so raising fog washes out the trees while leaving their outlines
  pure black. Depth-attenuating the outline is the mandatory partner to any fog
  change.
- `hint_normal_roughness_texture` is **Forward+ only** and not planned for Mobile.
  The outline pass pins the renderer.
- **Never use `Engine.time_scale` for hitstop.** `AudioStreamPlayer` ignores it
  entirely and physics stops being deterministic. Scale the participating
  `AnimationTree`s instead.
- `material_overlay` and `next_pass` draw the mesh a second time *and* introduce a
  shader variant never drawn before, which compiles on first use — a stutter
  exactly on the damage frame. Prefer `instance uniform` + `set_instance_shader_parameter()`
  (needs a `ShaderMaterial`; a plain `uniform` would flash every instance at once).
- `Decal` supports **no custom shader**, is Forward+/Mobile only, and applies
  through the lighting path — so an `unshaded` surface likely receives nothing. Use
  a `Sprite3D` or a flat quad with alpha scissor, as `toon_shadow_blob.tres`
  already does.
- **Hiding a node is not enough to hide an effect.** `SwordTrail` sets
  `visible = true` at the end of its own `_physics_process`, so setting `visible`
  false does nothing at all — the first pose-only capture run silently produced
  seven frames with the ribbon fully drawn. Disable `process_mode` as well.
  Anything that asserts its own visibility per-frame needs the same treatment.
- **An `OmniLight3D` counts as an effect node.** Hiding the charge glow changes the
  lit grass around the player, so an effects-on/effects-off pixel difference
  includes light, not just geometry. Worth knowing before trusting such a diff as a
  measure of "effect footprint".
- `.tscn` and `.tres` files **do** accept `;` comments, which is the only way to
  leave a note on hand-authored scene wiring.
- **An `AnimationNodeStateMachine` will not *start* a travel while the current state
  is still fading in.** The request is dropped, not queued. Measured cost: a 0.06 s
  cross-fade delayed an attack by 3 frames, because releasing a charge on the exact
  threshold frame releases into the charge pose's own fade-in. 0.02 s is the
  practical floor. This is why `spin_windup` measures 167 ms rather than 150.
- Conversely, **shortening a cross-fade costs nothing in measured timing** — all 19
  combat measurements were identical either side of `trans_attack_in` 0.05 → 0.02,
  because method tracks fire on *clip* time and blend weight has no say. Fade
  length affects when a travel is *accepted*, not when its keys fire.
- **A fading-out clip still advances and still fires its method tracks.** A combo
  that cross-fades clip A into clip B will run A's end keyframe *inside* B, which
  silently ended the second swing of ours: the clip played out from the wrong state
  with no commitment and no cancel window, and every probe number still passed.
  Pass the owning clip name into method-track calls and ignore keys from clips that
  are no longer current.

## Known hazards — read before touching these

- **Do not re-run `tools/build_clearing.gd`.** The level's last commit was a hand
  quality pass, not a generator run, so re-running overwrites human edits.
  `README.md` says the generator gets retired; it has been. Treat
  `world/rooms/greenhollow_clearing.tscn` as the source of truth and fold layout
  changes in by hand.
- **The project has no resource UIDs.** Verified: 2 of 21 tracked scene/resource
  files carry a `uid://` header, and both are harnesses that were hand-authored
  with made-up IDs. Every `ext_resource` in the project is `path=`-only. So
  renaming or moving an asset in the editor breaks references silently, with no
  UID to follow. Godot's own guidance after 4.4 is to re-save everything to add
  them; we never did.
- **`greenhollow_clearing.tscn` is `format=4`; every other scene says `format=3`.**
  If the editor ever re-saves the hand-authored scenes they all jump at once — a
  diff large enough to hide a real regression.
- **`player_anims.tres` has forked the `.glb`'s clips.** `build_combat_anims.gd`
  copies them in and re-paths their tracks, so the generator is now the sole
  source of truth for locomotion animation. **Updating `character.glb` will not
  propagate.** Re-run the generator after any model change.

## CI

`.github/workflows/static-checks.yml`. Two jobs, both runnable locally:

```bash
python -m gdtoolkit.linter $(git ls-files '*.gd' | grep -v '^addons/')

"$GODOT" --headless --fixed-fps 60 --path . res://tools/probe.tscn -- --suite=movement 2>&1 \
  | python tools/check_baseline.py tools/baselines/movement.json
```

`tools/baselines/movement.json` pins how the character moves, to one physics
frame. Changing feel is fine; changing it *by accident* is what this stops — a
real change means editing the baseline in the same commit and saying why.

`.gdlintrc` documents every deviation from gdtoolkit's defaults, with reasons.
`max-public-methods` is set to `player.gd`'s current count as a **ratchet**: the
next public method fails CI. Lower it as the animation façade lands; never raise
it.

## Readability: what the critics keep catching

Found by putting real frames in front of fresh-context critics that had no access
to the code. Each of these failed a round before it was understood.

- **Judge from the gameplay camera, never a showcase angle.** An over-the-shoulder
  camera at torso height owns the entire volume in front of the chest. Staged
  three-quarter angles made a swing look great while the same swing was
  *completely invisible* in play — no blade, no trail, indistinguishable from
  idle. Every action shot goes in the shot list at the default camera first.
- **An action must break the silhouette in the direction the camera looks from.**
  The only screen space the body does not already own is above the head and
  outside the shoulders. An overhead chop reads from behind; a chest-height
  horizontal cut does not.
- **Never put a light element on a light element.** White blade + white trail +
  white torso merge into one shape. Effects get a saturated off-palette hue
  (cyan, hot orange) that appears nowhere else in the world, so they read against
  grass, character and treeline alike.
- **Symmetry kills motion.** A pose with both arms out, shot front-on, reads as a
  T-pose holding a prop rather than as a spin. Asymmetry is what says "moving".
- **A front-on camera is the worst choice for a horizontal arc** — the motion
  travels toward and away from the lens, so its largest, fastest part compresses
  to nothing.
- **Flash the empty part too.** A damage flash applied only to the *filled*
  portion of a meter is invisible when almost nothing is left to flash — it fails
  on precisely the hits that matter most.
- **State changes should converge, not appear.** A reticle that snaps on reads as
  a HUD element; one that closes onto its target over ~110 ms reads as the game
  locking on, and communicates it in a single still frame.
- **Composition works against the action here.** The treeline is the
  highest-contrast, most heavily outlined region of every frame, and fights
  happen in a flat low-contrast green field below it. The eye goes to scenery.
  Unresolved — a lighting/composition pass owes this an answer.
- **Shape carries motion; the outline cannot.** The hardest-won lesson here. An
  un-outlined effect reads as a *rendering artefact*, and an outlined, opaque,
  hard-edged one reads as a *solid prop* — two critics, two rounds, both correct.
  In this art direction the black contour **is** the signifier of solidity, so
  there is no outline setting that fixes it. Effects must be shaped like motion:
  tapered to points at both ends, curved, no straight terminating edges. A flat
  quad with hard corners reads as a playing card no matter what colour it is.
- **The pose has to carry the read; the VFX is support.** The only frame a critic
  ever praised was the one where the *character's* body language was unambiguous
  and the effect was secondary. Its verdict is worth keeping verbatim: *"legibility
  and correctness are inversely correlated — the effects you can't miss are the
  ones that read as objects; the one that reads as a genuine action is carried by
  the pose."* Test it directly: capture with effects hidden
  (`tools/shots/poseonly.json`) and see whether the pose alone still reads.
- **Torso roll is the cheapest silhouette channel this rig has.** On a box torso
  seen from behind, yaw is nearly invisible and pitch reads weakly, but roll tilts
  the whole white mass, the head knob and both arms off vertical at once. Roll the
  **torso**, not the root — rolling the root drives a foot into the ground.
- **A slash's contact frame cannot get the blade clear of the body, and this is
  arithmetic, not art.** The hitbox has to reach 1.25 m in front at chest height;
  the blade is 1.2 m grip-to-tip and the hand travels at most 0.52 m from the
  shoulder, so the blade's midpoint must come within 0.86 m of the target. Rolling
  the body the other way to throw the arm outboard *gains* clearance and **loses
  the hit entirely** — measured reach 1.30 m at every live frame, damage 0, tip
  driven underground. Do not re-litigate this; the numbers are in
  `tools/build_combat_anims.gd`.
- **The character's head sits above the torso with a visible gap**, so it reads as
  floating on a stalk rather than as a style choice. Spotted independently by a
  critic and by a capture review. *(Fixed: it was the antenna knob, not a head.)*

## Layout

```
actors/player/     player.gd + player.tscn, the gameplay state machine
                   (player_*_state.gd), sword hitbox and trail, generated
                   player_anims.tres, procedural combat sfx under audio/
autoload/          GameState and Audio singletons
components/        Interactable base, LockOnTarget marker
items/             rupee, chest, sign, gate
addons/            vendored, licence committed alongside:
                   health_hitbox_hurtbox (MIT) — Health/HitBox3D/HurtBox3D
art/materials/     shared toon StandardMaterial3D resources
art/models/        .glb assets (Kenney, CC0/MIT)
art/shaders/       outline_post.gdshader (screen-space edge detect), foliage, water
world/rooms/       level scenes
tools/             build_clearing.gd (level), build_combat_anims.gd (animation),
                   probe.tscn (headless measurement), capture.tscn (screenshots),
                   shots/*.json (capture shot lists), out/ (generated, gitignored)
ui/                HUD, hearts, lock-on reticle, pause menu, debug overlay
refs/              reference frames for the gauntlet loop. GITIGNORED, never
                   committed, never traced or transcribed. See refs/README.md
.claude/skills/    gauntlet — the quality loop: prompt, critic contract,
                   feel rubric with bands, prior art already read
```

`GameState` is deliberately thin and its header says why. Health lives there only
as a projection of the player's `Health` component so the HUD has one thing to
listen to; the component stays authoritative. Resist adding anything else.

Art direction: flat colour, toon-ish shading, black outlines. No PBR, no textures
beyond the Kenney colormap atlas. Avoid SDFGI, SSR and volumetrics — the target
is integrated graphics.
