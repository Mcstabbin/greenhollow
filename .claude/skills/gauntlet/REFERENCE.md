# The bar — reference material and feel rubric

## `refs/oot/` — what to put there

Gitignored. Frames captured from your own legally obtained copy. Nothing here is
ever committed, traced, transcribed or shipped; it exists so a critic can compare
against the real thing instead of reciting a description of it.

Name descriptively — the filename is all the critic gets as a caption, so
`lockon_midfight_plant.png` beats `oot_03.png`.

**Combat, wave 1 (highest value):**

| Frame | Why |
|---|---|
| `lockon_midfight_*.png` ×3 | Locked on, enemy alive, mid-exchange. The single most important reference in the set — it is the framing question, the reticle question and the state-legibility question in one image. |
| `sword_swing_*.png` ×2 | Mid-slash, arc visible. Judges swing readability and trail/VFX weight. |
| `spin_attack.png` | The charged attack at full extension. |
| `shield_block.png` | Guarding, ideally taking a hit. |
| `enemy_telegraph.png` | An enemy in its wind-up, before the strike. Judges whether a threat is legible *early*. |
| `enemy_death.png` | The kill effect. |
| `player_hurt.png` | Damage feedback on the player. |
| `hearts_hud.png` | HUD density, placement, contrast over a bright background. |

**Later waves, useful now:**

| Frame | Why |
|---|---|
| `forest_establishing_*.png` ×3 | Composition, fog depth, canopy light, how a wooded bowl is framed. Directly comparable to the Greenhollow clearing. |
| `textbox.png` | Panel, framing, type size, how much world it covers. |
| `interior_*.png` ×2 | Dungeon lighting — later, but shapes the lighting decisions now. |

Prefer frames from **normal play at normal camera distance**, not cutscenes and
not a paused menu. The critic is judging what the player looks at for hours.

If you can drop a short video instead, that is better — frame counts are what
calibrate the bands below.

---

## Feel rubric — bands

**Read this before using the numbers.** These are *design targets derived from
how the reference plays*, not measured frame data. Ocarina of Time runs its
gameplay at 20 Hz, so its own timings are coarse multiples of 50 ms — a swing is
a handful of frames, not a smooth curve. Values below are stated in milliseconds
so they port to a 60 fps engine, and the 20 Hz-equivalent frame count is noted
where it matters.

Treat every band as **provisional until calibrated against footage**. Where a
band is a genuine estimate it is marked ~. Calibration procedure is at the bottom.

### Lock-on

| Measurement | Band | Note |
|---|---|---|
| Acquisition, press to locked | 50–150 ms | Must feel instant. Anything above ~200 ms reads as input lag. |
| Camera settle onto framing | 250–400 ms | ~ Eased, not linear. Snapping is nauseating; drifting loses the read. |
| Max lock range | 8–14 m | ~ Scale-dependent. Calibrate against the player capsule (r 0.4, h 1.8). |
| Break on distance, hysteresis | 1.5–3 m beyond acquire range | Must differ from acquire range or the lock flickers at the boundary. |
| Break on line-of-sight loss | 200–500 ms grace | ~ Instant break behind a tree is infuriating. |
| Target switch | under 120 ms | |
| Camera yaw rate while locked and strafing | keeps target within centre 40% of frame | This is the real test, not a rate number. |
| Both player and target on screen | 100% of locked frames | Non-negotiable. Any frame where either is off-screen is a bug. |

### Attacks

| Measurement | Band | Note |
|---|---|---|
| Wind-up, press to hitbox active | 80–150 ms | ~ Long enough to read, short enough to feel responsive. |
| Hitbox active window | 80–130 ms | |
| Total commitment, press to next input accepted | 300–500 ms | ~ Below 300 ms it mashes into noise; above 500 ms it feels stuck. |
| Cancel window into a defensive action | last 30–40% of recovery | Its absence is what makes hand-rolled combat feel like glue. |
| Charged attack, hold to charged | 900–1300 ms | ~ Needs an audible and visual tell at the threshold. |
| Combo link window | last 25–35% of recovery | |

### Hit feedback

| Measurement | Band | Note |
|---|---|---|
| Hitstop on connect | 60–120 ms | ~ 3–7 frames at 60 fps. The single highest-value number in combat feel. Freeze attacker and victim both. |
| Hit flash duration | 80–150 ms | |
| Knockback distance, light hit | 0.4–1.0 m | ~ |
| Knockback settle | under 350 ms | |
| Player i-frames after taking damage | 800–1500 ms | ~ Must exceed the fastest enemy attack cadence, or a player gets chain-hit with no out. |
| I-frame visual tell | present for the whole window | An invisible i-frame window is a bug even when the number is right. |
| Hit sfx latency from hitbox overlap | under 1 frame | |

### Enemies

| Measurement | Band | Note |
|---|---|---|
| Telegraph, tell to hitbox active | 400–700 ms | ~ Must exceed the player's total defensive commitment or the fight is unfair by construction. |
| Attack cadence at rest | 1200–2500 ms | ~ Compare against player i-frames above. |
| Vulnerability window after an attack | 500–900 ms | ~ The whole loop: bait, dodge, punish. |
| Aggro range | inside lock-on range | An enemy that engages before it can be locked is a camera fight. |
| Death to gone | 400–900 ms | ~ Long enough to register, short enough not to block the next enemy. |

### Cross-checks the numbers must survive

These matter more than any single band, and are what Mode 2 of the critic brief
asks about:

- **Enemy telegraph > player defensive commitment.** Otherwise blocking is a coin
  flip.
- **Player i-frames > enemy fastest cadence.** Otherwise chain damage with no out.
- **Attack commitment < enemy vulnerability window.** Otherwise the punish
  doesn't land and the loop has no payoff.
- **Camera settle < attack commitment.** Otherwise you swing before you can see.

---

## Calibrating a band from footage

When a band is marked ~ and it matters, replace the estimate with a count:

1. Take a clip of the reference at native rate.
2. Step frame by frame. Mark the frame the input visibly registers and the frame
   the effect starts.
3. Multiply the frame delta by 50 ms (20 Hz gameplay).
4. Replace the band here with the counted value ±1 frame, and drop the ~.

A counted number beats an argued one every time. `CLAUDE.md` Rule 3 exists
because this project has already lost time to the alternative.
