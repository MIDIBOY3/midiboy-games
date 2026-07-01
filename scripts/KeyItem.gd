class_name KeyItem
extends Node3D

# RELIC — campaign key item dropped by abyss guardians. It never expires:
# it sinks with the scroll but hovers at the bottom edge of the screen until
# collected. Securing BOSS_REQ_ITEMS of these (plus the guardian kills) makes
# the OMEGA CORE boss star appear in space.

const COLLECT_RADIUS := 0.4
const MAGNET_RADIUS := 1.4

var t: int = 0
var item_kind: String = "relic" # "relic" | "oopart" | "boss_relic" | "arena_relic"
var arena_floor_drop: bool = false
var fall_alt: float = 0.0
var _mat: StandardMaterial3D
var _holder: Node3D
var _relic_light: OmniLight3D = null   # arena_relic beacon glow
var _relic_ring: MeshInstance3D = null # arena_relic pulsing ground ring

func _ready() -> void:
	add_to_group("key_items")
	if item_kind == "boss_relic":
		add_to_group("boss_relic")
	var col := Color(0.95, 0.35, 1.0) if item_kind == "boss_relic" \
		else (Color(1.0, 0.85, 0.25) if item_kind == "relic" \
		else (Color(0.35, 1.0, 0.55) if item_kind == "arena_relic" else Color(0.35, 1.0, 0.9)))
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = col
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 3.8 if item_kind == "arena_relic" else 2.2
	_holder = Node3D.new()
	add_child(_holder)
	# Golden double-diamond (two nested rotated boxes). The arena STAR RELIC is bigger so it
	# reads on the dark cave floor (it was being walked over unnoticed).
	var sizes := [0.22, 0.13] if item_kind == "oopart" \
		else ([0.34, 0.21] if item_kind == "boss_relic" \
		else ([0.30, 0.18] if item_kind == "arena_relic" else [0.13, 0.08]))
	for s: float in sizes:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(s, s, s)
		m.mesh = box
		m.rotation_degrees = Vector3(45.0, 0.0, 45.0 if s > 0.1 else 0.0)
		m.material_override = _mat
		_holder.add_child(m)
	if item_kind == "oopart" or item_kind == "boss_relic" or item_kind == "arena_relic":
		for i in 4:
			var b := MeshInstance3D.new()
			var beam := BoxMesh.new()
			beam.size = Vector3(0.060, 0.78, 0.060) if item_kind == "boss_relic" \
				else (Vector3(0.052, 0.70, 0.052) if item_kind == "arena_relic" \
				else Vector3(0.035, 0.46, 0.035))
			b.mesh = beam
			b.rotation_degrees.z = 45.0 * float(i)
			b.material_override = _mat
			_holder.add_child(b)
	if item_kind == "arena_relic":
		_build_relic_beacon(col)
	if arena_floor_drop:
		if fall_alt <= 0.0:
			fall_alt = GameState.ARENA_FLOOR_ALT

# The STAR RELIC is easy to walk over unnoticed on the dark cave floor, so dress it as a BEACON:
# a green point light that pools on the ground, a light column rising toward the (top-down) camera,
# and a pulsing ground ring — all readable from across the arena.
func _build_relic_beacon(col: Color) -> void:
	# Parent the beacon parts to the ROOT (not _holder) so they stay put — _holder spins the
	# diamonds each frame, which would swing an offset column around.
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = 6.0
	light.omni_attenuation = 1.0
	light.light_energy = 4.0
	light.shadow_enabled = false
	add_child(light)
	_relic_light = light
	# Light column toward the camera (the arena is viewed top-down, so +z reads as "up out of the
	# floor"). Unshaded additive so it glows regardless of the dim cave lighting.
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.085, 0.085, 3.2)
	beam.mesh = bm
	beam.position.z = 1.5
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(col.r, col.g, col.b, 0.55)
	beam_mat.emission_enabled = true
	beam_mat.emission = col
	beam_mat.emission_energy_multiplier = 3.0
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = beam_mat
	add_child(beam)
	# Pulsing ground-ring target marker, laid flat on the floor plane (faces the camera).
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.46
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.position.z = 0.05
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = col
	ring_mat.emission_enabled = true
	ring_mat.emission = col
	ring_mat.emission_energy_multiplier = 3.5
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = ring_mat
	add_child(ring)   # parent to the root (not _holder) so it doesn't spin with the diamonds
	_relic_ring = ring

func _process(_delta: float) -> void:
	t += 1
	# Sinks with the world but never leaves: it waits at the screen's bottom. The GERWALK arena
	# doesn't scroll (the player walks out into static world space), so an arena_relic must stay
	# pinned to its world-y instead — the player walks back over it to collect.
	if item_kind != "arena_relic":
		position.y = maxf(position.y - PlanetTerrain.SCROLL, -2.0)
	_holder.rotation_degrees.y += 4.5 if item_kind == "boss_relic" \
		else (4.0 if item_kind == "oopart" else 2.4)
	_mat.emission_energy_multiplier = (3.0 + 2.0 * sin(t * 0.16)) \
		if item_kind == "boss_relic" else ((2.4 + 1.6 * sin(t * 0.16)) \
		if item_kind == "oopart" else ((3.2 + 2.6 * sin(t * 0.14)) \
		if item_kind == "arena_relic" else (1.6 + 1.2 * sin(t * 0.12))))
	# Animate the arena beacon: a breathing point light + an expanding ground ring marker.
	if item_kind == "arena_relic":
		var pulse := 0.5 + 0.5 * sin(t * 0.14)
		if _relic_light != null and is_instance_valid(_relic_light):
			_relic_light.light_energy = 3.0 + 3.5 * pulse
		if _relic_ring != null and is_instance_valid(_relic_ring):
			var rs := 1.0 + 0.55 * pulse
			# Torus lies in its local XZ plane (central axis Y) — scale those two axes to grow the ring.
			_relic_ring.scale = Vector3(rs, 1.0, rs)

	if GameState.game_over or GameState.in_transition():
		return
	if arena_floor_drop:
		fall_alt = maxf(GameState.ARENA_FLOOR_ALT, fall_alt - 2.6)
		position.z = GameState.alt_to_z(fall_alt)
		position.y = maxf(position.y, -2.4)
	else:
		# Always collectable where it appears: snap to the player's altitude plane.
		position.z = GameState.alt_to_z(GameState.alt) + (0.18 if item_kind == "oopart" else 0.0)
	var pp := Vector2(GameState.px, GameState.py)
	var d := Vector2(position.x, position.y).distance_to(pp)
	var magnet_r := MAGNET_RADIUS * (3.6 if item_kind == "boss_relic" else (1.8 if item_kind == "oopart" else 1.0))
	var collect_r := COLLECT_RADIUS * (2.4 if item_kind == "boss_relic" else (1.5 if item_kind == "oopart" else 1.0))
	if d < magnet_r:
		var pull := 0.16 if item_kind == "boss_relic" else 0.1
		position.x = lerpf(position.x, GameState.px, pull)
		position.y = lerpf(position.y, GameState.py, pull)
		d = Vector2(position.x, position.y).distance_to(pp)
	var alt_ok := true
	if arena_floor_drop:
		alt_ok = fall_alt <= GameState.ARENA_FLOOR_ALT + 90.0 \
			and absf(GameState.alt - fall_alt) < 120.0
	if d < collect_r and alt_ok:
		_collect()

func _collect() -> void:
	GameState.score += 5000
	var title := ""
	var sub := ""
	if item_kind == "oopart":
		GameState.underground_ooparts = mini(GameState.underground_ooparts + 1, 3)
		if GameState.underground_ooparts >= 3:
			GameState.underground_boss_unlocked = true
			sub = Loc.t("DEEP GUARDIAN SIGNAL DETECTED")
		title = "%s  %d / 3" % [Loc.t("OOPART SECURED"), GameState.underground_ooparts]
	elif item_kind == "boss_relic":
		GameState.key_items += 1
		GameState.arena_reward_pending = false
		GameState.underground_boss_defeated = true
		var main := get_tree().current_scene
		if main != null and main.has_method("_begin_arena_exit_rise"):
			main.call("_begin_arena_exit_rise")
		if GameState.boss_star_ready():
			sub = Loc.t("THE OMEGA CORE STAR HAS APPEARED - FIND IT IN SPACE")
		else:
			sub = Loc.t("ASCENDING TO SURFACE")
		title = "%s  %d / %d" % [Loc.t("BOSS RELIC SECURED"), GameState.key_items, GameState.BOSS_REQ_ITEMS]
	elif item_kind == "arena_relic":
		GameState.arena_relics_found = mini(GameState.arena_relics_found + 1, GameState.ARENA_RELIC_GOAL)
		title = "%s  %d / %d" % [Loc.t("STAR RELIC"), GameState.arena_relics_found, GameState.ARENA_RELIC_GOAL]
		TsgAudio.star_relic_get()
		if GameState.arena_relics_found >= GameState.ARENA_RELIC_GOAL:
			sub = Loc.t("A SEALED WALL FRAMES IN AHEAD")
			var main := get_tree().current_scene
			if main != null and main.has_method("on_arena_relics_complete"):
				main.call("on_arena_relics_complete")
	else:
		GameState.key_items += 1
		if GameState.boss_star_ready():
			sub = Loc.t("THE OMEGA CORE STAR HAS APPEARED - FIND IT IN SPACE")
		title = "%s  %d / %d" % [Loc.t("RELIC SECURED"), GameState.key_items, GameState.BOSS_REQ_ITEMS]
	get_tree().call_group("star_hud", "show_message", title, sub)
	var ex := Explosion.new()
	ex.color = Color(0.35, 1.0, 0.55) if item_kind == "arena_relic" else Color(1.0, 0.85, 0.3)
	ex.count = 20 if item_kind == "arena_relic" else 14
	ex.strength = 1.5 if item_kind == "arena_relic" else 1.2
	get_parent().add_child(ex)
	ex.global_position = global_position
	queue_free()
