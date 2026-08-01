class_name PlayerAimState
extends PlayerState
## Drawing and loosing the bow.
##
## THE READABILITY PROBLEM, first, because it shaped the implementation. A drawn bow is a
## HELD POSE WITH NO MOTION, which is structurally identical to the weakest frame this
## project has produced: a blind critic given the charged sword beside its idle said "only
## the blade's colour changed — if the glow had been absent I would have called it IDLE
## with confidence 5 and been wrong." A tint cannot carry a held state. So the draw gets
## three cues and none of them is a colour:
##
##  1. A pose that cannot be idle — both arms out of the silhouette in OPPOSITE
##     directions, chest turned side-on, weight sunk. `bow_draw` in
##     tools/build_combat_anims.gd, with the whole argument written out there.
##  2. An opaque, black-outlined ARROW nocked on the string, which retracts along the aim
##     as the draw builds. A hard-edged prop leaving the silhouette, and the one cue that
##     also carries the *progress* of the draw rather than just its existence.
##  3. At full draw, the charge ring — already this project's hard-edged "wound up and
##     waiting" mark, converging onto the player over 110 ms, plus the same chime the
##     sword's charge threshold uses. Reused rather than reinvented so a player learns
##     one vocabulary.
##
## The arrow is the same object throughout: nocked, then reparented into the level on
## release with its world transform preserved. That is the dance the engine's own
## hand-tracking pickup demo does, and it means what a player sees drawn IS what flies —
## there is no second "visual" arrow to keep in sync.

@export var idle_state: PlayerState
@export var move_state: PlayerState
@export var air_state: PlayerState
## Fraction of top speed while drawing. Slower than a guard: an archer walking at speed
## is a different weapon.
@export_range(0.0, 1.0) var move_scale: float = 0.4
## How fast the character turns to face the camera while aiming.
@export var turn_speed: float = 14.0
## WHERE THE SHOT CONVERGES, rather than a direction it leaves in: a point this high above
## the player's feet, this far along the facing. The arrow is aimed from the bow THROUGH
## that point.
##
## Measured, not chosen. Aiming as a fixed direction out of the bow's own ArrowSpawn meant
## the shot ran parallel from wherever the hand happened to be, and the hand moves nearly a
## metre between nocking and full draw — so a tap fired from a pose that was still blending
## in went low and missed a target at 5 m that a full draw hit dead centre
## (`bow_tap_damage` measured 0 against `bow_arrow_damage` 2). Converging on a point makes
## the weapon aim the same at every instant of the draw, which is the only version a player
## can learn.
@export var aim_height: float = 1.3
@export var aim_distance: float = 8.0
## A little extra lift on top, paying for the arrow's own droop over that distance.
@export var launch_pitch_deg: float = 2.0
## How far back the nocked arrow travels between nocked and fully drawn, in metres. This
## is the motion cue, so it is deliberately large enough to see in a still frame.
@export var nock_pull: float = 0.42
## Where the arrow starts, along the aim, from the bow's ArrowSpawn. Positive is forward.
@export var nock_lead: float = 0.12

var _draw := 0.0
var _full := false
var _shooting := false
var _shot_elapsed := 0.0
var _arrow: Arrow = null
## Meshes tinted at full draw, and what they wore before. See `_tint_bow`.
var _tinted: Array[MeshInstance3D] = []
var _tint_rest: Array[Material] = []


func enter(_previous: StringName) -> void:
	# Consume the press that brought us here, or the buffer re-triggers the state.
	player.take_attack_request()
	_draw = 0.0
	_full = false
	_shooting = false
	_shot_elapsed = 0.0
	player.rig.rotation.y = player.camera_pivot.rotation.y + PI
	player.play_anim(&"bow_draw", 1.0)

	if player.loadout.ammo <= 0:
		# An empty bow draws nothing. Better to say so than to mime a full shot: an
		# animation that fires an arrow that does not exist is a lie about the game state.
		GameState.say("Out of arrows.")
		return
	_nock()


func exit() -> void:
	_clear_tell()
	if _arrow != null:
		# Only ever the UNFIRED arrow: a launched one was already reparented out of the
		# player, and `_arrow` was cleared at the same moment.
		_arrow.queue_free()
		_arrow = null


func physics_update(delta: float, on_floor: bool) -> PlayerState:
	if _shooting:
		_shot_elapsed += delta
	else:
		_tick_draw(delta)

	player.rig.rotation.y = lerp_angle(
		player.rig.rotation.y, player.camera_pivot.rotation.y + PI, turn_speed * delta)

	player.apply_gravity(delta, on_floor)
	player.tick_landing(on_floor)
	player.apply_movement(delta, on_floor, move_scale)
	player.move_and_slide()

	_place_nocked_arrow()

	if not on_floor:
		return air_state
	if _shooting and _shot_elapsed >= player.get_clip_length(&"bow_shoot"):
		return _resolve_exit()
	# An empty bow has nothing to release, so holding it is pointless — leave as soon as
	# the button comes up, with no recovery clip.
	if not _shooting and not Input.is_action_pressed("attack"):
		if player.loadout.ammo <= 0:
			return _resolve_exit()
		_release()
	return null


## The draw itself, plus the full-draw tell. `RangedWeapon.ms_draw` owns the timing.
func _tick_draw(delta: float) -> void:
	var bow := player.loadout.equipped as RangedWeapon
	if bow == null:
		return
	var seconds := maxf(bow.ms_draw / 1000.0, 0.001)
	_draw = clampf(_draw + delta / seconds, 0.0, 1.0)
	if _full or _draw < 1.0:
		return
	_full = true
	# Audible AND visible, on the same frame, because REFERENCE.md is explicit that a
	# threshold with only one of the two is a guess. The ring is the half with EDGES.
	player.sfx_cue_player.stream = player.sfx_charge_ready
	player.sfx_cue_player.volume_db = -8.0
	player.sfx_cue_player.play()
	if player.charge_ring != null:
		player.charge_ring.begin()
	if player.charge_glow != null:
		player.charge_glow.visible = true
	_tint_bow(true)


## The bow itself goes cyan at full draw, and this is the one cue here that IS a colour.
## It is not the cue the state relies on — the pose and the ground ring are — but it fixes
## the specific measured problem that a bow's silhouette is a LINE. Measured off a capture:
## the limbs are 3-5 px wide at the capture size and sit in dark wood right at the body's
## edge, where the background is rocks and water. Cyan at 0.94 luminance is visible there;
## brown at 0.3 is not.
##
## Cyan rather than any other hue because the vocabulary is already fixed: cyan means
## "wound up and waiting" (the sword's charge) and orange means "live". A fully drawn bow is
## the first of those.
func _tint_bow(on: bool) -> void:
	if not on:
		for i in _tinted.size():
			if is_instance_valid(_tinted[i]):
				_tinted[i].material_override = _tint_rest[i]
		_tinted.clear()
		_tint_rest.clear()
		return
	var weapon := player.loadout.instance()
	if weapon == null or not _tinted.is_empty():
		return
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_tinted.append(mesh)
		_tint_rest.append(mesh.material_override)
		mesh.material_override = player.blade_charged_material


## Loose. Power scales damage, never speed or range: an arrow that travelled a different
## distance depending on how long you held the button would make aiming a guess.
func _release() -> void:
	_shooting = true
	_shot_elapsed = 0.0
	_clear_tell()
	player.play_anim(&"bow_shoot", 1.0, true)

	var bow := player.loadout.equipped as RangedWeapon
	if bow == null or _arrow == null or not player.loadout.spend_ammo():
		return

	var power: float = lerpf(bow.min_power, 1.0, _draw)
	var direction := _aim_direction(bow)
	var launched := _arrow
	_arrow = null
	# Into the level, not the player: an arrow parented to the character would follow it,
	# and would die with it.
	var origin := launched.global_transform
	launched.get_parent().remove_child(launched)
	_level().add_child(launched)
	launched.lifetime = bow.projectile_lifetime
	launched.launch(origin, direction, bow.projectile_speed, roundi(bow.damage * power))

	player.sfx_blade_player.stream = player.sfx_swing
	player.sfx_blade_player.volume_db = -7.0
	player.sfx_blade_player.pitch_scale = randf_range(1.1, 1.25)
	player.sfx_blade_player.play()


## Where the shot goes.
##
## The fallback is the whole of the aiming today and has to work on its own: there is no
## lock-on system yet. It is the direction the CHARACTER faces — which the strafe above
## has already slaved to the camera — pitched up slightly to pay for the arrow's droop.
##
## The assist on top is dormant rather than speculative: `LockOnTarget` exists
## (components/lockon_target.gd), it sits on collision layer 9, and this finds it with a
## shape query rather than by walking the scene tree. With no enemies in the world the
## query returns nothing and the fallback is what ships. When lock-on lands, this is
## already connected.
func _aim_direction(bow: RangedWeapon) -> Vector3:
	var facing := player.rig.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var focus := player.global_position + Vector3.UP * aim_height + facing * aim_distance
	var aim := (focus - _muzzle()).normalized()
	aim = (aim + Vector3.UP * tan(deg_to_rad(launch_pitch_deg))).normalized()

	var marker := _best_target(bow, aim)
	if marker == null:
		return aim
	var target := marker.aim_point()
	var to_target := (target - _muzzle()).normalized()
	# Tapered by range, so distant targets still have to be aimed at. Straight lerp of two
	# unit vectors then renormalised: for the small angles an assist should be correcting,
	# it is indistinguishable from a slerp and cannot flip near 180 degrees.
	var distance := _muzzle().distance_to(target)
	var falloff := 1.0 - clampf(distance / maxf(bow.assist_range, 0.01), 0.0, 1.0)
	return aim.lerp(to_target, bow.lockon_assist * falloff).normalized()


## The nearest lock-on marker that is roughly where the player is pointing, or null.
## Layer 9 is `lockon_target`; the query collides with areas only, because that is what a
## marker is.
func _best_target(bow: RangedWeapon, aim: Vector3) -> LockOnTarget:
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = bow.assist_range
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _muzzle())
	query.collision_mask = 1 << 8
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var best: LockOnTarget = null
	var best_dot := 0.55  # roughly a 57-degree cone: an assist, not a homing missile.
	for hit in space.intersect_shape(query, 16):
		var marker := hit["collider"] as LockOnTarget
		if marker == null or not marker.is_valid():
			continue
		var dot := aim.dot((marker.aim_point() - _muzzle()).normalized())
		if dot > best_dot:
			best_dot = dot
			best = marker
	return best


## Where an arrow leaves from: the bow's own ArrowSpawn if it has one, and the chest
## otherwise, so a bow scene without the marker still shoots from somewhere sensible.
func _muzzle() -> Vector3:
	var spawn := player.loadout.part(&"ArrowSpawn") as Node3D
	if spawn != null:
		return spawn.global_position
	return player.global_position + Vector3.UP * 1.2


func _nock() -> void:
	var bow := player.loadout.equipped as RangedWeapon
	if bow == null or bow.projectile == null:
		return
	_arrow = bow.projectile.instantiate() as Arrow
	if _arrow == null:
		return
	_arrow.nock()
	# A child of the Player rather than of the grip, and this is not a stylistic choice:
	# Rig/Character is scaled x2, so an arrow parented under the hand would be drawn 1.8 m
	# long. Its global transform is written every tick instead.
	player.add_child(_arrow)
	_place_nocked_arrow()


## Slide the nocked arrow back along the aim as the draw builds. This is the cue that
## carries the draw's PROGRESS, and the reason it is geometry rather than a tint.
func _place_nocked_arrow() -> void:
	if _arrow == null:
		return
	var bow := player.loadout.equipped as RangedWeapon
	if bow == null:
		return
	var aim := _aim_direction(bow)
	var origin := _muzzle() + aim * (nock_lead - nock_pull * _draw)
	# look_at aims -Z, which is the axis items/arrow.tscn is authored down.
	_arrow.global_position = origin
	_arrow.look_at(origin + aim, Vector3.UP)


func _clear_tell() -> void:
	_full = false
	_tint_bow(false)
	if player.charge_ring != null:
		player.charge_ring.stop()
	if player.charge_glow != null:
		player.charge_glow.visible = false


## Where a fired arrow lives. The player's own parent, so arrows belong to the room and
## are torn down with it.
func _level() -> Node:
	return player.get_parent()


func _resolve_exit() -> PlayerState:
	if player.get_horizontal_speed() > player.walk_anim_threshold:
		return move_state
	return idle_state
