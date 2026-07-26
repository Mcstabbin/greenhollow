extends SceneTree
## Generates world/rooms/greenhollow_clearing.tscn.
##
## Run:  godot --headless --path . --script res://tools/build_clearing.gd
##
## This emits a REAL, hand-editable scene file. Re-running overwrites it, so once
## you start moving things by hand in the editor, either stop running this or
## fold your changes back in here. Layout lives in the build_* functions;
## decoration is seeded RNG so the result is identical every run.
##
## Design notes, learned the hard way from screenshots:
##  - Enclosure beats size. A wide play area with sparse props reads as a lawn.
##  - Vegetation clusters in nature. Uniform scatter reads as litter.
##  - One flat colour across 300 trees looks synthetic; tint per instance.
##  - Flat ground is the single biggest killer of a "place". Add mounds.

const OUT_PATH := "res://world/rooms/greenhollow_clearing.tscn"
const NATURE := "res://art/models/nature/%s.glb"
const SEED := 20260725

const HALF := 46.0          # ground extends +/- this (well past the treeline)
const PLAY := 24.0          # invisible wall radius — keep this TIGHT
const RIVER_Z := -2.0
const RIVER_HALF_W := 2.5
const RIVER_DEPTH := 0.7
## The whole terrain is yawed so the stream cuts diagonally instead of running
## dead-straight across the map on the Z axis.
const RIVER_YAW := 0.28  # ~16 degrees

# Kenney's leafsGreen is a mint teal that reads as ice at forest scale.
const LEAF_COLOURS := [
	Color(0.45, 0.76, 0.40), Color(0.55, 0.83, 0.43), Color(0.37, 0.67, 0.43),
	Color(0.63, 0.85, 0.45), Color(0.49, 0.79, 0.52), Color(0.70, 0.86, 0.46),
]
const LEAF_AUTUMN := [Color(0.90, 0.63, 0.26), Color(0.84, 0.52, 0.24)]
const BARK_COLOURS := [
	Color(0.60, 0.45, 0.32), Color(0.67, 0.52, 0.36), Color(0.54, 0.41, 0.30),
]

const CANOPY := ["tree_default", "tree_oak", "tree_fat", "tree_detailed",
	"tree_tall", "tree_thin", "tree_blocks", "tree_pineRoundC"]

var _root: Node3D
var _rng := RandomNumberGenerator.new()
var _aabb_cache := {}
var _mesh_cache := {}
var _mat_cache := {}
var _keepouts: Array = []
var _terrain: Node3D          # yawed; children use terrain-local coords


func _initialize() -> void:
	_rng.seed = SEED
	_root = Node3D.new()
	_root.name = "clearingForest"
	_root.set_script(load("res://world/rooms/greenhollow_clearing.gd"))

	build_environment()
	build_ground()
	build_bounds()

	var world := Node3D.new()
	world.name = "World"
	_root.add_child(world)
	world.owner = _root

	build_mounds(world)
	build_deku_tree(world)
	build_village(world)
	build_river(world)
	build_lookout(world)
	build_gate(world)
	# Before scatter, so decoration keeps clear of anything interactive.
	build_gameplay(world)
	build_perimeter(world)
	build_scatter(world)
	build_actors()

	var packed := PackedScene.new()
	if packed.pack(_root) != OK:
		push_error("pack failed")
		quit(1)
		return
	if ResourceSaver.save(packed, OUT_PATH) != OK:
		push_error("save failed")
		quit(1)
		return
	print("wrote %s" % OUT_PATH)
	print("  nodes: %d" % _count(_root))
	quit()


func _count(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count(c)
	return total


# --- helpers -----------------------------------------------------------------

func _own(n: Node) -> void:
	n.owner = _root


func _model_aabb(model: String) -> AABB:
	if _aabb_cache.has(model):
		return _aabb_cache[model]
	var probe := (load(NATURE % model) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for c in probe.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var a := mi.get_aabb()
		a.position += mi.position
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	probe.free()
	_aabb_cache[model] = box
	return box


## Raw meshes + local transforms for a model, so props can be built as plain
## MeshInstance3D nodes we own.
##
## Instancing the .glb scene instead looks tempting, but property changes on
## nodes INSIDE an instanced sub-scene are not recorded when packing unless the
## node is owned — which silently threw away every per-instance tint.
func _meshes_of(model: String) -> Array:
	if _mesh_cache.has(model):
		return _mesh_cache[model]
	var probe := (load(NATURE % model) as PackedScene).instantiate()
	var out: Array = []
	for c in probe.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh != null:
			out.append({"mesh": mi.mesh, "xform": mi.transform})
	probe.free()
	_mesh_cache[model] = out
	return out


## Shared material per (source, colour) pair. Duplicating per instance would
## write thousands of near-identical materials into the scene file.
func _mat_for(src: StandardMaterial3D, colour: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [src.resource_name, colour.to_html(false)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := src.duplicate() as StandardMaterial3D
	m.albedo_color = colour
	m.roughness = 1.0
	# LAMBERT_WRAP, not TOON: toon's hard terminator collapses every away-facing
	# surface to flat ambient and turns the whole forest grey.
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mat_cache[key] = m
	return m


## `collide` is "none", "box", or "trunk". Scale applies to the mesh only;
## collision shapes are sized in world units so no physics body is ever scaled.
func _prop(
	parent: Node, model: String, pos: Vector3, yaw: float, s: float,
	collide: String = "none", name_hint: String = ""
) -> Node3D:
	var holder := Node3D.new()
	holder.name = name_hint if name_hint != "" else model
	holder.position = pos
	holder.rotation.y = yaw
	parent.add_child(holder)
	_own(holder)

	var autumn := _rng.randf() < 0.11
	var leaf: Color = (
		LEAF_AUTUMN[_rng.randi() % LEAF_AUTUMN.size()] if autumn
		else LEAF_COLOURS[_rng.randi() % LEAF_COLOURS.size()]
	)
	leaf = leaf.lerp(Color(_rng.randf(), _rng.randf(), _rng.randf()), 0.05)
	var bark: Color = BARK_COLOURS[_rng.randi() % BARK_COLOURS.size()]

	var parts := _meshes_of(model)
	for i in parts.size():
		var mi := MeshInstance3D.new()
		mi.name = "Mesh" if parts.size() == 1 else "Mesh%d" % i
		mi.mesh = parts[i]["mesh"]
		var xf: Transform3D = parts[i]["xform"]
		xf.origin *= s
		mi.transform = xf.scaled_local(Vector3.ONE * s)
		holder.add_child(mi)
		_own(mi)
		for surf in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(surf) as StandardMaterial3D
			if src == null:
				continue
			var n := src.resource_name.to_lower()
			if n.contains("leaf") or n.contains("green") or n.contains("grass"):
				mi.set_surface_override_material(surf, _mat_for(src, leaf))
			elif n.contains("wood") or n.contains("bark") or n.contains("trunk"):
				mi.set_surface_override_material(surf, _mat_for(src, bark))
			else:
				mi.set_surface_override_material(surf, _mat_for(src, src.albedo_color))

	if collide == "none":
		return holder

	var box := _model_aabb(model)
	var body := StaticBody3D.new()
	body.name = "Body"
	holder.add_child(body)
	_own(body)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	body.add_child(col)
	_own(col)

	if collide == "trunk":
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(box.size.x, box.size.z) * s * 0.15
		cyl.height = box.size.y * s
		col.shape = cyl
		col.position.y = cyl.height * 0.5
	else:
		var b := BoxShape3D.new()
		b.size = box.size * s
		col.shape = b
		col.position = (box.position + box.size * 0.5) * s
	return holder


func _static_box(
	parent: Node, name: String, centre: Vector3, size: Vector3,
	mat: Material, visible_mesh: bool = true
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = centre
	parent.add_child(body)
	_own(body)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_own(col)
	if visible_mesh:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		if mat:
			mi.material_override = mat
		body.add_child(mi)
		_own(mi)
	return body


func _no_shadow(holder: Node) -> void:
	for c in holder.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _keepout(x: float, z: float, r: float) -> void:
	_keepouts.append([Vector2(x, z), r])


## Distance along the terrain's local Z, i.e. across the stream. World points
## must be rotated into terrain space before testing against the channel.
func _river_axis(x: float, z: float) -> float:
	return x * sin(RIVER_YAW) + z * cos(RIVER_YAW)


func _blocked(x: float, z: float, pad: float) -> bool:
	if absf(_river_axis(x, z) - RIVER_Z) < RIVER_HALF_W + 1.2:
		return true
	for k in _keepouts:
		if Vector2(x, z).distance_to(k[0]) < k[1] + pad:
			return true
	return false


# --- build steps -------------------------------------------------------------

func build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.58, 0.88)
	sky_mat.sky_horizon_color = Color(0.87, 0.92, 0.90)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.32, 0.40, 0.30)
	sky_mat.ground_horizon_color = Color(0.74, 0.79, 0.68)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Explicit warm ambient. Sky-derived ambient pulled a muted grey-green
	# through the whole palette.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.88, 0.91, 0.84)
	# Deep in the treeline almost nothing receives direct sun — measured: those
	# pixels don't move when the sun is disabled entirely. Ambient is the only
	# lever on them, so it carries most of the exposure here.
	env.ambient_light_energy = 2.1
	# Without this, ambient still comes entirely from the sky and both settings
	# above are silently ignored. It defaults to 1.0 (full sky).
	env.ambient_light_sky_contribution = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.88, 0.82)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.12

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_root.add_child(we)
	_own(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Low sun energy against high ambient. A strong key with dense foliage
	# buries everything behind the front rank in its own shadow; this flatter
	# ratio suits the stylised look and keeps shadowed leaves readable.
	sun.light_color = Color(1.0, 0.96, 0.87)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_normal_bias = 2.0
	# Must light the faces the default camera sees. For a light with euler
	# (x, y, 0): basis.z = (cos(x)*sin(y), -sin(x), cos(x)*cos(y)), and photons
	# travel along -basis.z. The camera looks down -Z, so camera-facing surfaces
	# have normal +Z and are only lit when basis.z.z > 0 — which needs
	# |rotation.y| < 90. At y=152 the whole treeline was backlit.
	sun.rotation_degrees = Vector3(-46.0, -35.0, 0.0)
	_root.add_child(sun)
	_own(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	# Near-neutral: a saturated blue fill tinted every shadow and every stone
	# surface blue.
	fill.light_color = Color(0.88, 0.92, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, -30.0, 0.0)
	_root.add_child(fill)
	_own(fill)


func build_ground() -> void:
	var grass := load("res://art/materials/toon_grass.tres") as Material
	var dirt := load("res://art/materials/toon_wood.tres") as Material
	var ground := Node3D.new()
	ground.name = "Ground"
	ground.rotation.y = RIVER_YAW
	_root.add_child(ground)
	_own(ground)
	_terrain = ground

	var n_near := RIVER_Z - RIVER_HALF_W
	_static_box(ground, "BankNorth", Vector3(0, -2.0, (-HALF + n_near) * 0.5),
		Vector3(HALF * 2.0, 4.0, n_near + HALF), grass)
	var s_near := RIVER_Z + RIVER_HALF_W
	_static_box(ground, "BankSouth", Vector3(0, -2.0, (s_near + HALF) * 0.5),
		Vector3(HALF * 2.0, 4.0, HALF - s_near), grass)
	_static_box(ground, "RiverBed", Vector3(0, -2.0 - RIVER_DEPTH, RIVER_Z),
		Vector3(HALF * 2.0, 4.0, RIVER_HALF_W * 2.0), dirt)

	# Flat colour patches break up the uniform lawn without needing textures.
	var patch_cols := [Color(0.38, 0.57, 0.31), Color(0.47, 0.66, 0.36),
		Color(0.52, 0.60, 0.33)]
	for i in 22:
		var x := _rng.randf_range(-PLAY, PLAY)
		var z := _rng.randf_range(-PLAY, PLAY)
		if absf(z - RIVER_Z) < RIVER_HALF_W + 1.0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Patch%d" % i
		var cyl := CylinderMesh.new()
		var r := _rng.randf_range(2.5, 6.5)
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = 0.06
		cyl.radial_segments = 9
		mi.mesh = cyl
		mi.position = Vector3(x, 0.03, z)
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.albedo_color = patch_cols[_rng.randi() % patch_cols.size()]
		m.roughness = 1.0
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mi.material_override = m
		ground.add_child(mi)
		_own(mi)


func build_bounds() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	_root.add_child(bounds)
	_own(bounds)
	var sides := [
		[Vector3(0, 8, -PLAY), Vector3(PLAY * 2.0, 18, 1)],
		[Vector3(0, 8, PLAY), Vector3(PLAY * 2.0, 18, 1)],
		[Vector3(-PLAY, 8, 0), Vector3(1, 18, PLAY * 2.0)],
		[Vector3(PLAY, 8, 0), Vector3(1, 18, PLAY * 2.0)],
	]
	for i in sides.size():
		var col := CollisionShape3D.new()
		col.name = "Wall%d" % i
		var shape := BoxShape3D.new()
		shape.size = sides[i][1]
		col.shape = shape
		col.position = sides[i][0]
		bounds.add_child(col)
		_own(col)


## Grassy rises so the floor isn't a billiard table. Shallow enough to walk up.
func build_mounds(world: Node) -> void:
	var g := Node3D.new()
	g.name = "Mounds"
	world.add_child(g)
	_own(g)
	var grass := load("res://art/materials/toon_grass.tres") as Material
	var spots := [
		[Vector3(-14.0, 0, -14.0), 7.0, 1.5],
		[Vector3(15.0, 0, -13.0), 6.0, 1.2],
		[Vector3(18.0, 0, 4.0), 5.5, 1.0],
		[Vector3(-19.0, 0, -2.0), 5.0, 0.9],
	]
	for i in spots.size():
		var p: Vector3 = spots[i][0]
		var r: float = spots[i][1]
		var h: float = spots[i][2]
		var body := StaticBody3D.new()
		body.name = "Mound%d" % i
		body.position = p
		g.add_child(body)
		_own(body)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var cone := CylinderMesh.new()
		cone.top_radius = r * 0.55
		cone.bottom_radius = r
		cone.height = h * 2.0
		cone.radial_segments = 10
		mi.mesh = cone
		mi.position.y = 0.0
		mi.material_override = grass
		body.add_child(mi)
		_own(mi)
		var col := CollisionShape3D.new()
		col.name = "Shape"
		var cyl := CylinderShape3D.new()
		cyl.radius = r * 0.8
		cyl.height = h * 2.0
		col.shape = cyl
		body.add_child(col)
		_own(col)
		_keepout(p.x, p.z, r * 0.5)


func build_deku_tree(world: Node) -> void:
	var g := Node3D.new()
	g.name = "GreatDekuTree"
	world.add_child(g)
	_own(g)

	# The landmark has to win the skyline outright. Perimeter canopy tops out
	# around 10 m; at scale 26 this is ~35 m and sits on a raised knoll, so it
	# reads as the thing the whole clearing is arranged around.
	var knoll := StaticBody3D.new()
	knoll.name = "DekuKnoll"
	knoll.position = Vector3(0, 0, -21.0)
	g.add_child(knoll)
	_own(knoll)
	var kmesh := MeshInstance3D.new()
	kmesh.name = "Mesh"
	var kcone := CylinderMesh.new()
	kcone.top_radius = 6.0
	kcone.bottom_radius = 10.5
	kcone.height = 3.0
	kcone.radial_segments = 12
	kmesh.mesh = kcone
	kmesh.material_override = load("res://art/materials/toon_grass.tres") as Material
	knoll.add_child(kmesh)
	_own(kmesh)
	var kcol := CollisionShape3D.new()
	kcol.name = "Shape"
	var kshape := CylinderShape3D.new()
	kshape.radius = 8.0
	kshape.height = 3.0
	kcol.shape = kshape
	knoll.add_child(kcol)
	_own(kcol)

	_prop(g, "tree_detailed", Vector3(0, 1.4, -21.0), 0.2, 26.0, "trunk", "DekuTree")
	_keepout(0, -21, 11.0)
	# Attendants pushed well back and scaled down so nothing competes with it.
	_prop(g, "tree_default", Vector3(-16.0, 0, -24.0), 1.1, 5.5, "trunk")
	_prop(g, "tree_fat", Vector3(15.5, 0, -23.5), 2.4, 5.0, "trunk")
	_keepout(-16.0, -24.0, 3.0)
	_keepout(15.5, -23.5, 3.0)

	# Shrine sits on the knoll top (y = +1.5), flanking the approach.
	_prop(g, "statue_head", Vector3(-3.6, 1.5, -17.0), 0.5, 3.0, "box")
	_prop(g, "statue_head", Vector3(3.6, 1.5, -17.0), -0.5, 3.0, "box")
	_prop(g, "statue_obelisk", Vector3(0, 1.5, -19.0), 0.0, 3.6, "box")
	_keepout(0, -17, 5.5)

	# Approach path: from the north bank of the stream up to the knoll foot.
	for i in 6:
		var t := float(i) / 5.0
		var z: float = lerpf(-5.5, -10.2, t)
		var x := sin(t * 2.6) * 0.7
		_prop(g, "path_stoneCircle", Vector3(x, 0.05, z), _rng.randf() * TAU, 2.4)
		_keepout(x, z, 1.9)


func build_village(world: Node) -> void:
	var g := Node3D.new()
	g.name = "Village"
	world.add_child(g)
	_own(g)

	# clearing houses are hollow stumps in the source material, so oversized
	# stump models read right.
	# Scaled up hard: at scale 8 a stump is 2.9 m wide but only 1.7 m tall,
	# which is shorter than the player. These need to read as buildings.
	var houses := [
		[Vector3(-11.5, 0, 6.5), 0.6, 15.0, "stump_squareDetailed"],
		[Vector3(-7.5, 0, 16.5), -0.4, 13.0, "stump_round"],
		[Vector3(11.0, 0, 8.5), 2.6, 14.0, "stump_old"],
		[Vector3(15.5, 0, 17.0), 3.4, 12.0, "stump_round"],
	]
	for h in houses:
		var pos: Vector3 = h[0]
		var s: float = h[2]
		_house(g, h[3], pos, h[1], s)
		_keepout(pos.x, pos.z, s * 0.24 + 2.5)

	_prop(g, "campfire_logs", Vector3(0, 0, 10.0), 0.0, 3.2, "none", "Campfire")
	_prop(g, "campfire_stones", Vector3(0, 0, 10.0), 0.4, 3.2, "none")
	_keepout(0, 10, 2.8)
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		_prop(g, "log", Vector3(cos(a) * 3.0, 0, 10.0 + sin(a) * 3.0), a, 2.4, "box")

	for i in 5:
		_prop(g, "fence_simple", Vector3(-15.0 + float(i) * 1.9, 0, 11.5), 0.0, 1.9, "box")
	_keepout(-13, 11.5, 2.0)


## An oversized stump plus a doorway and lit windows facing the village green.
## Without these it reads as a tree stump, not somewhere anyone lives.
func _house(parent: Node, model: String, pos: Vector3, yaw: float, _s: float) -> void:
	# Stumps are roughly 2:1 wide-to-tall discs, so scaling uniformly to reach
	# a usable height makes a 7 m wall. Scale each axis to a target size
	# instead, and derive the doorway offset from that target — deriving it
	# from a uniform scale is what left the door floating beside the house.
	const WIDTH := 4.6
	const HEIGHT := 3.4
	var box := _model_aabb(model)
	var scale := Vector3(WIDTH / box.size.x, HEIGHT / box.size.y, WIDTH / box.size.z)

	# Face the village green. This is not cosmetic: these stumps are square, so
	# a door placed along the diagonal direction to the green lands beyond the
	# corner and floats. Turning a flat face toward the green makes the door
	# offset perpendicular to a wall.
	var to_centre := Vector3(0.0, 0.0, 10.0) - pos
	to_centre.y = 0.0
	var dir := to_centre.normalized() if to_centre.length() > 0.01 else Vector3.BACK
	var facing := atan2(dir.x, dir.z)
	var tangent := Vector3(dir.z, 0.0, -dir.x)

	var holder := Node3D.new()
	holder.name = "House"
	holder.position = pos
	holder.rotation.y = facing + yaw * 0.12  # tiny jitter so they aren't uniform
	parent.add_child(holder)
	_own(holder)

	for part in _meshes_of(model):
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = part["mesh"]
		var xf: Transform3D = part["xform"]
		xf.origin *= scale
		mi.transform = xf.scaled_local(scale)
		holder.add_child(mi)
		_own(mi)
		for surf in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(surf) as StandardMaterial3D
			if src != null:
				mi.set_surface_override_material(surf, _mat_for(src, src.albedo_color))

	var body := StaticBody3D.new()
	body.name = "Body"
	holder.add_child(body)
	_own(body)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(WIDTH, HEIGHT, WIDTH)
	col.shape = cbox
	col.position.y = HEIGHT * 0.5
	body.add_child(col)
	_own(col)

	var radius := WIDTH * 0.5
	var height := HEIGHT

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.07, 0.05)
	dark.roughness = 1.0
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.83, 0.45)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.75, 0.35)
	glow.emission_energy_multiplier = 1.6

	var door := MeshInstance3D.new()
	door.name = "Doorway"
	var dm := BoxMesh.new()
	dm.size = Vector3(1.5, 2.2, 0.6)
	door.mesh = dm
	door.position = pos + dir * (radius - 0.25) + Vector3(0, 1.1, 0)
	door.rotation.y = facing
	door.material_override = dark
	parent.add_child(door)
	_own(door)

	var lintel := MeshInstance3D.new()
	lintel.name = "Lintel"
	var lm := BoxMesh.new()
	lm.size = Vector3(2.1, 0.35, 1.0)
	lintel.mesh = lm
	lintel.position = pos + dir * (radius - 0.1) + Vector3(0, 2.35, 0)
	lintel.rotation.y = facing
	lintel.material_override = _mat_for(
		load("res://art/materials/toon_wood.tres") as StandardMaterial3D,
		Color(0.42, 0.30, 0.20)
	)
	parent.add_child(lintel)
	_own(lintel)

	# Two lit windows either side, set a little above the door.
	for side in [-1.0, 1.0]:
		var win := MeshInstance3D.new()
		win.name = "Window"
		var wm2 := BoxMesh.new()
		wm2.size = Vector3(0.85, 0.85, 0.5)
		win.mesh = wm2
		var offset: Vector3 = dir * (radius - 0.3) + tangent * (float(side) * radius * 0.52)
		win.position = pos + offset + Vector3(0, minf(height * 0.62, 3.1), 0)
		win.rotation.y = facing
		win.material_override = glow
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(win)
		_own(win)

	var step := MeshInstance3D.new()
	step.name = "Doorstep"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.3
	cyl.bottom_radius = 1.3
	cyl.height = 0.08
	cyl.radial_segments = 10
	step.mesh = cyl
	step.position = pos + dir * (radius + 0.6) + Vector3(0, 0.05, 0)
	step.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	step.material_override = _mat_for(
		load("res://art/materials/toon_wood.tres") as StandardMaterial3D,
		Color(0.44, 0.36, 0.27)
	)
	parent.add_child(step)
	_own(step)


func build_river(_world: Node) -> void:
	# Parented to the yawed terrain, so everything here is in terrain-local
	# space and the stream inherits the diagonal.
	var g := Node3D.new()
	g.name = "River"
	_terrain.add_child(g)
	_own(g)

	var water := MeshInstance3D.new()
	water.name = "WaterSurface"
	var plane := BoxMesh.new()
	plane.size = Vector3(HALF * 2.0, 0.12, RIVER_HALF_W * 2.0)
	water.mesh = plane
	water.position = Vector3(0, -RIVER_DEPTH + 0.30, RIVER_Z)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wm := StandardMaterial3D.new()
	# Was washing out to near-white against the tan riverbed at low alpha.
	wm.albedo_color = Color(0.24, 0.50, 0.62, 0.88)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
	wm.metallic_specular = 0.6
	water.material_override = wm
	g.add_child(water)
	_own(water)

	_prop(g, "bridge_wood", Vector3(0, 0, RIVER_Z), 0.0, 6.0, "none", "Bridge")
	_static_box(g, "BridgeDeck", Vector3(0, 0.05, RIVER_Z),
		Vector3(4.4, 0.2, RIVER_HALF_W * 2.4), null, false)

	# Reeds and bank vegetation, denser near the bridge, so the stream edge
	# isn't a bare cut line through the grass.
	for i in 40:
		var x := _rng.randf_range(-PLAY - 6.0, PLAY + 6.0)
		if absf(x) < 3.0:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var z := RIVER_Z + side * (RIVER_HALF_W + _rng.randf_range(0.0, 1.4))
		_prop(g, ["grass_leafs", "grass_large", "plant_bushSmall"][_rng.randi() % 3],
			Vector3(x, -0.1, z), _rng.randf() * TAU, _rng.randf_range(2.6, 4.4))

	for i in 22:
		var x := _rng.randf_range(-PLAY + 1.0, PLAY - 1.0)
		if absf(x) < 3.2:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var z := RIVER_Z + side * (RIVER_HALF_W + _rng.randf_range(0.1, 1.0))
		var model: String = ["rock_smallA", "rock_smallB", "stone_smallA"][_rng.randi() % 3]
		_prop(g, model, Vector3(x, 0, z), _rng.randf() * TAU, _rng.randf_range(2.2, 3.8))


func build_lookout(world: Node) -> void:
	var g := Node3D.new()
	g.name = "Lookout"
	world.add_child(g)
	_own(g)
	# Collision stays as clean boxes (reliable to walk and jump on) but they are
	# invisible; actual rock models are stacked over them so it doesn't read as
	# placeholder geometry.
	var grass := load("res://art/materials/toon_grass.tres") as Material
	var base := Vector3(-17.0, 0, 13.0)
	# offset, top height, footprint
	var terraces := [
		[Vector3(0, 0, 0), 1.3, 5.2],
		[Vector3(3.6, 0, -0.8), 2.6, 4.6],
		[Vector3(6.9, 0, -1.4), 3.9, 4.2],
	]
	for i in terraces.size():
		var off: Vector3 = terraces[i][0]
		var h: float = terraces[i][1]
		var fp: float = terraces[i][2]
		var c: Vector3 = base + off

		_static_box(g, "LedgeCol%d" % i, Vector3(c.x, h - 2.0, c.z),
			Vector3(fp, 4.0, fp), null, false)
		_keepout(c.x, c.z, fp * 0.6)

		# cliff_block_rock spans y from -0.05s to +0.95s, so to land its top on
		# the terrace height, drop it by 0.95 * scale.
		var s := 2.4
		for gx in 2:
			for gz in 2:
				var p := Vector3(
					c.x + (float(gx) - 0.5) * fp * 0.5,
					h - 0.95 * s,
					c.z + (float(gz) - 0.5) * fp * 0.5
				)
				_prop(g, "cliff_block_rock", p, _rng.randf() * TAU, s)

		var cap := MeshInstance3D.new()
		cap.name = "LedgeTop%d" % i
		var cm := BoxMesh.new()
		cm.size = Vector3(fp, 0.25, fp)
		cap.mesh = cm
		cap.position = Vector3(c.x, h - 0.12, c.z)
		cap.material_override = grass
		g.add_child(cap)
		_own(cap)

	# Loose boulders skirting the base so it grows out of the ground.
	for i in 9:
		var a := TAU * float(i) / 9.0
		_prop(g, ["rock_largeA", "rock_largeB", "stone_tallA"][_rng.randi() % 3],
			base + Vector3(cos(a) * 5.8, -0.2, sin(a) * 5.0), a,
			_rng.randf_range(2.6, 4.0), "box")

	var top := base + Vector3(6.9, 3.9, -1.4)
	_prop(g, "tree_small", top + Vector3(-1.2, 0, -1.0), 0.8, 3.4, "trunk")


func build_gate(world: Node) -> void:
	var g := Node3D.new()
	g.name = "ForestGate"
	world.add_child(g)
	_own(g)
	var gz := 20.5

	# Locked until the player finds the key. This is the level's goal.
	var gate := Area3D.new()
	gate.set_script(load("res://items/gate.gd"))
	gate.name = "ForestGateDoor"
	gate.position = Vector3(6.0, 0, gz)
	g.add_child(gate)
	_own(gate)
	gate.set("locked", true)
	_prop(gate, "fence_gate", Vector3.ZERO, 0.0, 3.6, "none", "Mesh")

	var blocker := StaticBody3D.new()
	blocker.name = "Blocker"
	gate.add_child(blocker)
	_own(blocker)
	var bshape := CollisionShape3D.new()
	bshape.name = "Shape"
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(3.6, 3.0, 0.6)
	bshape.shape = bbox
	bshape.position.y = 1.5
	blocker.add_child(bshape)
	_own(bshape)

	for i in 4:
		_prop(g, "fence_planks", Vector3(-0.5 + float(i) * 3.5, 0, gz), 0.0, 3.5, "box")
	for i in 3:
		_prop(g, "fence_planks", Vector3(9.5 + float(i) * 3.5, 0, gz), 0.0, 3.5, "box")
	_prop(g, "tree_tall", Vector3(-2.5, 0, 22.0), 0.4, 7.0, "trunk")
	_prop(g, "tree_tall", Vector3(14.0, 0, 22.5), 2.1, 7.5, "trunk")
	_keepout(6, gz, 5.0)
	for i in 4:
		var t := float(i) / 3.0
		_prop(g, "path_stone", Vector3(lerpf(1.0, 5.0, t), 0.05, lerpf(14.0, 18.5, t)),
			_rng.randf() * TAU, 2.6)


## Dense multi-layer treeline. This is what makes the clearing a room rather
## than an island: the player must never see past it or under it.
func build_perimeter(world: Node) -> void:
	var g := Node3D.new()
	g.name = "Perimeter"
	world.add_child(g)
	_own(g)

	for ring in 5:
		var radius := PLAY - 0.5 + float(ring) * 3.0
		var count := 34 + ring * 8
		for i in count:
			var a := TAU * float(i) / float(count) + float(ring) * 0.31
			var jitter := _rng.randf_range(-1.3, 1.3)
			var x := cos(a) * (radius + jitter)
			var z := sin(a) * (radius + jitter)
			# Leave the river mouth clear so the water reads as flowing out.
			if absf(z - RIVER_Z) < RIVER_HALF_W - 0.5 and ring < 2:
				continue
			# Outer rings sit progressively higher so the canopy stacks up
			# behind itself instead of forming one flat wall.
			var lift := float(ring) * 0.9
			var s := _rng.randf_range(4.0, 7.5) + float(ring) * 0.7
			var holder := _prop(g, CANOPY[_rng.randi() % CANOPY.size()],
				Vector3(x, -0.3 + lift, z), _rng.randf() * TAU, s,
				"trunk" if ring == 0 else "none")
			# Outer rings are pure backdrop. Letting them cast shadows buried
			# the whole treeline in its own shade, and it costs fill rate.
			if ring >= 2:
				_no_shadow(holder)

	# Undergrowth at the base of the treeline hides the gap under the canopy.
	for i in 120:
		var a := _rng.randf() * TAU
		var r := PLAY + _rng.randf_range(-1.5, 2.5)
		var model: String = ["plant_bushLarge", "plant_bushDetailed", "plant_bush",
			"grass_large", "tree_small"][_rng.randi() % 5]
		_prop(g, model, Vector3(cos(a) * r, -0.2, sin(a) * r), _rng.randf() * TAU,
			_rng.randf_range(3.5, 6.0))

	for i in 22:
		var a := TAU * float(i) / 22.0 + 0.1
		var r := PLAY + 1.2
		_prop(g, "cliff_block_rock", Vector3(cos(a) * r, -1.0, sin(a) * r),
			a + PI * 0.5, _rng.randf_range(3.0, 4.5))


## Clustered vegetation. Uniform scatter reads as litter; nature clumps.
func build_scatter(world: Node) -> void:
	var g := Node3D.new()
	g.name = "Scatter"
	world.add_child(g)
	_own(g)

	var tufts := ["grass", "grass_large", "grass_leafs", "plant_bush",
		"plant_bushSmall", "plant_bushLarge", "plant_bushDetailed"]
	var blooms := ["flower_redA", "flower_yellowA", "flower_purpleA"]
	var fungi := ["mushroom_red", "mushroom_redGroup", "mushroom_redTall"]
	var pebbles := ["rock_smallA", "rock_smallB", "stone_smallA", "stump_round"]

	_clusters(g, tufts, 26, 6, 10, 3.2, 3.5, 5.5, 0.9)
	_clusters(g, blooms, 14, 4, 8, 2.2, 3.0, 4.2, 0.9)
	_clusters(g, fungi, 9, 3, 6, 1.6, 3.0, 4.6, 1.0)
	_clusters(g, pebbles, 8, 2, 4, 2.4, 2.6, 4.0, 1.2)

	# Mid-size trees inside the bowl, in small groves.
	var inner := ["tree_small", "tree_thin", "tree_oak", "tree_pineRoundC",
		"tree_default"]
	for grove in 7:
		var cx := _rng.randf_range(-PLAY + 6.0, PLAY - 6.0)
		var cz := _rng.randf_range(-PLAY + 6.0, PLAY - 6.0)
		if _blocked(cx, cz, 6.0):
			continue
		for i in _rng.randi_range(2, 4):
			var x := cx + _rng.randf_range(-3.5, 3.5)
			var z := cz + _rng.randf_range(-3.5, 3.5)
			if _blocked(x, z, 3.0):
				continue
			_prop(g, inner[_rng.randi() % inner.size()], Vector3(x, 0, z),
				_rng.randf() * TAU, _rng.randf_range(3.5, 6.0), "trunk")
			_keepout(x, z, 2.2)


func _clusters(
	parent: Node, models: Array, groups: int, per_min: int, per_max: int,
	spread: float, s_min: float, s_max: float, pad: float
) -> void:
	for c in groups:
		var cx := _rng.randf_range(-PLAY + 2.5, PLAY - 2.5)
		var cz := _rng.randf_range(-PLAY + 2.5, PLAY - 2.5)
		if _blocked(cx, cz, pad + 1.0):
			continue
		for i in _rng.randi_range(per_min, per_max):
			var x := cx + _rng.randf_range(-spread, spread)
			var z := cz + _rng.randf_range(-spread, spread)
			if _blocked(x, z, pad):
				continue
			_prop(parent, models[_rng.randi() % models.size()], Vector3(x, 0, z),
				_rng.randf() * TAU, _rng.randf_range(s_min, s_max))


func _rupee(parent: Node, pos: Vector3, value: int, colour: String) -> void:
	var node := Area3D.new()
	node.set_script(load("res://items/rupee.gd"))
	node.name = "Rupee"
	node.position = pos
	parent.add_child(node)
	_own(node)
	node.set("value", value)
	node.set("colour", colour)


func _chest(
	parent: Node, pos: Vector3, yaw: float, key: bool, rupees: int, id: String
) -> void:
	var node := Area3D.new()
	node.set_script(load("res://items/chest.gd"))
	node.name = "Chest_" + id
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)
	_own(node)
	node.set("contains_key", key)
	node.set("rupees", rupees)
	node.set("chest_id", id)


func _sign_post(
	parent: Node, pos: Vector3, yaw: float, text: String, id: String
) -> void:
	var node := Area3D.new()
	node.set_script(load("res://items/sign_post.gd"))
	node.name = "Sign_" + id
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)
	_own(node)
	node.set("text", text)
	_prop(node, "sign", Vector3.ZERO, 0.0, 3.0, "none", "Mesh")


## Chests, pickups and readable signs. This is what turns the clearing from a
## place you walk around into a level you play.
func build_gameplay(world: Node) -> void:
	var g := Node3D.new()
	g.name = "Gameplay"
	world.add_child(g)
	_own(g)

	# The key is the reward for climbing the lookout — the one bit of
	# verticality in the level should pay out.
	_chest(g, Vector3(-10.4, 3.9, 11.2), -0.9, true, 0, "lookout_key")
	# A second chest tucked behind the shrine, for players who explore north.
	_chest(g, Vector3(4.8, 1.5, -19.5), 2.3, false, 20, "shrine_rupees")

	_sign_post(g, Vector3(2.6, 0, 13.5), -0.35,
		"clearing Village\nThe Great Deku Tree sleeps beyond the stream.", "village")
	_sign_post(g, Vector3(2.2, 0, 17.6), 0.25,
		"The forest gate is locked.\nSomeone left a key up on the rocks.", "gate")
	_sign_post(g, Vector3(-9.0, 3.9, 12.6), 2.2,
		"The whole forest from up here.\nSomething glints in that chest.", "lookout")
	_sign_post(g, Vector3(-1.6, 0, -6.6), 0.1,
		"Tread softly.\nThe Deku Tree is old and dreaming.", "deku")

	# Teaching rupees: a couple right where you spawn.
	_rupee(g, Vector3(-1.8, 0, 13.0), 1, "green")
	_rupee(g, Vector3(1.9, 0, 12.2), 1, "green")

	# A trail up the lookout terraces so the climb is signposted.
	var lookout := Vector3(-17.0, 0, 13.0)
	_rupee(g, lookout + Vector3(-2.0, 1.4, 2.4), 1, "green")
	_rupee(g, lookout + Vector3(1.2, 1.4, 0.4), 1, "green")
	_rupee(g, lookout + Vector3(4.0, 2.7, -0.6), 5, "blue")
	_rupee(g, lookout + Vector3(6.6, 4.0, -2.6), 5, "blue")

	# Across the bridge, drawing you toward the Deku Tree.
	_rupee(g, Vector3(-2.4, 0, -5.4), 1, "green")
	_rupee(g, Vector3(-0.4, 0, -8.6), 1, "green")
	_rupee(g, Vector3(0.9, 0, -11.2), 5, "blue")
	_rupee(g, Vector3(-4.6, 1.5, -17.5), 20, "red")

	# A ring around the campfire.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.6
		_rupee(g, Vector3(cos(a) * 5.2, 0, 10.0 + sin(a) * 5.2), 1, "green")


func build_actors() -> void:
	var player := (load("res://actors/player/player.tscn") as PackedScene).instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0.3, 16.0)
	_root.add_child(player)
	_own(player)

	var hud := (load("res://ui/hud.tscn") as PackedScene).instantiate()
	hud.name = "HUD"
	_root.add_child(hud)
	_own(hud)

	var debug := (load("res://ui/debug_overlay.tscn") as PackedScene).instantiate()
	debug.name = "DebugOverlay"
	_root.add_child(debug)
	_own(debug)
