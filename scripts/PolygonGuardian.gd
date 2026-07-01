class_name PolygonGuardian
extends Node3D

var enemy_type: String = "poly_guardian"
var hp: int = 220
var max_hp: int = 220
var hue: float = 5.0
var alt: float = 0.0

var t: int = 0
var _hit_flash: int = 0
var _charge_t: int = 0
var _mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _joints: Array = []
var _plates: Array = []
const MAX_BOSS_BULLETS := 18

func _ready() -> void:
	add_to_group("enemies")
	alt = GameState.alt / GameState.ALT_MAX
	position.z = GameState.enemy_z(alt)
	_build_body()

func _build_body() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.08, 0.065, 0.09)
	_mat.roughness = 0.9
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(1.0, 0.08, 0.035)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.08, 0.035)
	_core_mat.emission_energy_multiplier = 2.5

	_add_box(Vector3(1.45, 0.82, 0.46), Vector3.ZERO, _mat)
	_add_box(Vector3(0.95, 1.18, 0.36), Vector3(0.0, 0.0, 0.08), _mat, 45.0)
	_add_box(Vector3(0.48, 0.48, 0.22), Vector3(0.0, 0.0, 0.34), _core_mat, 45.0)
	for y: float in [-0.52, 0.52]:
		_add_box(Vector3(1.95, 0.18, 0.22), Vector3(0.0, y, -0.04), _mat)
		_add_box(Vector3(0.22, 0.64, 0.18), Vector3(-0.96, y, 0.0), _core_mat, 18.0)
		_add_box(Vector3(0.22, 0.64, 0.18), Vector3(0.96, y, 0.0), _core_mat, -18.0)
	for side: float in [-1.0, 1.0]:
		for y: float in [-0.58, 0.58]:
			_add_joint_chain(side, y)
	for i in 4:
		var a := TAU * float(i) / 4.0
		var plate := _add_box(Vector3(0.42, 0.16, 0.12),
			Vector3(cos(a) * 0.62, sin(a) * 0.34, 0.2), _core_mat, rad_to_deg(a))
		_plates.append(plate)

func _add_box(size: Vector3, pos: Vector3, mat: Material, rot_z: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.position = pos
	m.rotation_degrees.z = rot_z
	m.material_override = mat
	add_child(m)
	return m

func _add_joint_chain(side: float, y: float) -> void:
	var joint := Node3D.new()
	joint.position = Vector3(side * 0.82, y, -0.02)
	add_child(joint)
	_joints.append(joint)
	for i in 2:
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.36 - float(i) * 0.05, 0.14, 0.14)
		seg.mesh = box
		seg.position = Vector3(side * (0.22 + float(i) * 0.22), 0.0, 0.0)
		seg.rotation_degrees.z = side * (12.0 + float(i) * 7.0)
		seg.material_override = _mat if i < 2 else _core_mat
		joint.add_child(seg)

func _process(_delta: float) -> void:
	t += 1
	if _hit_flash > 0:
		_hit_flash -= 1
	var flash := 1.0 if _hit_flash % 2 == 1 else 0.0
	_core_mat.emission_energy_multiplier = 2.2 + 1.4 * sin(t * 0.1) + flash * 3.0
	if (t & 1) == 0:
		for i in _joints.size():
			var j := _joints[i] as Node3D
			j.rotation_degrees.z = sin(t * 0.055 + float(i) * 0.9) * 28.0
			j.rotation_degrees.x = cos(t * 0.043 + float(i)) * 10.0
		for i in _plates.size():
			var p := _plates[i] as MeshInstance3D
			p.rotation_degrees.z += 3.6 + float(i) * 0.24

	if GameState.arena_active:
		# Dodge by WEAVING up and down the arena band (slow swing + faster jitter), so
		# the player must match the boss's altitude to land hits (see is_in_player_range).
		var lo := GameState.ARENA_FLOOR_ALT
		var hi := GameState.ARENA_CEIL_ALT
		var mid := (lo + hi) * 0.5
		var amp := (hi - lo) * 0.42
		var weave := mid + sin(t * 0.013) * amp + sin(t * 0.047) * (amp * 0.28)
		alt = lerpf(alt, clampf(weave, lo, hi) / GameState.ALT_MAX, 0.05)
		position.x = lerpf(position.x, sin(t * 0.011) * 2.2, 0.02)
	else:
		var target_alt := minf(GameState.alt / GameState.ALT_MAX, GameState.GROUND_ALT / GameState.ALT_MAX * 0.62)
		alt = lerpf(alt, target_alt, 0.018)
		position.x = lerpf(position.x, sin(t * 0.011) * 1.75, 0.018)
	position.z = GameState.enemy_z(alt)
	position.y = lerpf(position.y, 1.05, 0.012)
	scale = Vector3.ONE * (1.25 + 0.04 * sin(t * 0.08))
	rotation_degrees.z = sin(t * 0.018) * 8.0

	_charge_t += 1
	if _charge_t >= 70:
		_charge_t = 0
		var mode := (t / 70) % 3
		if mode == 0:
			_fire_aimed_fan()
		elif mode == 1:
			_fire_limb_sweep()
		else:
			_fire_ring()
	if position.y < -3.2:
		queue_free()

func is_in_player_range() -> bool:
	# In the arena the boss dodges shots by changing altitude: it's only hittable when
	# the player's altitude is near the boss's, so you must chase its depth to land hits.
	if GameState.arena_active:
		return absf(GameState.alt - alt * GameState.ALT_MAX) < 30.0
	return true

func take_hit(_attacker_unit_id: int = 0) -> bool:
	hp -= 1
	_hit_flash = 8
	if hp <= 0:
		_on_down()
		queue_free()
		return true
	return false

func _on_down() -> void:
	GameState.mid_bosses += 1
	GameState.arena_reward_pending = true
	GameState.underground_boss_unlocked = false
	GameState.underground_biome = GameState.underground_base_biome
	if GameState.arena_active:
		var main := get_tree().current_scene
		if main != null and main.has_method("spawn_arena_boss_relic"):
			main.call_deferred("spawn_arena_boss_relic")
	else:
		var relic := KeyItem.new()
		get_parent().add_child(relic)
		relic.global_position = global_position
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.12, 0.04)
	ex.count = 28
	ex.strength = 2.0
	get_parent().add_child(ex)
	ex.global_position = global_position
	get_tree().call_group("star_hud", "show_message",
		Loc.pair("ポリゴンボス破壊  %d / %d", "POLYGON BOSS DESTROYED  %d / %d")
			% [GameState.mid_bosses, GameState.BOSS_REQ_BOSSES],
		"FINAL RELIC DROPPING TO THE LOWEST LAYER")

func _fire_aimed_fan() -> void:
	var base_ang := atan2(GameState.py - position.y, GameState.px - position.x)
	for i in range(-2, 3):
		var ang := base_ang + float(i) * 0.15
		_spawn_bullet(global_position, Vector3(cos(ang), sin(ang), 0.0) * 0.038)

func _fire_ring() -> void:
	var base := randf() * TAU
	for i in 8:
		var ang := base + TAU * float(i) / 8.0
		_spawn_bullet(global_position, Vector3(cos(ang), sin(ang), 0.0) * 0.03)

func _fire_limb_sweep() -> void:
	for i in _joints.size():
		if i % 2 != t % 2:
			continue
		var j := _joints[i] as Node3D
		var ang := j.global_rotation.z + (0.0 if j.global_position.x > position.x else PI)
		_spawn_bullet(j.global_position, Vector3(cos(ang), sin(ang), 0.0) * 0.033)

func _spawn_bullet(global_pos: Vector3, vel: Vector3) -> void:
	if get_tree().get_nodes_in_group("enemy_bullets").size() >= MAX_BOSS_BULLETS:
		return
	var b := EnemyBullet.new()
	b.velocity = vel
	b.alt = alt
	# Callers pass world-space positions; convert into the shared parent space.
	b.position = get_parent().to_local(global_pos)
	get_parent().add_child(b)
