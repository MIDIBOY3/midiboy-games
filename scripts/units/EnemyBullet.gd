class_name EnemyBullet
extends Node3D

var velocity: Vector3 = Vector3.ZERO
var alt: float = 0.5   # 0.0 (low/ground) … 1.0 (high/space), same as Enemy
var bullet_type: String = "shot"

var _mat: StandardMaterial3D
static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
var _mesh_node: MeshInstance3D

func _ready() -> void:
	add_to_group("enemy_bullets")
	_mesh_node = MeshInstance3D.new()
	var size := Vector3(0.045, 0.045, 0.045)
	match bullet_type:
		"ring":
			size = Vector3(0.052, 0.052, 0.030)
		"fan":
			size = Vector3(0.040, 0.060, 0.032)
		"lane":
			size = Vector3(0.036, 0.074, 0.030)
		"burst":
			size = Vector3(0.060, 0.038, 0.032)
		"divine":
			size = Vector3(0.070, 0.070, 0.044)
		"halo":
			size = Vector3(0.082, 0.082, 0.034)
		"lance":
			size = Vector3(0.034, 0.130, 0.036)
	var mesh_key := "%d:%d:%d" % [int(size.x * 1000.0), int(size.y * 1000.0), int(size.z * 1000.0)]
	var box: BoxMesh = _mesh_cache.get(mesh_key)
	if box == null:
		box = BoxMesh.new()
		box.size = size
		_mesh_cache[mesh_key] = box
	_mesh_node.mesh = box
	var mat_key := bullet_type
	_mat = _mat_cache.get(mat_key)
	if _mat == null:
		_mat = StandardMaterial3D.new()
		match bullet_type:
			"ring":
				_mat.albedo_color = Color(1.0, 0.42, 0.10)
				_mat.emission = Color(1.0, 0.24, 0.04)
			"fan":
				_mat.albedo_color = Color(1.0, 0.14, 0.08)
				_mat.emission = Color(1.0, 0.08, 0.03)
			"lane":
				_mat.albedo_color = Color(0.4, 0.9, 1.0)
				_mat.emission = Color(0.15, 0.65, 1.0)
			"burst":
				_mat.albedo_color = Color(1.0, 0.85, 0.18)
				_mat.emission = Color(1.0, 0.55, 0.05)
			"divine":
				_mat.albedo_color = Color(1.0, 0.82, 0.24)
				_mat.emission = Color(1.0, 0.54, 0.06)
			"halo":
				_mat.albedo_color = Color(1.0, 0.96, 0.68)
				_mat.emission = Color(1.0, 0.82, 0.22)
			"lance":
				_mat.albedo_color = Color(0.60, 0.93, 1.0)
				_mat.emission = Color(0.18, 0.72, 1.0)
			_:
				_mat.albedo_color = Color(1.0, 0.18, 0.04)
				_mat.emission = Color(1.0, 0.05, 0.02)
		_mat.emission_enabled = true
		_mat.emission_energy_multiplier = 2.4 if bullet_type == "halo" else 1.65
		_mat_cache[mat_key] = _mat
	_mesh_node.material_override = _mat
	add_child(_mesh_node)

func _process(_delta: float) -> void:
	position += velocity
	if _mesh_node != null:
		_mesh_node.rotation_degrees.z += 12.0 if bullet_type == "halo" else (8.0 if bullet_type == "ring" else 3.0)
	# Cull off-screen relative to the CAMERA (world scrolls in the ZAKO design; an absolute
	# ±6 test would instantly free anything spawned far up the world, e.g. the ZAKO front).
	var rel_y := position.y - GameState.cam_y
	if rel_y > 6.0 or rel_y < -6.0 or absf(position.x) > 8.0:
		queue_free()

func is_in_player_range() -> bool:
	return absf(GameState.alt - alt * GameState.ALT_MAX) < 12.0
