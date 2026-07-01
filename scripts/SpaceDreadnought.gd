class_name SpaceDreadnought
extends Node3D

var enemy_type: String = "space_dreadnought"
var hp: int = 90
var max_hp: int = 90
var hue: float = 210.0
var alt: float = 0.98

var _t := 0
var _hit_flash := 0
var _shot_t := 0
var _volleys := 0
var _dive_t := 0
var _diving := false
var _dive_start := Vector3.ZERO
var _dive_target_x := 0.0
var _mat: StandardMaterial3D
var _core_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("enemies")
	_build()

func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.06, 0.08, 0.13)
	_mat.roughness = 0.85
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.25, 0.8, 1.0)
	_core_mat.emission_enabled = false
	_box(Vector3(1.5, 0.45, 0.28), Vector3.ZERO, _mat)
	_box(Vector3(0.75, 1.25, 0.22), Vector3(0.0, -0.05, 0.05), _mat)
	_box(Vector3(2.25, 0.10, 0.10), Vector3(0.0, 0.25, 0.0), _core_mat)
	_box(Vector3(0.18, 0.62, 0.12), Vector3(-0.86, -0.12, 0.02), _core_mat, -18.0)
	_box(Vector3(0.18, 0.62, 0.12), Vector3(0.86, -0.12, 0.02), _core_mat, 18.0)

func _box(size: Vector3, pos: Vector3, mat: Material, rz: float = 0.0) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.position = pos
	m.rotation_degrees.z = rz
	m.material_override = mat
	add_child(m)

func _process(_delta: float) -> void:
	_t += 1
	if _hit_flash > 0:
		_hit_flash -= 1
	if _diving:
		_update_dive()
	else:
		_update_barrage()
		rotation_degrees.z = sin(_t * 0.016) * 3.0
	var flash := 1.0 if _hit_flash % 2 == 1 else 0.0
	_core_mat.albedo_color = Color(0.25 + flash * 0.65, 0.8, 1.0)

func _update_barrage() -> void:
	var k := clampf(float(_t) / 620.0, 0.0, 1.0)
	position.z = -13.4 + sin(_t * 0.011) * 1.1
	scale = Vector3.ONE * (0.78 + sin(_t * 0.017) * 0.08)
	position.y -= 0.0048
	var target_x := -GameState.px * 0.16 + sin(_t * 0.015) * 1.45
	position.x = lerpf(position.x, target_x, 0.018)
	_shot_t += 1
	if _shot_t > 62 and k > 0.12:
		_shot_t = 0
		_fire_fan()
		_volleys += 1
		if _volleys >= 7:
			_start_dive()
	if position.y < -8.4 or k >= 1.0:
		queue_free()

func _start_dive() -> void:
	_diving = true
	_dive_t = 0
	_dive_start = position
	_dive_target_x = GameState.px

func _update_dive() -> void:
	_dive_t += 1
	var k := clampf(float(_dive_t) / 150.0, 0.0, 1.0)
	var ease := k * k * (3.0 - 2.0 * k)
	var target_z := GameState.alt_to_z(GameState.GROUND_ALT) + 0.45
	position.z = lerpf(_dive_start.z, target_z + 0.4, ease)
	position.x = lerpf(_dive_start.x, _dive_target_x, ease)
	position.y = _dive_start.y - 0.012 * float(_dive_t) - ease * 2.2
	scale = Vector3.ONE * lerpf(0.82, 2.75, ease)
	rotation_degrees.z = sin(_t * 0.08) * lerpf(4.0, 18.0, ease)
	if _dive_t == 46 or _dive_t == 72:
		_fire_fan()
	if position.y < -8.8 or k >= 1.0:
		queue_free()

func is_in_player_range() -> bool:
	return true

func take_hit(_attacker_unit_id: int = 0) -> bool:
	hp -= 1
	_hit_flash = 8
	if hp <= 0:
		GameState.score += 5000
		var ex := Explosion.new()
		ex.color = Color(0.35, 0.8, 1.0)
		ex.count = 18
		ex.strength = 2.0
		get_parent().add_child(ex)
		ex.global_position = global_position
		queue_free()
		return true
	return false

func _fire_fan() -> void:
	var base := atan2(GameState.py - position.y, GameState.px - position.x)
	for i in range(-2, 3):
		if get_tree().get_nodes_in_group("enemy_bullets").size() >= 32:
			return
		var a := base + float(i) * 0.13
		var b := EnemyBullet.new()
		b.velocity = Vector3(cos(a), sin(a), 0.0) * 0.032
		b.alt = GameState.alt / GameState.ALT_MAX
		b.position = Vector3(position.x, position.y, GameState.alt_to_z(GameState.alt))
		get_parent().add_child(b)
