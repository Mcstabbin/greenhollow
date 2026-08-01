class_name LockOnSystem
extends Area3D
## Z-target lock-on: hold on to the thing you are looking at.
##
## Design taken end-to-end from Snaiel's Godot4ThirdPersonCombatPrototype (MIT) —
## see .claude/skills/gauntlet/PRIOR-ART.md, which is the Rule 1 pass for this
## feature. Three of its decisions are load-bearing and are the reason this file
## exists rather than a distance check inlined into the player:
##
##  1. **Selection is scored in SCREEN SPACE, by distance from the centre of the
##     viewport — not in 3D.** That single choice is what makes Ocarina-style
##     targeting feel right: it locks what you are *looking at*, not what you
##     happen to be nearest to. The probe proves the difference directly
##     (`lockon_picks_screen_centre`): given a target 9 m away dead ahead and one
##     6 m away well off to the side, this picks the far one.
##  2. **Broad phase is a persistent overlap list, scoring runs on the press.**
##     This Area3D is a sphere the size of the BREAK range that travels with the
##     player; `area_entered`/`area_exited` keep `_targets` up to date, and the
##     screen-space scoring — which costs an `unproject_position` per candidate —
##     only runs when the button is pressed or a switch is requested.
##  3. **Validity is a frustum test plus a ray from the CAMERA**, not from the
##     player. A creature the player could touch but the camera cannot see is not
##     lockable, and that is the correct answer: the lock is a camera contract.
##
## Two things Snaiel does that are deliberately NOT copied. It has no hysteresis,
## so a target hovering at the range boundary flickers in and out; acquire and
## break are separate numbers here. And its LOS is checked only at acquisition, so
## a lock survives the target walking behind a wall — this checks continuously,
## with a grace period, because an instant break behind a tree is infuriating
## (REFERENCE.md's band is 200-500 ms).
##
## Ranges are OURS, not Snaiel's. His 20 m acquire radius would lock half of a
## level whose whole play area is ±24 m. REFERENCE.md's band is 8-14 m.
##
## Deliberately knows nothing about the Player type: it is given a body and a
## camera. That keeps it testable, keeps a script dependency cycle closed, and is
## the direct answer to PRIOR-ART.md's complaint that Snaiel's own `LockOnSystem`
## reaches five levels deep into other systems and so can be neither tested nor
## reused.

## A target was acquired, or the lock moved to a different target. The HUD reticle
## is driven from this.
signal locked(target: LockOnTarget)
## The lock ended — released by the player, or broken by range, sight-line or death.
signal released()

## Collision layer 9, "lockon_target". Matches `LockOnTarget.LAYER`.
const TARGET_MASK := 1 << 8
## Layer 1, "world". What can break a sight-line: terrain, houses, tree trunks.
## Deliberately not the interactable layer — a lock should not break behind a sign.
const WORLD_MASK := 1

## Furthest a lock can be ACQUIRED, in metres. REFERENCE.md's band is 8-14 m,
## against a play area of ±24 m and a player capsule of r 0.4 / h 1.8.
@export var acquire_range: float = 12.0
## Furthest an existing lock is RETAINED. Must exceed `acquire_range` or the lock
## flickers on and off for anything sitting exactly at the boundary — the failure
## REFERENCE.md calls out by name. The gap is the hysteresis; its band is 1.5-3 m.
@export var break_range: float = 14.5
## Seconds the target may stay out of sight before the lock breaks. Instant is
## infuriating: it means you cannot walk behind your own scenery.
@export var los_grace: float = 0.35
## How far the look axis has to be pushed before it counts as a switch request,
## and how long before another one is accepted. Snaiel uses 0.2 with a 0.5 s
## debounce; 0.5 and 0.3 here because our switch is also bound to the camera
## stick, which is idle-centred rather than held.
@export_range(0.0, 1.0) var switch_threshold: float = 0.5
@export var switch_cooldown: float = 0.3

## The camera lock-on is a contract with. Selection, the frustum test and the
## sight-line ray are all measured from here.
@export var camera: Camera3D
## Whose position range is measured from — the player body. Separate from the
## camera on purpose: range is a gameplay number and belongs to the character,
## while visibility is the camera's business.
@export var body: Node3D

## The current lock, or null. Read it; do not assign it.
var target: LockOnTarget = null

## Everything currently inside the detection sphere, valid or not. Validity is
## re-tested at scoring time rather than filtered here, so a creature that becomes
## targetable again without ever leaving the sphere comes back into contention.
var _targets: Array[LockOnTarget] = []
var _los_timer := 0.0
var _switch_timer := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = TARGET_MASK
	monitoring = true
	monitorable = false

	# Built in code, and sized from `break_range` rather than authored: the sphere
	# IS the retention range, so the two can never disagree. A target that leaves
	# the sphere is exactly a target that is out of break range.
	if get_child_count() == 0:
		var shape := SphereShape3D.new()
		shape.radius = break_range
		var holder := CollisionShape3D.new()
		holder.name = "Shape"
		holder.shape = shape
		add_child(holder)

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


## Toggle, the way Z-targeting works: press to grab the best candidate, press
## again to let go. Returns true if there is a lock afterwards.
func press() -> bool:
	if target != null:
		release()
		return false
	return acquire()


## Grab the best candidate under the STRICT rule — in the frustum, inside
## `acquire_range`, and visible. Returns false when there is nothing to lock.
func acquire() -> bool:
	var best := _pick_centred()
	if best == null:
		return false
	_set_target(best)
	return true


func release() -> void:
	if target == null:
		return
	target = null
	_los_timer = 0.0
	released.emit()


func is_locked() -> bool:
	return target != null and is_instance_valid(target)


## Where the camera and the character should aim. Falls back to the body's own
## position so a caller never has to null-check before doing arithmetic.
func target_point() -> Vector3:
	if not is_locked():
		return body.global_position if body != null else global_position
	return target.aim_point()


## Move the lock to the next target in a screen direction. `axis` is a signed look
## input: positive is screen-right. Returns true if the lock actually moved.
##
## Validity is LOOSER here than at acquisition — merely "not behind the camera"
## rather than a full frustum test — so you can flick onto something just off the
## edge of the frame instead of having to turn first. That asymmetry is Snaiel's
## and it is the right way round.
func try_switch(axis: float) -> bool:
	if not is_locked() or _switch_timer > 0.0 or absf(axis) < switch_threshold:
		return false
	if camera == null:
		return false
	var from := camera.unproject_position(target.aim_point())
	var want := signf(axis)
	var best: LockOnTarget = null
	var best_gap := INF
	for candidate in _targets:
		if candidate == target or not _usable(candidate, break_range):
			continue
		if camera.is_position_behind(candidate.aim_point()):
			continue
		var at := camera.unproject_position(candidate.aim_point())
		var gap := (at.x - from.x) * want
		if gap <= 0.0:
			continue  # the wrong side of the current target
		if gap < best_gap:
			best_gap = gap
			best = candidate
	if best == null:
		return false
	_switch_timer = switch_cooldown
	_set_target(best)
	return true


## Re-test the lock. Called once per physics tick by the player, before the camera
## is updated, so a lock that has just broken never gets a frame of framing.
func tick(delta: float) -> void:
	_switch_timer = maxf(_switch_timer - delta, 0.0)
	if not is_locked():
		return
	if not target.is_valid():
		release()
		return
	var aim := target.aim_point()
	if body != null and body.global_position.distance_to(aim) > break_range:
		release()
		return
	if _blocked(aim, target):
		_los_timer += delta
		if _los_timer >= los_grace:
			release()
		return
	_los_timer = 0.0


## How many candidates are inside the sphere and currently lockable. Read by
## tools/probe.gd; nothing in the game needs it.
func candidate_count() -> int:
	var count := 0
	for candidate in _targets:
		if _usable(candidate, break_range):
			count += 1
	return count


# --- Selection ------------------------------------------------------------

## The candidate nearest the centre of the screen. THE load-bearing function: this
## is why targeting feels like it reads your intent rather than your position.
func _pick_centred() -> LockOnTarget:
	if camera == null:
		return null
	var centre := Vector2(camera.get_viewport().get_visible_rect().size) * 0.5
	var best: LockOnTarget = null
	var best_distance := INF
	for candidate in _targets:
		if not _usable(candidate, acquire_range):
			continue
		var aim := candidate.aim_point()
		# Strict for acquisition: it must genuinely be in shot. `is_position_behind`
		# alone would happily lock something 40 degrees off the edge of the frame.
		if not camera.is_position_in_frustum(aim):
			continue
		if _blocked(aim, candidate):
			continue
		var distance := centre.distance_to(camera.unproject_position(aim))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## In the tree, alive, targetable, and within `range_limit` of the body.
func _usable(candidate: LockOnTarget, range_limit: float) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if not candidate.is_valid():
		return false
	if body == null:
		return true
	return body.global_position.distance_to(candidate.aim_point()) <= range_limit


## Is the sight-line from the CAMERA to this point interrupted by world geometry?
##
## The creature's own body is excluded, and that is not a nicety: an aim point sits
## inside the chest, so a ray from outside always terminates on the creature's own
## collision shape and every target would read as hidden. This is the reason enemy
## bodies belong on layer 4 rather than layer 1 — but excluding the RID as well
## means a body that lands on the world layer by mistake still cannot hide its own
## owner's chest.
func _blocked(point: Vector3, candidate: LockOnTarget) -> bool:
	if camera == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point)
	query.collision_mask = WORLD_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var actor := candidate.actor as CollisionObject3D
	if actor != null:
		query.exclude = [actor.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _set_target(next: LockOnTarget) -> void:
	target = next
	_los_timer = 0.0
	locked.emit(target)


# --- Broad phase ----------------------------------------------------------

func _on_area_entered(area: Area3D) -> void:
	var candidate := area as LockOnTarget
	if candidate == null or _targets.has(candidate):
		return
	_targets.append(candidate)
	# Not `_targets.erase` on `lost`: a creature that becomes untargetable and then
	# targetable again never leaves the sphere, so removing it here would retire it
	# permanently. Membership is overlap; validity is re-tested when scoring.
	if not candidate.lost.is_connected(_on_target_lost):
		candidate.lost.connect(_on_target_lost)


func _on_area_exited(area: Area3D) -> void:
	var candidate := area as LockOnTarget
	if candidate == null:
		return
	_targets.erase(candidate)
	if is_instance_valid(candidate) and candidate.lost.is_connected(_on_target_lost):
		candidate.lost.disconnect(_on_target_lost)
	if candidate == target:
		release()


func _on_target_lost(lost_target: LockOnTarget) -> void:
	if lost_target == target:
		release()
