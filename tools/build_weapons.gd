extends SceneTree
## Generates the four weapon scenes into items/weapons/.
##
## Run:  godot --headless --path . --script res://tools/build_weapons.gd
##
## Same approach as build_clearing.gd and build_combat_anims.gd: emit real,
## hand-editable scenes rather than hand-authoring four near-identical .tscn files
## and keeping their node contracts in sync by eye.
##
## Every weapon presents the SAME node contract, because `components/loadout.gd`
## instantiates one under the player's grip and the player must not know which
## weapon it is holding:
##
##   <Weapon>            Node3D, the root
##     ...meshes         weapon-specific, cast_shadow off
##     HitBox            Area3D + Shape, layer 5 / mask 6, monitoring OFF at rest
##                       (melee only — a shield has no hitbox and a bow's damage
##                        rides on the arrow)
##     BladeBase/BladeTip  Node3D markers the trail samples between
##     ChargeGlow        OmniLight3D, hidden until a charge threshold fires
##     ArrowSpawn        Node3D, ranged only
##
## Proportions note, learned the hard way: the character is scaled x2, so every
## number here reads at twice its value in the world. A 0.42 blade is 0.84 m on a
## 2.2 m character, and the earlier 0.3 was proportionally a dagger that a critic
## looking at a gameplay-camera frame could not find at all.
##
## Silhouettes are deliberately different from each other. The readability rounds
## established that an action has to break the body's outline to read from an
## over-the-shoulder camera, so a straight blade, a top-heavy wedge, a tall thin arc
## and a broad slab are four distinguishable shapes rather than four swords.

const OUT_DIR := "res://items/weapons"
const MAT_WOOD := "res://art/materials/toon_wood.tres"
const MAT_GOLD := "res://art/materials/toon_gold.tres"
const HITBOX_SCRIPT := "res://actors/player/sword_hit_box.gd"

## Layer 5 player_hitbox, mask 6 enemy_hurtbox — names are in project.godot.
const HITBOX_LAYER := 16
const HITBOX_MASK := 32

## Markedly darker and cooler than the white torso it swings across. The original
## 0.79/0.84/0.90 steel sat within a few percent of the body's value, so at rest
## the blade merged into the chest it hangs in front of.
const STEEL := Color(0.42, 0.5, 0.66)
## Charge tell. Cyan so "charged and waiting" can never read as "blade live" —
## the swing owns the warm hue because it is the one fighting a green background.
const CHARGE_CYAN := Color(0.5, 0.96, 1.0)



func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var built := 0
	built += _emit("sword", _build_sword())
	built += _emit("axe", _build_axe())
	built += _emit("bow", _build_bow())
	built += _emit("shield", _build_shield())

	print("build_weapons: wrote %d weapon scene(s) to %s" % [built, OUT_DIR])
	quit(0 if built == 4 else 1)


# --- Weapons ----------------------------------------------------------------

## The reference weapon. Mirrors what player.tscn currently holds inline, so
## equipping it is a no-visual-change swap and the inline copy can be deleted.
func _build_sword() -> Node3D:
	var root := _weapon_root("Sword")
	_mesh(root, "Handle", _box(0.06, 0.14, 0.06), Vector3(0, 0.04, 0), _load_mat(MAT_WOOD))
	_mesh(root, "Guard", _box(0.28, 0.05, 0.08), Vector3(0, 0.125, 0), _load_mat(MAT_GOLD))
	_mesh(root, "Blade", _box(0.135, 0.42, 0.045), Vector3(0, 0.35, 0), _steel())
	_melee_hitbox(root, Vector3(0, 0.35, 0), 0.13, 0.42)
	_trail_markers(root, 0.14, 0.6)
	_charge_glow(root, Vector3(0, 0.36, 0))
	return root


## Heavier and top-weighted. Reach is close to the sword's, but the mass sits at
## the head, which is what makes the slower wind-up read as *weight* rather than as
## input lag. Damage, timing and knockback are NOT here — they live in the .tres,
## which is the whole point of the data model.
func _build_axe() -> Node3D:
	var root := _weapon_root("Axe")
	_mesh(root, "Handle", _box(0.055, 0.46, 0.055), Vector3(0, 0.2, 0), _load_mat(MAT_WOOD))
	# Head as two pieces: a blocky cheek and a wedge that reads as an edge. Offset
	# to one side so the silhouette is asymmetric — symmetry kills the read of
	# motion, which a critic said of the spin attack in as many words.
	# The outer piece is TALLER than the inner one, which is what makes the head read
	# as a flaring axe blade. Equal heights made it a rectangle on a stick — the first
	# render looked like a flag, not an axe.
	_mesh(root, "HeadCheek", _box(0.09, 0.17, 0.085), Vector3(0.05, 0.42, 0), _steel())
	_mesh(root, "HeadEdge", _box(0.1, 0.27, 0.05), Vector3(0.14, 0.42, 0), _steel())
	_mesh(root, "Butt", _box(0.075, 0.05, 0.075), Vector3(0, 0.47, 0), _load_mat(MAT_GOLD))
	# Bigger than the sword's, matched to the head rather than the handle: the axe
	# only threatens where its head is.
	_melee_hitbox(root, Vector3(0.1, 0.42, 0), 0.17, 0.24)
	_trail_markers(root, 0.3, 0.55)
	_charge_glow(root, Vector3(0.1, 0.42, 0))
	return root


## A tall thin arc, so it cannot be mistaken for either blade at a glance. Limbs
## are three angled segments rather than a curve — the outline pass finds edges, and
## a faceted limb reads as a bow while costing four boxes.
func _build_bow() -> Node3D:
	var root := _weapon_root("Bow")
	_mesh(root, "Grip", _box(0.05, 0.16, 0.06), Vector3(0, 0.0, 0), _load_mat(MAT_WOOD))
	var limb := _load_mat(MAT_WOOD)
	_mesh(root, "UpperLimbA", _box(0.04, 0.2, 0.05), Vector3(0.015, 0.17, 0), limb,
		Vector3(0, 0, deg_to_rad(-7)))
	_mesh(root, "UpperLimbB", _box(0.035, 0.17, 0.045), Vector3(0.05, 0.33, 0), limb,
		Vector3(0, 0, deg_to_rad(-20)))
	_mesh(root, "LowerLimbA", _box(0.04, 0.2, 0.05), Vector3(0.015, -0.17, 0), limb,
		Vector3(0, 0, deg_to_rad(7)))
	_mesh(root, "LowerLimbB", _box(0.035, 0.17, 0.045), Vector3(0.05, -0.33, 0), limb,
		Vector3(0, 0, deg_to_rad(20)))
	# The string is the bow's most identifying line and the thinnest thing here, so
	# it gets a bright warm value rather than wood: a dark hairline against a dark
	# treeline is invisible, and the string is what tells a viewer it is drawn.
	var string_mat := StandardMaterial3D.new()
	string_mat.resource_name = "bow_string"
	string_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	string_mat.albedo_color = Color(0.96, 0.93, 0.8)
	_mesh(root, "String", _box(0.012, 0.84, 0.012), Vector3(0.085, 0, 0), string_mat)

	# Where the arrow leaves from. On the string, not the grip, so a drawn arrow
	# and its launch point agree.
	var spawn := Node3D.new()
	spawn.name = "ArrowSpawn"
	spawn.position = Vector3(0.085, 0, 0)
	_add(root, spawn)

	_charge_glow(root, Vector3(0.05, 0, 0))
	return root


## A broad slab — the most distinct silhouette of the four, and deliberately so:
## with one equip slot, "am I holding the shield" is a question the player answers
## from the frame rather than from a HUD.
func _build_shield() -> Node3D:
	var root := _weapon_root("Shield")
	var face := StandardMaterial3D.new()
	face.resource_name = "shield_face"
	face.albedo_color = Color(0.33, 0.46, 0.68)
	face.roughness = 1.0
	face.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	face.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	_mesh(root, "Face", _box(0.34, 0.44, 0.045), Vector3.ZERO, face)
	_mesh(root, "RimTop", _box(0.36, 0.04, 0.055), Vector3(0, 0.22, 0), _load_mat(MAT_GOLD))
	_mesh(root, "RimBottom", _box(0.28, 0.04, 0.055), Vector3(0, -0.22, 0), _load_mat(MAT_GOLD))
	_mesh(root, "Boss", _box(0.1, 0.1, 0.07), Vector3(0, 0.02, 0.03), _load_mat(MAT_GOLD))

	# No HitBox: blocking is a state, not a swing. A shield-bash would add one, and
	# would be a MeleeWeapon-shaped addition rather than a change here.
	# Reuses ChargeGlow as the deflect flash — same node, same hidden-by-default
	# contract, so the player needs no shield-specific lookup.
	_charge_glow(root, Vector3(0, 0, 0.12))
	return root


# --- Contract pieces --------------------------------------------------------

func _weapon_root(name_hint: String) -> Node3D:
	var root := Node3D.new()
	root.name = name_hint
	return root


func _melee_hitbox(root: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var area := Area3D.new()
	area.name = "HitBox"
	area.position = pos
	area.collision_layer = HITBOX_LAYER
	area.collision_mask = HITBOX_MASK
	# Off at rest. The clips' _anim_hitbox_on keyframe arms it, which is what keeps
	# the active window in the same place as the animation it has to match.
	area.monitoring = false
	area.set_script(load(HITBOX_SCRIPT))
	_add(root, area)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	# Radius matched to the mesh's own half-width rather than kept thinner than it.
	# A third-of-the-mesh capsule left a swing reaching a target in front by about a
	# centimetre.
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0 + 0.01)
	shape.shape = capsule
	_add(area, shape)


## The two points the trail ribbon spans. Named for the sword because the sword is
## the reference; an axe's "blade" is its head and a bow has none.
func _trail_markers(root: Node3D, base_y: float, tip_y: float) -> void:
	for pair in [["BladeBase", base_y], ["BladeTip", tip_y]]:
		var marker := Node3D.new()
		marker.name = String(pair[0])
		marker.position = Vector3(0, float(pair[1]), 0)
		_add(root, marker)


func _charge_glow(root: Node3D, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "ChargeGlow"
	light.position = pos
	light.visible = false
	light.light_color = CHARGE_CYAN
	# Bright enough to tint the grass. A 2.2-energy light was not, and a charge
	# threshold has to be visible as well as audible.
	light.light_energy = 4.0
	light.shadow_enabled = false
	light.omni_range = 1.4
	_add(root, light)


# --- Plumbing ---------------------------------------------------------------

func _mesh(
	root: Node3D, name_hint: String, mesh: Mesh, pos: Vector3, mat: Material,
	rot: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_hint
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	# Weapons do not cast shadows: they are small, they move fast, and a flickering
	# shadow on the character reads as a rendering fault rather than as a sword.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	_add(root, mi)
	return mi


func _box(x: float, y: float, z: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x, y, z)
	return mesh


func _steel() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "toon_steel"
	mat.albedo_color = STEEL
	mat.roughness = 0.6
	# LAMBERT_WRAP, not TOON: toon's hard terminator collapses away-facing surfaces
	# to flat ambient, which on a thin blade means half of it disappears.
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


func _load_mat(path: String) -> Material:
	var mat := load(path) as Material
	if mat == null:
		push_error("build_weapons: could not load %s" % path)
	return mat


## Parent only. Ownership cannot be assigned meaningfully until the whole tree
## exists, so `_emit` re-owns depth-first against the finished root. Getting this
## wrong is silent: `PackedScene.pack()` drops unowned nodes with no warning and no
## error, which is why `_emit` round-trips the node count afterwards.
func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)


func _emit(file_name: String, root: Node3D) -> int:
	# Owner must be the scene root, and it can only be assigned once the whole tree
	# exists, so re-own depth-first here rather than guessing during construction.
	_own_recursive(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("build_weapons: pack failed for %s" % file_name)
		return 0

	var path := "%s/%s.tscn" % [OUT_DIR, file_name]
	if ResourceSaver.save(packed, path) != OK:
		push_error("build_weapons: save failed for %s" % path)
		return 0

	# Round-trip check. pack() drops unowned nodes without complaint, so compare the
	# node count that came back against the tree that went in.
	var expected := _count(root)
	var reloaded: Node = (load(path) as PackedScene).instantiate()
	var actual := _count(reloaded)
	reloaded.free()
	if expected != actual:
		push_error("build_weapons: %s packed %d of %d nodes — an owner is missing"
			% [file_name, actual, expected])
		return 0

	print("  %s: %d nodes" % [path, actual])
	# Free the built tree: this is a one-shot CLI tool, but leaked-RID spam at exit
	# is noise that hides real errors in the same output.
	root.free()
	return 1


func _own_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		# Stop at instanced-scene boundaries, or a sub-scene gets flattened into
		# this one. Not relevant yet — these are all built from primitives — but it
		# is the generalised form of the .glb gotcha in CLAUDE.md.
		if child.scene_file_path.is_empty():
			_own_recursive(child, scene_root)


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
