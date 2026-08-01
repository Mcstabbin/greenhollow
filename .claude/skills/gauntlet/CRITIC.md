# The critic brief

Two modes. Spawn a **new** subagent for every critique — a critic that has seen
the builder's reasoning is not a critic. Never tell it which artefact is ours.
Never give it repo access in visual mode.

---

## Mode 1 — blind visual A/B

Set up: copy one capture and one reference frame into a fresh temp dir as
`a.png` and `b.png`. **Vary which is which every round** — if ours is always `a`
the critic learns the tell. Record the mapping yourself; do not write it into the
temp dir.

Paste this to the subagent, filling `<DIR>` and `<SUBJECT>`:

> Read the two images `<DIR>/a.png` and `<DIR>/b.png`. Both are frames from
> third-person 3D action-adventure games, showing `<SUBJECT>`.
>
> You are a harsh art director. Your job is to say which frame is better
> *composed and clearer to play from*, and you are hard to impress.
>
> **Do not attempt to identify either game, guess which is older, or reason
> about which is a commercial release.** Resolution, texture filtering and
> polygon count are off the table — you are grading craft, not hardware. If you
> catch yourself thinking "this one is a real game so it wins", discard that
> thought and go back to the axes.
>
> Score each frame 1–5 on each axis and say which frame wins the axis:
>
> 1. **Silhouette clarity** — can you separate character, enemy and background at
>    a glance? Do the shapes read against what is behind them?
> 2. **Action legibility** — from this single frame, is it obvious what is
>    happening and what the player should do next?
> 3. **State legibility** — is it clear what mode the player is in (locked on,
>    mid-swing, guarding, hurt)? Is the target unambiguous?
> 4. **Framing** — is the camera showing the right thing at the right distance?
>    Are player and threat both readable? Is anything important clipped or
>    occluded?
> 5. **Colour composition** — does the palette direct the eye to what matters, or
>    does the background compete with the action?
> 6. **Depth read** — can you tell how far apart things are, and what is
>    standable?
>
> Then:
> - **Overall winner**, and whether it is a clear win or a coin flip.
> - For the **losing** frame: the single largest change that would flip the
>   verdict. Concrete and visual — "the enemy's silhouette dissolves into the
>   treeline behind it", not "improve the art".
> - Anything in the losing frame that is outright broken or confusing.
>
> Be blunt. A coin flip is a loss.

**Honest limit:** the critic can often still tell which frame is which, and its
own knowledge of famous games leaks in. The 640×480 capture and the
grade-named-axes instruction are what keep the verdict useful anyway — a
per-axis gap is actionable whether or not the critic guessed. Do not pretend the
blindness is airtight. Do not accept "B is clearly a professional game" as a
verdict; re-spawn and demand the axes.

---

## Mode 2 — measured feel

For anything with a number: attack commitment, lock-on acquisition, camera turn
rate, hitstop, i-frames, knockback. No screenshots. Give the critic the probe's
JSON output and the bands from [REFERENCE.md](REFERENCE.md), and nothing else.

> Here is measured output from a third-person action game's combat system, and
> the target bands it is being held to. For each measurement: state whether it is
> inside the band, and if not, by how much and in which direction.
>
> Then, ignoring the bands for a moment, reason about the numbers *as a set*:
> which combination will feel wrong in play even though each value passes alone?
> Attack commitment against enemy telegraph length, i-frame window against
> enemy attack cadence, camera turn rate against strafe speed — that is where
> combat feel actually breaks.
>
> Name the single worst number and what it will feel like in the player's hands.
> Verdict: pass or fail. A measurement that is inside its band but wrong against
> its neighbours is a fail.

## Mode 3 — integration pass, wave end

One critic, fresh context, given every capture from the wave plus the full probe
output. Repo access is fine here.

> These frames and measurements are the whole of one system in a 3D
> action-adventure. Judge it as a *whole*: does it read as one designed thing, or
> as separate features that happen to coexist? Name inconsistencies — timings
> that disagree, visual languages that clash, states with no feedback, feedback
> with no state. What is missing that a player would immediately reach for and
> not find?

## Rules for whoever is running the loop

- One critic per piece per round. Do not reuse a critic across rounds; it
  remembers its last verdict and softens.
- If a critic passes something on the first round, be suspicious. Spawn a second
  with a different axis emphasis before believing it.
- A critic's verdict is data, not an order. If it is confidently wrong about the
  engine or the code, check before acting — but do not use "the critic is wrong"
  as a way to dismiss a gap you don't want to fix.
- Log which gap came from which critic so a recurring gap is visible. Same
  blocker three rounds running with no new strategy means change the approach,
  not the round count.
