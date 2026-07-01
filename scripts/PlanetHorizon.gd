class_name PlanetHorizon
extends Node3D

# A lightweight spherical-surface view for planet flight.
# It draws a huge curved cap like the camera is close to a ball, then streams
# faux-3D surface objects along that cap from the horizon toward the player.

const MAX_SURFACE_OBJECTS := 18
const SPAWN_FRAMES := 18
const CAP_Z := -7.2
const OBJ_Z := -2.95

static var _box_mesh: BoxMesh
static var _cap_mesh: ArrayMesh
static var _cap_mat: StandardMaterial3D
static var _rim_mat: StandardMaterial3D
static var _shadow_mat: StandardMaterial3D
static var _mats: Array[StandardMaterial3D] = []

var _cap: MeshInstance3D
var _rim: MeshInstance3D
var _objects_root: Node3D
var _timer: int = 1
var _seeded_biome: String = ""
var _planet_spin: float = 0.0

func _ready() -> void:
	add_to_group("planet_horizon")
	top_level = true
	_make_shared()
	_cap = MeshInstance3D.new()
	_cap.mesh = _cap_mesh
	_cap.material_override = _cap_mat
	add_child(_cap)
	_rim = MeshInstance3D.new()
	_rim.mesh = _cap_mesh
	_rim.material_override = _rim_mat
	_rim.scale = Vector3(1.012, 1.012, 1.0)
	_rim.position.z = -0.03
	add_child(_rim)
	_objects_root = Node3D.new()
	add_child(_objects_root)
	_set_visible_planet(false)

func _make_shared() -> void:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE
	if _cap_mesh == null:
		_cap_mesh = _build_cap_mesh()
	if _cap_mat != null:
		return
	_cap_mat = _mat(Color(1.0, 0.94, 0.28), true)
	_rim_mat = _mat(Color(0.60, 0.45, 0.16), true)
	_shadow_mat = _mat(Color(0.08, 0.08, 0.09), true)
	_shadow_mat.albedo_color.a = 0.42
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats = [
		_mat(Color(0.66, 0.67, 0.64)),
		_mat(Color(0.42, 0.45, 0.48)),
		_mat(Color(0.76, 0.70, 0.54)),
		_mat(Color(0.30, 0.54, 0.36)),
		_mat(Color(0.58, 0.42, 0.68)),
	]

func _mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _build_cap_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var samples := 56
	var rx := 7.5
	var ry := 4.15
	var cy := -4.72
	var bottom := -7.6
	verts.append(Vector3(-rx, bottom, 0.0))
	cols.append(Color.WHITE)
	for i in samples + 1:
		var t := -1.0 + 2.0 * float(i) / float(samples)
		var x := t * rx
		var y := cy + sqrt(maxf(0.0, 1.0 - t * t)) * ry
		verts.append(Vector3(x, y, 0.0))
		cols.append(Color.WHITE)
	verts.append(Vector3(rx, bottom, 0.0))
	cols.append(Color.WHITE)
	for i in range(1, samples + 2):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _process(delta: float) -> void:
	var on := GameState.stage == "planet" and not GameState.underground
	_set_visible_planet(on)
	if not on:
		_clear_objects()
		return
	var active_biome := GameState.planet_biome
	if _seeded_biome != active_biome:
		_seeded_biome = active_biome
		_recolor_for_biome()
		_clear_objects()
	var camera := get_viewport().get_camera_3d()
	var cx := camera.global_position.x if camera != null else 0.0
	global_position = Vector3(cx, 0.0, 0.0)
	var surf_t := 1.0
	scale = Vector3.ONE * surf_t
	_cap_mat.albedo_color.a = 0.98
	_rim_mat.albedo_color.a = 1.0
	_cap_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_planet_spin += (0.18 + absf(GameState.vx) * 0.04) * delta
	_timer -= 1
	if _timer <= 0:
		_timer = SPAWN_FRAMES + randi() % 16
		if _objects_root.get_child_count() < MAX_SURFACE_OBJECTS:
			_spawn_surface_object()
	_update_surface_objects(delta)

func _target_planet() -> TargetPlanet:
	var raw := get_tree().get_first_node_in_group("target_planet")
	return raw as TargetPlanet

func _set_visible_planet(on: bool) -> void:
	visible = on

func _recolor_for_biome() -> void:
	var b: Dictionary = PlanetTerrain.BIOMES.get(_seeded_biome, PlanetTerrain.BIOMES["VERDANT"])
	var high: Color = b["high"]
	var base := high.lerp(Color(1.0, 0.92, 0.24), 0.42).lightened(0.15)
	_cap_mat.albedo_color = Color(base.r, base.g, base.b, 0.98)
	var rim := base.darkened(0.42)
	_rim_mat.albedo_color = Color(rim.r, rim.g, rim.b, 1.0)

func _spawn_surface_object() -> void:
	var root := Node3D.new()
	var lane := randf_range(-1.05, 1.05)
	root.set_meta("lane", lane)
	root.set_meta("depth", 0.02)
	root.set_meta("spin_phase", randf() * TAU)
	root.set_meta("kind", randi() % 5)
	_objects_root.add_child(root)
	_build_object(root, int(root.get_meta("kind")))
	_place_object(root)

func _build_object(root: Node3D, kind: int) -> void:
	var mat := _mats[kind % _mats.size()]
	match kind:
		0:
			_block(root, Vector3.ZERO, Vector3(0.34, 0.34, 0.36), mat, randf_range(-12.0, 12.0))
			_block(root, Vector3(0.05, -0.06, -0.11), Vector3(0.34, 0.34, 0.12), _shadow_mat, 0.0)
		1:
			for i in 3:
				_block(root, Vector3((float(i) - 1.0) * 0.22, 0.0, 0.12 + float(i) * 0.03),
					Vector3(0.16, 0.16, 0.24 + float(i) * 0.09), mat)
			_block(root, Vector3(0.05, -0.08, -0.08), Vector3(0.70, 0.24, 0.10), _shadow_mat)
		2:
			for i in 5:
				var a := TAU * float(i) / 5.0
				_block(root, Vector3(cos(a) * 0.22, sin(a) * 0.10, 0.08),
					Vector3(0.12, 0.10, 0.20), mat, rad_to_deg(a))
		3:
			for i in 4:
				_block(root, Vector3((float(i) - 1.5) * 0.18, sin(float(i)) * 0.07, 0.08),
					Vector3(0.17, 0.17, randf_range(0.16, 0.34)), mat, randf_range(-8.0, 8.0))
		_:
			_block(root, Vector3(0.0, 0.0, 0.14), Vector3(0.48, 0.12, 0.12), mat, randf_range(-20.0, 20.0))
			_block(root, Vector3(-0.18, 0.12, 0.26), Vector3(0.12, 0.32, 0.10), mat, randf_range(16.0, 32.0))
			_block(root, Vector3(0.18, -0.10, 0.26), Vector3(0.12, 0.28, 0.10), mat, randf_range(-32.0, -16.0))

func _block(parent: Node3D, pos: Vector3, size: Vector3, mat: Material,
		rz: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh
	m.position = pos
	m.scale = size
	m.rotation_degrees.z = rz
	m.material_override = mat
	parent.add_child(m)
	return m

func _update_surface_objects(delta: float) -> void:
	for c in _objects_root.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var d := float(n.get_meta("depth", 0.0))
		d += delta * lerpf(0.10, 0.22, clampf(GameState.sky_t(), 0.0, 1.0))
		n.set_meta("depth", d)
		_place_object(n)
		if d > 1.18:
			n.queue_free()

func _place_object(root: Node3D) -> void:
	var d := float(root.get_meta("depth", 0.0))
	var lane := float(root.get_meta("lane", 0.0))
	var side_shift := -GameState.px * lerpf(0.05, 0.36, d)
	var curve := sin((_planet_spin + lane * 0.7) * 0.55) * 0.25
	var x := lane * lerpf(3.0, 5.9, d) + side_shift + curve
	var y := _surface_y(x) - lerpf(0.05, 4.55, d)
	var z := lerpf(-5.6, OBJ_Z, d)
	var sc := lerpf(0.16, 1.55, pow(d, 1.55))
	root.position = Vector3(x, y, z)
	root.scale = Vector3.ONE * sc
	root.rotation_degrees.z = lane * lerpf(-8.0, -18.0, d)
	root.rotation_degrees.x = lerpf(-20.0, 10.0, d)

func _surface_y(x: float) -> float:
	var rx := 7.5
	var ry := 4.15
	var cy := -4.72
	var t := clampf(x / rx, -0.98, 0.98)
	return cy + sqrt(maxf(0.0, 1.0 - t * t)) * ry

func _clear_objects() -> void:
	if _objects_root == null:
		return
	for c in _objects_root.get_children():
		c.queue_free()
