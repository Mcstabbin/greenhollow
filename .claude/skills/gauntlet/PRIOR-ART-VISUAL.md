# Prior art — readability, VFX and state legibility

Companion to [PRIOR-ART.md](PRIOR-ART.md) (combat, lock-on, components). This is
the Rule 1 pass for the *visual* problems that kept failing critic rounds. Read it
before touching outlines, trails, hit feedback or anything meant to be **seen**.

Our constraints, which invalidate most advice you will find: flat colour, hard
black outlines from a **screen-space** Roberts-cross pass over depth + normals, no
PBR, **no glow**, Linear tonemapping, integrated graphics, `SpringArm3D` camera
pitched −20° at 5.5 m with **zero lateral offset** (centred-behind, not
over-the-shoulder).

---

## The mechanism behind three of our four problems

**Godot captures the depth and normal-roughness buffers before the transparent
pass.** `art/shaders/outline_post.gdshader` reads only `hint_depth_texture` and
`hint_normal_roughness_texture`. Therefore:

**A transparent object can never be outlined.** Not at any setting. Confirmed:
[godot-docs-user-notes #42](https://github.com/godotengine/godot-docs-user-notes/discussions/42),
still true with depth-draw Always per [godot#114602](https://github.com/godotengine/godot/issues/114602)
(closed Jan 2026, no workaround).

Consequences, all verified against our own files:

1. `StandardMaterial3D_trail` and the spin ring are `transparency = 1`. In a world
   where every object carries a 1.3 px black contour, the two un-contoured shapes
   read as **rendering artefacts** — which is exactly what a critic said of the
   trail, unprompted: *"could be mistaken for a lighting artefact."* The fix is one
   integer: move them to the opaque pipeline (`ALPHA_HASH`, or `ALPHA_SCISSOR`
   with a threshold). They then write depth and inherit the same contour.
2. **Alpha-blend blinking for invulnerability would strobe the character's own
   outline** — the single most identity-defining element of the art direction.
   Toggling `visible` is worse. Use a tint toggle instead (see below).
3. `no_depth_test` on an effect forfeits the same fix and draws through walls.

## Our value structure is inverted

Authored albedo, Rec.709 luminance: outline **0.05** · grass **0.47** · **tunic
0.49** · stone 0.64 · **foliage 0.67** · sky top 0.55 · **sky horizon 0.91**.

The player and the ground are the same value *and* the same hue, and the two
brightest things on screen are both background. The rule is the opposite — the
focal point holds the highest contrast while background sits mid-to-dark
([nastyrodent](https://nastyrodent.com/color-theory-for-game-art/),
[Level Design Lesson 17](https://www.gamedeveloper.com/design/level-design-lesson-17-color-contrast)).
Judge every effect **in greyscale**; it tells you immediately whether a dark edge
is doing its job.

---

## Problem 1 — actions invisible from the gameplay camera

**Camera moves cannot fix this, and the geometry proves it.** Eye at ≈(0, 2.98,
5.17). A chest-height point 0.8 m in front of the chest is occluded by the body.
Clearing `|x| < 0.67` at the body needs the camera ≈**3.3 m** to the side — side-on,
not over-the-shoulder. Widening FOV does nothing: occlusion is a property of the
sight-line, not the frustum. **So the arc must move, not the camera.**

The animation rule of thumb, stated plainly
([animotionx](https://www.animotionx.com/en/post/how-to-create-a-readable-silhouette-in-gameplay-animation)):

> **"The weapon must ALWAYS be separated from the body."** … **"The body adapts to
> the weapon, not the other way around."**

Pose the weapon first in its final action position, then build the body around it.
Position weapons **diagonally**, never perfectly vertical or horizontal. The test:
**hide the body, keep only the weapon — is the attack direction obvious?** Judge at
gameplay camera distance, and squint or use flat shading.

**[God of War 2018](https://media.gdcvault.com/gdc2019/presentations/Sheth_Mihir_EvolvingCombat.pdf)**
(GDC 2019, Mihir Sheth — the only shipped account of our exact problem) never
widens FOV or pulls back. It compensates systemically: re-orients the camera toward
the attack direction, **rotates the character to the target** (*"If Kratos has a
target, all of his attacks are automatically rotated to face them"*), reduces
forward translation (*"moving FORWARD is naturally disadvantageous since you are
reducing the amount you can see"*), and adds **Strike Assist**, which blends the
victim's knockback trajectory toward camera-facing to pull them onto screen.
Off-screen threats get circling arrows — **red incoming, white idle, purple
ranged**. Their first attempt, flashing the screen edge, was *"thought to be damage
indicators instead. Not ideal."*

**Zelda's Z-target is framing, not camera motion**: player and target at opposite
ends of the screen, so the player rarely obscures the target, and the diagonal
keeps the spatial relationship clear. OoT also **swaps the moveset** — unlocked is
three horizontal slashes, locked is three **vertical** ones, a different blade axis
sharing no outline with the run cycle.

Counter-example worth knowing: **Arkham Asylum centres the camera during combat**
and offsets during exploration. Off-centre framing helps you see *past* the
character; it does not help you see *through* them.

| Repo | ★ | Licence | Take |
|---|---|---|---|
| [Snaiel/Godot4ThirdPersonCombatPrototype](https://github.com/Snaiel/Godot4ThirdPersonCombatPrototype) | 228 | MIT | Camera-controller FSM; solves pitch so the target lands at screen `(w/2, h/4)` — player low, target high, volume between them open |
| [ramokz/phantom-camera](https://github.com/ramokz/phantom-camera) | 3481 | MIT | Maintained equivalent. Group Follow builds an AABB over player+target. `damping_value` 0.1–0.25 |

```gdscript
var project_desired_pos: Vector3 = camera.project_position(
    Vector2(get_viewport().size.x / 2, get_viewport().size.y / 4), dist_to_target)
var desired_rotation_x: float = camera_controller.rotation.x \
    + atan2(_lock_on_target.global_position.y - project_desired_pos.y, dist_to_target)
```

Timing: hit pause **light 8 / medium 12 / heavy 15 frames** (SFV); Melee hitlag
`⌊d/3 + 3⌋`, cap 20 f; anticipation baseline ≈**15 frames at 60 fps**. Put idle at
frame −3 and the anticipation pose at frame 0, then start the clip 0.1 s in so the
contrast survives blending.

---

## Problem 2 — weapon trails

| Repo | ★ | Pushed | Licence | Geometry |
|---|---|---|---|---|
| [celyk/GPUTrail](https://github.com/celyk/GPUTrail) | 291 | 2025-12 | MIT | GPU; abuses `TRANSFORM`'s 4 columns as quad corners, `CUSTOM.w` as ring index. Zero CPU. Its billboard flag is self-described unfinished |
| [Hyrdaboo/TrailRenderer](https://github.com/Hyrdaboo/TrailRenderer) | 73 | 2026-01 | MIT | CPU `ImmediateMesh`; **3 alignment modes**; ships `sword_demo.tscn`. New features are **C#-only** — unusable on our Standard build |
| [HungryProton/proton_trail](https://github.com/HungryProton/proton_trail) | 150 | 2023 | MIT | Godot 3, clearest algorithm |
| [OBKF/Godot-Trail-System](https://github.com/OBKF/Godot-Trail-System) | 369 | **2021** | MIT | awesome-godot's only trail entry and it is **Godot 3**. Stars do not mean alive |

**`ImmediateMesh` is the right tool** — the docs call this its intended use, and
36 verts/frame is noise. **Do not optimise the rebuild.**

Three things good implementations do that ours does not:

1. **Distance-gated insertion, not per-tick.** Set `max_dist = 1.0 / resolution`,
   add points only when the emitter has moved further, and insert
   `ceil(dist / max_dist)` interpolated points in one frame. Our tip covers ~180°
   in 100 ms ≈ 0.6 m per tick, which yields a faceted 6-segment polygon, not an
   arc. ProtonTrail also Laplacian-smooths (`smooth = 0.5`), *"useful if your
   emitter moves too fast and produces a jagged trail"*.
2. **UVs and a width `Curve`.** Without them you get a parallelogram, never a
   crescent. Taper via `bitangent *= curve.sample(t)`.
3. **Keep the previous swing.** ProtonTrail pushes the finished array into
   `_previous_data` so a combo's two swings coexist. Ours clears on start.

**Colour: three bands, and the outer one must be dark.** The same ramp appears
independently in [Slash Shader](https://godotshaders.com/shader/slash-shader/),
CGHOW and Cyanilux. [Riot's VFX style guide](https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/)
states it outright: *"adding a dark background manually can help to promote the
effect"* and *"AVOID USING 100% OR 0% VALUES."* Priority order is **Shape → Value
→ Colour**. A bright-only effect *borrows* contrast from the background and dies on
a bright one; bright-core-plus-dark-edge *carries* its own.

| Band | Reads against | Value | Colour |
|---|---|---|---|
| Core, 15–25% of width, leading edge | grass (0.47) | 0.93–0.98 | warm near-white |
| Mid body | identity | 0.55–0.70 | teal or amber |
| Edge, 2–4 px, all round | sky (0.91), white torso | 0.08–0.18 | near-black |

Why our first cyan attempt failed: it is a **hue neighbour of our sky** and
intrinsically high-luminance (≈0.79), so it could not get below a 0.91-value
horizon. Keep teal as the *mid* band, never the outer value.

**Duration.** Slash shapes exist for 1–2 frames at their climax; Overwatch trails
fade in two or three and are very opaque *because* they vanish. Target **10–18
frames (0.17–0.30 s)**. Ours was ~2× too long and still fading during the next
input window. Guilty Gear Xrd runs **15 fps with interpolation off** — *"every
frame now is a key frame"* — so **step** the reveal in 2–4 holds; continuous lerping
is what makes a ribbon look like a 3D ribbon.

**Edge-on collapse is real** — a horizontal chest-height arc seen at 20° grazing
compresses by `sin 20° ≈ 0.34`, and every mature implementation ships an alignment
enum for it. But **full billboarding is the wrong counter for a swept blade**: it
makes width an arbitrary number instead of the blade span and twists as the camera
moves. Prefer authoring the swing plane broadside, enough thickness that 30°
off-broadside still has area, `cull_disabled`, and the practitioner hybrid — *"a
locked axis, but still faces the player"*, yawing about the swing axis only.
`RibbonTrailMesh` with `Shape = Cross` is two perpendicular quads and cannot
vanish edge-on.

---

## Problem 3 — the background out-shouts the action

**Yes, outline strength can be depth-attenuated in a screen-space depth+normal
shader, and it is standard.**
[pink-arcana/godot-distance-field-outlines](https://github.com/pink-arcana/godot-distance-field-outlines)
(148★, MIT) ships it as a first-class feature — modes `NONE / ALPHA / WIDTH /
ALPHA_AND_WIDTH`, defaults **`depth_fade_start = 4.0`, `depth_fade_end = 40.0`** —
for our exact stated reason: *"prevents wide outlines from obscuring far-away
content."*

```glsl
float get_depth_value(float p_depth) {
    return smoothstep(df.data.depth_fade_start, df.data.depth_fade_end, p_depth);
}
```

Three more precedents: [Depth Modulated Pixel Outline](https://godotshaders.com/shader/depth-modulated-pixel-outline-in-screen-space/)
shrinks the sampling radius (`pixel_size = (distance_falloff / d) / screen_size`);
[Thick 3D Screen Space Outline](https://godotshaders.com/shader/thick-3d-screen-space-depth-normal-based-outline-shader/)
divides the **normal** term by depth — the exact term we do not attenuate;
[Post-Process Outline](https://godotshaders.com/shader/post-process-outline-depth-normal/)
(CC0) scales the depth threshold *by* depth.

**Our two defects**, and the second dominates:

1. `depth_edge` normalises by distance (`dd / max(dc, 0.001)`) deliberately, so
   *"distant geometry outlines as readily as near geometry"*. That choice causes
   the symptom.
2. **`normal_edge` has no distance term at all.** Normal differences are
   distance-invariant, so distant foliage emits full-opacity crease lines that mat
   into a dense hatch as trees shrink — and our canopies *sway*, so the hatch
   shimmers. Temporal noise in the busiest region of frame.

**Fog cannot rescue it**: our outline `render_mode` includes `fog_disabled`, so more
fog washes out the trees while leaving their outlines pure black — strictly worse.
Depth-attenuating the outline is the mandatory partner to any fog change.

Then: our fog is exponential at `0.0035` ≈ **13% at 40 m**, essentially nothing.
**`FOG_MODE_DEPTH`** gives authored control (`fog_depth_begin` 10,
`fog_depth_end` 100, `fog_depth_curve`) with no extra pass. Watch for banding at
higher densities.

**Sable is the shipped flat-shaded peer** and lists our fix among its four:
load-bearing shadows (they added *moonlight* so the player still casts one),
per-biome distant fog *"really, really key"*, **outlines with opacity fading by
distance**, and gridded environment lines for overlap cues
([Game Developer](https://www.gamedeveloper.com/marketing/how-shedworks-refined-the-art-of-sable-in-pursuit-of-readability)).

**Selective outlines are a trap for us.** Godot 4.5+ stencil is marked
experimental, the stencil buffer is readable only in the transparent pass, and
**shaders cannot read stencil at all** — only a `CompositorEffect`, which has an
open accuracy bug ([#110629](https://github.com/godotengine/godot/issues/110629)).
Note `hint_normal_roughness_texture` is **Forward+ only, not planned for Mobile**,
so our outline choice pins the renderer.

---

## Problem 4 — state legible in a single frame

**`instance uniform` is the answer for per-character effects.** It needs a
`ShaderMaterial`; a plain `uniform` lives on the shared material and would flash
every instance at once. Limits: no textures or arrays, ~**16** per shader, and with
multiple materials the first one found wins.

```glsl
instance uniform vec4 tint : source_color = vec4(1.0);
```

Set with `GeometryInstance3D.set_instance_shader_parameter()`. Ranking:
`instance uniform` **>** `material_overlay` **>** `next_pass`. The latter two draw
the mesh again *and* introduce a shader variant never drawn before — Godot's own
guidance is that this *"will result in immediate stutters"*. A hitch on the damage
frame is the worst possible place for one.

**Rim light must be thresholded** to survive flat colour
([eldskald/godot4-cel-shader](https://github.com/eldskald/godot4-cel-shader), 297★,
MIT): `smoothstep(threshold - smoothness/2, threshold + smoothness/2, fresnel)`
with smoothness near 0 gives a hard flat band, gated by `is_lit()` so it only
appears on the lit side. A soft `pow()` gradient next to a 1.3 px hard contour reads
as a rendering error.

**Hit flash — not white.** `player.tscn` already records why: a white flash on a
white torso is invisible. GDQuest's whole implementation is a flat albedo
replacement driven by an AnimationPlayer track.

**Invulnerability — tint toggle, never alpha.** DOOM inverts the **entire frame**
and alternates 8 tics on / 8 off ≈ 2.2 Hz at 50% duty, and only for the last 128
tics, so the *expiring* blink is a separate state from the active one. Celeste
toggles a tint on a 10 Hz square wave (`OnInterval(.05f)`), plus a 120 ms flash on
dash refill and a trail of exactly 3 ghosts at 0 / +80 / +150 ms **tinted to encode
whether the dash is available**. No source states a canonical flicker Hz; 60 Hz
alternation vanishes entirely when captured at 30 fps, and flicker is a
photosensitivity concern.

**Damage — Quake's kick carries information**, and is strictly better than random
shake: `count` floored at 10 so small hits still read, tint colour encoding *what
absorbed the hit* (armour-heavy `(200,100,100)` … flesh only `(255,0,0)`), and the
roll **points at the attacker**, so a still frame shows direction. DOOM decouples
flinching entirely with a per-enemy `painchance` out of 256 (Cyberdemon = 0).

**Parry windows, measured**: DS3 small shields **10 frames (11–20)**, buckler 12,
with a partial parry just outside. Sekiro **12 frames (0.2 s) decaying to 4 or 0 if
spammed**, recovering after 30 — an anti-mash array, not a fixed window.
Bayonetta Witch Time frames 8–27 with **Bat Within on 24–35**, so a *late* dodge
gives a different, weaker outcome.

**Distinguishing parry from block**: Wind Waker uses three channels at once — button
icon flashes green, **sword flashes green**, and a sound, *"lasting only a
split-second"*. No developer anywhere states a stance-width or centre-of-gravity
number; don't invent one.

**Ground markers: use a quad, not a `Decal`.** Decals support **no custom shader**,
are Forward+/Mobile only, cap at 8 per mesh on Mobile, and apply through the
*lighting* path — so an `unshaded` ground surface very likely receives nothing.
The docs name `Sprite3D` as the alternative. Our `toon_shadow_blob.tres` on a
squashed sphere is already the right pattern; use **alpha scissor** so it stays in
the instancing path and keeps a hard edge at 640 px.

**Hitstop is not a visual technique** — it buys screen time for the pose you already
have. Smash draws the victim on the first frame of their flinch *while shaking*;
the freeze exists to display a chosen readable pose. **Never
`Engine.time_scale`**: `AudioStreamPlayer` ignores it
([#28953](https://github.com/godotengine/godot/issues/28953)) and physics stops
being deterministic. Scale the two combatants' `AnimationTree`s, or use
[Kelpekk/Juicee](https://github.com/Kelpekk/Juicee) (94★, MIT), whose
`hit_stop(node, 0.08)` is node-scoped.

Vlambeer's [Art of Screenshake](https://theengineeringofconsciousexperience.com/jan-willem-nijman-vlambeer-the-art-of-screenshake/)
order is worth following: animations → SFX → muzzle flash → impact effects → enemy
hit animations → camera lerp → screen shake → … → **lower enemy HP** → … → **less
accuracy** → knockback → a very short freeze on hit. Nuclear Throne shipped
screenshake and freeze-frame **sliders down to 0%**; players use them for legibility.

---

## Reject, despite being common advice

- **Bloom / glow.** Nearly every slash tutorial is `blend_add` + `emission_energy`
  and *assumes* bloom. Our environment has **no glow** and Linear tonemapping, so
  values above 1.0 clip flat and additive over a 0.91-value sky is *arithmetically*
  invisible. Flat-colour signalling works on hue and value contrast, not luminance
  overflow.
- **Soft rim gradients and emissive halos** — they compete for the silhouette edge
  we already spend the budget on.
- **Depth of field.** Blurs the outline it is blurring, carries zero state
  information, costs fill rate. Death's Door gets away with it only because its
  camera is fixed isometric with a static focal plane.
- **Alpha-blend blinking, semi-transparent ghosts, `visible` toggling.** Erases the
  outline; also disqualifies the mesh from automatic instancing.
- **Screen-edge damage flash.** Not an art conflict but a documented *state
  collision* — GoW's players read it as the wrong thing.
- **Damage numbers.** A second typographic layer competing with the outline read.
- **Unqualified overhead markers.** Sekiro's 危 *"obscures the enemy's attack for a
  brief but important second."*

## Traps at our scale

- **`GPUParticles3D.trail_enabled` / `RibbonTrailMesh`.** Silently does nothing
  without `use_particle_trails` on the material, appears **zero** times in
  `godot-demo-projects`, skewing bug [#65920](https://github.com/godotengine/godot/issues/65920)
  closed as not planned, and it is *per-particle* so it cannot express a base→tip
  smear.
- **A `CompositorEffect` for stencil per-state outlines.** A flat albedo swap gets
  the same read in an afternoon.
- **Optimising the `ImmediateMesh` rebuild.** The real sunk cost in the level is
  **625 individual `MeshInstance3D` nodes with no MultiMesh**, plus the
  full-screen outline pass.
- **Assuming stars mean alive.** awesome-godot's only trail entry is Godot 3, last
  pushed 2021. The Asset Library's `godot_version` filter does not actually filter.
- **Authoring effects against black.** Judge against grass, against sky, and in
  greyscale.

## Negative results — the ecosystem, not our search

awesome-godot has **no** Godot 4 trail entry and **no** lock-on entry.
`godot-demo-projects` has no combat, camera-rig or trail demo. Godot
screenshot-regression tooling is two repos at 21 and 0 stars. Proposal
[#4020 Built-in 3D mesh trails](https://github.com/godotengine/godot-proposals/discussions/4020)
has been open since 2022 and [PR #115040 `Line3D`](https://github.com/godotengine/godot/pull/115040)
closed as an unfinished draft in March 2026. For lock-on, trails and visual
regression we build rather than adopt.
