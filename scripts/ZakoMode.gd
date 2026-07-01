extends Node

# ZAKO play (design brief): the player pilots the ZAKO Unit, which spawns ~10 screens
# AHEAD of the HERO in shared world space (its "future front") and attacks the auto-piloting
# HERO. Everything is in world coordinates; Main's camera follows the active actor's world-Y.
#   move: WASD/arrows   ·   altitude: mouse wheel (Main)   ·   fire direction: mouse pointing

const ENEMY_SCENE := preload("res://scenes/units/Enemy.tscn")

const ZAKO_SPAWN_SCREENS := 10.0
const ZAKO_REWARP_SCREENS := 10.0
const ZAKO_PASS_BEHIND := 1.9          # world-Y behind the HERO before the zako redeploys
const ZAKO_SPEED := 0.05
const ZAKO_FIRE_PERIOD := 28
const ZAKO_BULLET_SPEED := 0.052
# Spaceship inertia (design): the ZAKO accelerates and coasts rather than snapping to input.
const ZAKO_ACCEL := 0.0065      # velocity gained per frame at full stick
const ZAKO_FRICTION := 0.90     # velocity retained per frame (coast/decelerate)
const ZAKO_MAX_SPEED := 0.09    # velocity cap

var _zako_unit: Enemy = null
var _zako_vel := Vector2.ZERO   # world-space velocity (momentum)
var _zako_base_scale := 1.0     # scale at reference camera depth (for constant-size compensation)
var _fire_cd := 0
var _hero_opp: Enemy = null     # HERO-mode: the single fixed opponent ZAKO placed ahead

func _ready() -> void:
	process_priority = 1000

func _process(_delta: float) -> void:
	if GameState.is_zako_mode():
		_clear_hero_opponent()
		GameState.zako_unit_active = true
		_ensure_zako_unit()
		_update_zako_unit()
		_enforce_one_vs_one()
		_ensure_terrain_loaded()
	else:
		_clear_zako_unit()
		_clear_build()
		# HERO mode: the ZAKO isn't the active actor, but the design has them converge — so keep
		# ONE opponent ZAKO present ahead in the shared world (fixed, random altitude) for the HERO
		# to find and shoot. Redeploys ahead again once the HERO passes it.
		if GameState.is_zako_prototype_mode():
			_ensure_hero_opponent()
			_update_hero_opponent()
		else:
			_clear_hero_opponent()

func _ensure_zako_unit() -> void:
	if _zako_unit != null and is_instance_valid(_zako_unit):
		return
	GameState.zako_unit_active = true
	_zako_unit = ENEMY_SCENE.instantiate() as Enemy
	_zako_unit.name = "LocalZakoUnit"
	_zako_unit.enemy_type = "toroid"
	_zako_unit.hp = 1
	_zako_unit.max_hp = 1
	_zako_unit.alt = clampf(GameState.zako_alt / GameState.ALT_MAX, 0.0, 1.0)
	_zako_unit.dormant = true
	_zako_unit.set_meta("local_zako_unit", true)
	_zako_unit.add_to_group("enemies")
	_zako_unit.add_to_group("zako_units")
	get_parent().add_child(_zako_unit)
	_zako_base_scale = _zako_unit.scale.x   # Enemy._ready has set its default size by now
	_spawn_attack_run()
	get_tree().call_group("star_hud", "show_message", "ZAKO MODE",
		"Same controls as HERO — move + altitude / auto-aim")

func _clear_zako_unit() -> void:
	if _zako_unit != null and is_instance_valid(_zako_unit):
		_zako_unit.queue_free()
	_zako_unit = null
	GameState.zako_unit_active = false

# --- HERO-mode opponent (fixed, one at a time) -----------------------------------
func _ensure_hero_opponent() -> void:
	if _hero_opp != null and is_instance_valid(_hero_opp) and not _hero_opp.is_queued_for_deletion():
		return
	_hero_opp = ENEMY_SCENE.instantiate() as Enemy
	_hero_opp.name = "HeroModeZakoOpponent"
	_hero_opp.enemy_type = "toroid"
	_hero_opp.hp = 1
	_hero_opp.max_hp = 1
	_hero_opp.dormant = true                       # fixed in world space: no AI, no fire, no scroll-kill
	_hero_opp.set_meta("hero_mode_opponent", true)
	_hero_opp.add_to_group("enemies")              # so HERO fire (bullets→enemies) can destroy it
	_hero_opp.add_to_group("zako_units")
	get_parent().add_child(_hero_opp)
	_deploy_hero_opponent()

# Place the opponent at the regulation respawn spot (~10 screens ahead of the HERO) at a random,
# FIXED altitude. Its apparent size then reads the altitude gap via the camera depth.
func _deploy_hero_opponent() -> void:
	if _hero_opp == null or not is_instance_valid(_hero_opp):
		return
	var ahead := _spawn_ahead_distance()
	var wx := clampf(GameState.hero_pos.x + randf_range(-0.6, 0.6),
		-GameState.PLAYFIELD_HALF_W, GameState.PLAYFIELD_HALF_W)
	var wy := GameState.hero_pos.y + ahead
	var opp_alt := randf_range(0.0, GameState.ALT_MAX)   # random, then held fixed
	_hero_opp.alt = clampf(opp_alt / GameState.ALT_MAX, 0.0, 1.0)
	_hero_opp.global_position = Vector3(wx, wy, GameState.alt_z(opp_alt))
	_hero_opp.rotation.z = PI                             # bearing down toward the HERO (world -Y)

func _update_hero_opponent() -> void:
	if _hero_opp == null or not is_instance_valid(_hero_opp):
		return
	if OS.has_environment("TSG_DEBUG_OPP"):
		var dy := _hero_opp.global_position.y - GameState.hero_pos.y
		if absf(dy) < 3.5:   # within the on-screen band
			print("[OPP] f=%d dy=%.2f alt=%.2f pos=%s" % [GameState.frame, dy,
				_hero_opp.alt, str(_hero_opp.global_position)])
	# HERO advanced past it → redeploy ahead again at a fresh random altitude (keeps one waiting).
	if _hero_opp.global_position.y < GameState.hero_pos.y - ZAKO_PASS_BEHIND:
		_deploy_hero_opponent()

func _clear_hero_opponent() -> void:
	if _hero_opp != null and is_instance_valid(_hero_opp):
		_hero_opp.queue_free()
	_hero_opp = null

# Deploy the ZAKO ~10 screens ahead of the HERO in world-Y (a fresh front each time).
func _spawn_attack_run() -> void:
	if _zako_unit == null or not is_instance_valid(_zako_unit):
		return
	var ahead := _spawn_ahead_distance()
	var front_y := _generate_enemy_front_chunk()
	if front_y > GameState.hero_pos.y:
		ahead = front_y - GameState.hero_pos.y
	GameState.zako_pos = Vector2(GameState.hero_pos.x + randf_range(-0.6, 0.6),
		GameState.hero_pos.y + ahead)
	GameState.zako_alt = GameState.hero_alt
	GameState.zako_talt = GameState.hero_alt       # ZAKO starts at the HERO's altitude
	GameState.zako_aim = Vector2(0.0, -1.0)
	_zako_vel = Vector2.ZERO
	GameState.zako_spawned = true
	_fire_cd = 10
	_zako_unit.alt = clampf(GameState.zako_alt / GameState.ALT_MAX, 0.0, 1.0)
	_zako_unit.global_position = Vector3(GameState.zako_pos.x, GameState.zako_pos.y, 0.0)
	GameState.set_active_actor(GameState.SIDE_ZAKO, GameState.zako_pos.y)
	GameState.update_active_actor_world_y(GameState.zako_pos.y)
	# Snap the camera onto the freshly spawned zako so the switch doesn't pan 10 screens.
	GameState.cam_y = GameState.zako_pos.y
	_ensure_terrain_loaded()
	_recalculate_visible_chunks()

func _update_zako_unit() -> void:
	if _zako_unit == null or not is_instance_valid(_zako_unit):
		return
	# Same controls as HERO (WASD/left stick), but the ZAKO view is faction-relative: Main
	# rolls the camera 180° so ZAKO plays "bottom-to-top" like HERO. Invert the movement so
	# the SCREEN feels identical — press up = go up on screen = advance toward the HERO.
	var mv := Vector2(
		Input.get_action_strength("mv_right") - Input.get_action_strength("mv_left"),
		Input.get_action_strength("mv_up") - Input.get_action_strength("mv_down"))
	if mv.length() > 1.0:
		mv = mv.normalized()
	# Spaceship inertia: input ACCELERATES the velocity (which coasts via friction) rather than
	# setting position directly. Input is inverted to match the 180° faction roll (up = up on
	# screen = toward the HERO). move_speed_mult (slow/boost) scales the thrust.
	_zako_vel += Vector2(-mv.x, -mv.y) * ZAKO_ACCEL * GameState.move_speed_mult()
	_zako_vel *= ZAKO_FRICTION
	if _zako_vel.length() > ZAKO_MAX_SPEED:
		_zako_vel = _zako_vel.normalized() * ZAKO_MAX_SPEED
	# Full Vector2 assignment (never mutate .x/.y through the autoload). CONSTANT world-movement
	# rate (altitude doesn't change traversal — pure-camera model); the apparent speed varies via
	# the per-player camera depth (perspective) and the ÷cam_z background scroll only.
	var zp := GameState.zako_pos + _zako_vel
	if zp.x < -GameState.PLAYFIELD_HALF_W or zp.x > GameState.PLAYFIELD_HALF_W:
		zp.x = clampf(zp.x, -GameState.PLAYFIELD_HALF_W, GameState.PLAYFIELD_HALF_W)
		_zako_vel.x = 0.0   # kill lateral momentum at the playfield edge
	GameState.zako_pos = zp

	_update_auto_aim()

	# Passed behind the HERO → redeploy ahead for another approach.
	if GameState.zako_pos.y < GameState.hero_pos.y - ZAKO_PASS_BEHIND:
		GameState.zako_pos = Vector2(GameState.hero_pos.x + randf_range(-0.9, 0.9),
			GameState.hero_pos.y + _rewrap_ahead_distance())
		GameState.cam_y = GameState.zako_pos.y
		_zako_vel = Vector2.ZERO
		get_tree().call_group("star_hud", "show_message", "ZAKO PASSED",
			"redeploying ahead of HERO Unit")

	_zako_unit.alt = clampf(GameState.zako_alt / GameState.ALT_MAX, 0.0, 1.0)
	# Altitude = world DEPTH (z): the ZAKO sits at alt_z(zako_alt). As the SELF the camera rides
	# above it (constant size). Scale FIXED (priority 1000 overrides Enemy's own scale).
	_zako_unit.global_position = Vector3(GameState.zako_pos.x, GameState.zako_pos.y,
		GameState.alt_z(GameState.zako_alt))
	_zako_unit.scale = Vector3(_zako_base_scale, _zako_base_scale, _zako_base_scale)
	_zako_unit.rotation.z = atan2(GameState.zako_aim.x, -GameState.zako_aim.y)
	GameState.update_active_actor_world_y(GameState.zako_pos.y)
	_update_zako_fire()
	_update_build()

# --- Zako terrain paint (hold-to-paint by flying, distance-paced) --------------------
# HOLD build_paint (R3 / F) and fly — incl. altitude — to drop a REAL TSG megastructure/terrain
# every PAINT_SPACING units along the path, so a run overlaps into one big mega-map. The build
# LAYER is the current altitude (HI/MID/LO). △ (interact / Space / Y) ERASES the band you're over.
const PAINT_SPACING := 2.6
var _last_paint_pos := Vector2(1e9, 1e9)
var _stroke_id := 0             # bumped each new R3 stroke → a stroke lays one continuous feature

func _update_build() -> void:
	var mgr := get_tree().get_first_node_in_group("enemy_front_mgr")
	if mgr == null:
		return
	var painting := Input.is_action_pressed("build_paint")
	var erasing := Input.is_action_pressed("interact")
	var layer := _alt_layer(GameState.zako_alt)
	var band: int = int(mgr.call("band_at", GameState.zako_pos.y))
	GameState.build_painting = painting and not erasing
	GameState.build_layer = layer
	GameState.build_credits = float(mgr.call("build_credits"))
	if erasing:
		mgr.call("remove_at_band", band)                     # scrub terrain as you fly over it
		_last_paint_pos = Vector2(1e9, 1e9)
	elif painting:
		# Distance-paced: drop a piece once the ZAKO has moved far enough from the last one. Roads/
		# rails connect from_pos→to_pos, so a held stroke draws one unbroken ribbon.
		var fresh := _last_paint_pos.x > 1e8
		if fresh or GameState.zako_pos.distance_to(_last_paint_pos) >= PAINT_SPACING:
			if fresh:
				_stroke_id += 1                              # new stroke → new continuous feature
			var from_p := GameState.zako_pos if fresh else _last_paint_pos
			var placed := String(mgr.call("paint_at", from_p, GameState.zako_pos, layer, _stroke_id))
			if placed != "":
				_last_paint_pos = GameState.zako_pos
				TsgAudio.block_chip()
	else:
		_last_paint_pos = Vector2(1e9, 1e9)                  # released → next stroke starts fresh
	GameState.build_reason = String(mgr.call("can_paint", band, layer))

# Current continuous altitude → discrete build layer LOW / MID / HIGH.
func _alt_layer(a: float) -> int:
	var t := a / GameState.ALT_MAX
	if t < 1.0 / 3.0:
		return 0
	if t < 2.0 / 3.0:
		return 1
	return 2

func _clear_build() -> void:
	GameState.build_reason = ""
	GameState.build_painting = false
	_last_paint_pos = Vector2(1e9, 1e9)

# ZAKO auto-aim (spec): loose "zako-like" fire. Forward is toward the HERO (world -Y). If the
# HERO sits within ~45° of forward, nudge the aim partway onto it; otherwise fire straight.
func _update_auto_aim() -> void:
	var forward := Vector2(0.0, -1.0)
	var to_hero := GameState.hero_pos - GameState.zako_pos
	if to_hero.length() > 0.01:
		to_hero = to_hero.normalized()
		var ang := forward.angle_to(to_hero)
		if absf(ang) <= deg_to_rad(45.0):
			GameState.zako_aim = forward.rotated(ang * 0.6)   # light correction only
			return
	GameState.zako_aim = forward

func _spawn_ahead_distance() -> float:
	return maxf(12.0, _screen_world_height() * ZAKO_SPAWN_SCREENS)

func _rewrap_ahead_distance() -> float:
	return maxf(12.0, _screen_world_height() * ZAKO_REWARP_SCREENS)

func _screen_world_height() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 6.0
	var sz := get_viewport().get_visible_rect().size
	# Depth to the ZAKO's play plane. The prototype places the ZAKO at alt_z(zako_alt) and the
	# camera CAM_REF_DIST above it, so this is a constant CAM_REF_DIST. (Was GENESIS alt_to_z,
	# which mismatched the new alt_z camera → wrong "10 screens ahead" spawn at non-HI altitude.)
	var depth := camera.global_position.z - GameState.alt_z(GameState.zako_alt)
	var top := camera.project_position(Vector2(sz.x * 0.5, 0.0), depth)
	var bottom := camera.project_position(Vector2(sz.x * 0.5, sz.y), depth)
	return absf(bottom.y - top.y)

func _ensure_terrain_loaded(extra_ahead: float = 0.0) -> void:
	if _zako_unit == null or not is_instance_valid(_zako_unit):
		return
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr == null:
		return
	var target_y := _zako_unit.global_position.y + maxf(extra_ahead, _screen_world_height() * 1.5)
	if terr.has_method("ensure_chunks_around"):
		terr.call("ensure_chunks_around", _zako_unit.global_position.y, GameState.chunk_preload_screens)
	elif terr.has_method("ensure_generated_to"):
		terr.call("ensure_generated_to", target_y)

func _generate_enemy_front_chunk() -> float:
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr != null and terr.has_method("generate_enemy_front_chunk"):
		return float(terr.call("generate_enemy_front_chunk", GameState.hero_pos.y, ZAKO_SPAWN_SCREENS))
	# Space/front-block prototype can run without PlanetTerrain; in that case ZAKO still spawns
	# ten screens ahead and any player-painted EnemyFront blocks persist in GameState.front_blocks.
	return GameState.hero_pos.y + _spawn_ahead_distance()

func _recalculate_visible_chunks() -> void:
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr != null and terr.has_method("recalculate_visible_chunks"):
		terr.call("recalculate_visible_chunks")

func _enforce_one_vs_one() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == _zako_unit:
			continue
		if node is Node and is_instance_valid(node):
			(node as Node).queue_free()
	for group_name in ["boundary_gate", "target_planet", "mothership_beacon", "mothership",
			"route_plate", "arena_gate", "golden_icon"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node and is_instance_valid(node):
				(node as Node).queue_free()
	GameState.gate_active = false
	GameState.route_armed = false
	GameState.carrier_takeover = false

func _update_zako_fire() -> void:
	# Same fire button as HERO (□ / left-click, hold to autofire); the only difference is
	# auto-aim (zako_aim), computed in _update_auto_aim. Release = ready to fire on next press.
	if not Input.is_action_pressed("fire"):
		_fire_cd = 0
		return
	_fire_cd -= 1
	if _fire_cd > 0:
		return
	_fire_cd = ZAKO_FIRE_PERIOD
	if _zako_unit == null or not is_instance_valid(_zako_unit):
		return
	var dir := GameState.zako_aim
	if dir.length_squared() <= 0.0001:
		dir = Vector2(0.0, -1.0)
	var b := EnemyBullet.new()
	b.bullet_type = "fan"
	b.velocity = Vector3(dir.x, dir.y, 0.0) * ZAKO_BULLET_SPEED
	b.alt = _zako_unit.alt
	b.position = _zako_unit.global_position
	get_parent().add_child(b)
