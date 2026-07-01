extends Node3D

var alt_t: float    = 0.0
var cruise_t: float = 0.0
var robot_t: float  = 0.0
var bullet_scene: PackedScene = null
var _shoot_timer: int = 2  # offset so units don't all fire on the same frame
# Smoothed attack-pose envelopes (avoid a 1-frame pose pop on each strike).
var _punch_s: float = 0.0
var _laser_s: float = 0.0
var _rocket_s: float = 0.0

# Lock-on missile system (formation mode)
const LOCK_INTERVAL := 4    # min frames between sequential air-enemy locks ("pi-pi-pi")
var _lock_timer: int = 0
# Rockets stream out ONE AFTER ANOTHER from this queue (RayStorm). A locked air enemy is
# pushed on the instant it's locked — no waiting to fill a salvo.
const LAUNCH_GAP := 6       # frames between successive rocket launches
const LOCK_LAG := 25        # arming lag: frames a fresh lock waits before its rocket fires
var _launch_queue: Array = []
var _arm: Dictionary = {}   # target → earliest frame its rocket may launch
var _launch_cd: int = 0
var _launch_side: float = -1.0
# Ground bombardment: on a planet surface Unit3 auto-fires homing mining missiles.
var _ground_cd: int = 0

func set_bullet_scene(s: PackedScene) -> void:
	bullet_scene = s

@onready var _left_arm:   Node3D        = $left_arm_group
@onready var _right_arm:  Node3D        = $right_arm_group
@onready var _center:     Node3D        = $center_body
@onready var _left_bar:   MeshInstance3D = $left_inner_bar
@onready var _right_bar:  MeshInstance3D = $right_inner_bar
@onready var _cockpit:    Node3D        = $cockpit_group

func set_rig(p_alt_t: float, p_cruise_t: float) -> void:
	alt_t    = clamp(p_alt_t,    0.0, 1.0)
	cruise_t = clamp(p_cruise_t, 0.0, 1.0)

func set_robot(p_robot_t: float) -> void:
	robot_t = clamp(p_robot_t, 0.0, 1.0)

func _process(_delta: float) -> void:
	var arm_out  := cruise_t * 0.055
	var arm_down := cruise_t * 0.095
	var low_down := alt_t * 0.18
	var low_in   := alt_t * 0.008
	var stow_y   := alt_t * 0.14

	# Flight-mode arm positions.
	var fl_lx := -arm_out + low_in
	var fl_ly := -arm_down - low_down - stow_y * 0.45
	var fl_rx :=  arm_out - low_in
	var fl_ry := fl_ly

	# Robot-mode arm positions: shoulder joint fixed here, only rotation creates the arm span.
	var rob_lx := -0.10
	var rob_ly :=  0.0
	var rob_rx :=  0.10
	var rob_ry :=  0.0

	# Shoulder stays fixed — no position inertia so the joint never detaches.
	_left_arm.position  = Vector3(lerpf(fl_lx, rob_lx, robot_t), lerpf(fl_ly, rob_ly, robot_t), 0.0)
	_right_arm.position = Vector3(lerpf(fl_rx, rob_rx, robot_t), lerpf(fl_ry, rob_ry, robot_t), 0.0)

	# Arm inertia: rotation around the shoulder joint (banking + hanging).
	# vx clamped so large mouse jumps never create visible separation.
	var vx_c: float = clampf(GameState.vx, -0.03, 0.03)
	var vy_c: float = clampf(GameState.vy, -0.03, 0.03)
	var arm_bank: float = 0.0 if GameState.robot_static else vx_c * robot_t * 80.0    # banking: left up / right down when moving right
	var arm_hang: float = 0.0 if GameState.robot_static else -vy_c * robot_t * 80.0   # hanging: both arms droop when accelerating up

	# --- Humanoid attack motion (Golden robot). Envelopes come from Unit1,
	# smoothed so each strike eases in over a few frames (a 1-frame pose pop reads
	# as a flicker). The screen-position raise/lower pose was removed by request. ---
	_punch_s  = move_toward(_punch_s,  GameState.robot_punch * robot_t,       0.18)
	_laser_s  = move_toward(_laser_s,  GameState.robot_laser_pose * robot_t,  0.12)
	_rocket_s = move_toward(_rocket_s, GameState.robot_rocket_pose * robot_t, 0.10)
	var rp := _punch_s
	var rl := _laser_s
	var rr := _rocket_s
	var l_punch := rp if GameState.robot_punch_side < 0 else 0.0
	var r_punch := rp if GameState.robot_punch_side > 0 else 0.0
	# (Removed the anti-phase idle sway `sin(frame)*±4°` — same scissoring flicker
	# as Unit5's legs; the standing robot now holds its arms still at rest.)

	# Shoulder thrust toward pointing UP (0°): the PUNCHING arm drives a big jab
	# while the other pulls back (chamber) — a human counter-motion. Laser/rocket
	# raise both arms together. (Tunable: 110 jab / -40 chamber.)
	var l_thrust := 0.0 if GameState.robot_static else clampf(110.0 * l_punch + 90.0 * rl + 70.0 * rr - 40.0 * r_punch, -40.0, 120.0)
	var r_thrust := 0.0 if GameState.robot_static else clampf(110.0 * r_punch + 90.0 * rl + 70.0 * rr - 40.0 * l_punch, -40.0, 120.0)
	# Left arm rests at +90 (points left) → thrust subtracts toward 0 (up);
	# right arm rests at -90 → thrust adds toward 0.
	# Build each arm's transform in ONE assignment: basis = rotZ · scaleY, keeping
	# the origin set above. The arm is non-uniformly scaled (y up to 1.6), so setting
	# .scale and .rotation_degrees SEPARATELY made Godot flip between two basis
	# decompositions every frame → the arm snapped between 2 shapes (same bug the
	# legs had). Assigning the basis directly avoids the decomposition.
	# The jab lunges the whole arm a little farther from the shoulder.
	var arm_scale := lerpf(1.0, 1.6, robot_t)
	# F5 walk: arms swing FORE/AFT (X) in counter-phase to the same-side leg, so the arm
	# OPPOSITE the forward foot leads (l_pump uses gait+PI = opposite the left leg's sin(g)).
	# Rest angle is RAISED from 90°→118° to LOWER the arms toward the body (NOT 64° — that
	# rotated them up into a banzai). Gated behind golden_walk; faded by amplitude & robot_t.
	var l_pump := 0.0
	var r_pump := 0.0
	var arm_span := 90.0
	if GameState.golden_walk:
		var amp: float = GameState.golden_gait_amp * robot_t
		l_pump = sin(GameState.golden_gait + PI) * 22.0 * amp
		r_pump = sin(GameState.golden_gait) * 22.0 * amp
		arm_span = 118.0
	var l_rot := deg_to_rad( arm_span * robot_t + arm_hang + arm_bank - l_thrust)
	var r_rot := deg_to_rad(-arm_span * robot_t + arm_hang - arm_bank + r_thrust)
	var l_scale := Vector3(1.0, arm_scale * (1.0 + 0.45 * l_punch + 0.30 * rl + 0.25 * rr), 1.0)
	var r_scale := Vector3(1.0, arm_scale * (1.0 + 0.45 * r_punch + 0.30 * rl + 0.25 * rr), 1.0)
	_left_arm.transform  = Transform3D(Basis.from_euler(Vector3(deg_to_rad(l_pump), 0.0, l_rot)).scaled_local(l_scale), _left_arm.position)
	_right_arm.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(r_pump), 0.0, r_rot)).scaled_local(r_scale), _right_arm.position)

	_center.position.y = lerpf(-cruise_t * 0.02 - low_down, 0.0, robot_t)

	_left_bar.scale.y  = maxf(0.1, 1.0 - alt_t * 0.5)
	_right_bar.scale.y = maxf(0.1, 1.0 - alt_t * 0.5)

	_cockpit.position.y = lerpf(low_down * 0.04, -0.17, robot_t)

	if GameState.sep_t > 0.5 and robot_t < 0.5 and bullet_scene != null:
		_update_lock_system()
	else:
		GameState.lock_ring_radius = 0.0
		GameState.lock_targets = []
	_process_launch_queue()   # rockets keep streaming out even after combining
	_handle_shoot()

func _handle_shoot() -> void:
	if bullet_scene == null or robot_t > 0.5 or GameState.carrier_battle or GameState.ending_cinematic \
			or GameState.boss_intro_active or GameState.god_phase > 0:
		return
	var lv := GameState.unit_level(3)
	var interval: int = 8 if lv <= 2 else (6 if lv <= 4 else 4)
	_shoot_timer += 1
	if _shoot_timer < interval:
		return
	_shoot_timer = 0
	if GameState.sep_t > 0.5:
		return  # formation attacks are handled by the lock-on missile system
	_shoot_combined()

# --- Lock-on system (player-driven) ---
# A lock-on circle follows the player. Unit3 never locks on by itself: only
# enemies the PLAYER sweeps the circle over get locked ("pi" per touch, max
# one new lock per LOCK_INTERVAL frames), at ANY altitude. When the lock count
# is full (4 + level) — or locks are held with nothing new for a while — all
# missiles launch at once.
func _update_lock_system() -> void:
	# Pending rockets are the launch queue; the HUD reticles read it.
	_launch_queue = _launch_queue.filter(func(e: Variant) -> bool:
		return e == null or (is_instance_valid(e) and not (e as Node).is_queued_for_deletion()))
	GameState.lock_targets = _launch_queue.filter(func(e: Variant) -> bool: return e != null)

	var pscale := lerpf(0.5, 1.0, GameState.sky_t())
	var ring_r := 0.55 * pscale
	GameState.lock_ring_radius = ring_r

	# AIR ENEMIES: the player sweeps the ship's lock circle (Unit1's) over them. Each one
	# the circle touches is locked AND fired at IMMEDIATELY — pushed onto the launch queue
	# so rockets streak out one after another, no waiting to fill a salvo.
	_lock_timer += 1
	if _lock_timer >= LOCK_INTERVAL:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var player_p := Vector3(GameState.px, GameState.py,
				GameState.alt_to_z(GameState.alt))
			var center := camera.unproject_position(player_p)
			var ring_px := center.distance_to(
				camera.unproject_position(player_p + Vector3(ring_r, 0.0, 0.0)))
			for node in get_tree().get_nodes_in_group("enemies"):
				var e := node as Node3D
				if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
					continue
				if e in _launch_queue:
					continue   # already has a rocket inbound
				if center.distance_to(camera.unproject_position(e.global_position)) < ring_px:
					_launch_queue.append(e)
					_arm[e] = GameState.frame + LOCK_LAG   # arm a beat before it fires
					TsgAudio.lock_ping(mini(_launch_queue.size(), 8))
					_lock_timer = 0
					break  # one lock per interval — the pi-pi-pi rhythm

	# GROUND BLOCKS: on a planet surface Unit3 auto-bombards — a homing mining missile on a
	# steady cadence (faster at higher level). Null target → it seeks the nearest block.
	# Only when a mineable terrain is present (don't lob rockets into empty high orbit).
	if GameState.stage == "planet" and get_tree().get_first_node_in_group("planet_terrain") != null:
		_ground_cd -= 1
		if _ground_cd <= 0:
			_ground_cd = maxi(18, 46 - GameState.unit_level(3) * 4)
			_launch_ground_missile()

# A homing mining missile aimed at no enemy: the Missile auto-seeks the nearest surface
# block and breaks it. Alternates sides for a fanned bombardment.
func _launch_ground_missile() -> void:
	_launch_side = -_launch_side
	var m := Missile.new()
	m.target = null
	m.velocity = Vector3(_launch_side * 0.04, 0.03, 0.0)   # punch out, then it homes down-range
	get_parent().add_child(m)
	m.global_position = global_position + Vector3(_launch_side * 0.08 * scale.x, 0.05, 0.0)
	TsgAudio.unit3_explosion()

# Streams the salvo out: one big rocket per LAUNCH_GAP frames toward each locked target,
# alternating sides for a fanned RayStorm volley. Runs every frame (any mode).
func _process_launch_queue() -> void:
	if _launch_queue.is_empty():
		return
	if _launch_cd > 0:
		_launch_cd -= 1
		return
	# Arming lag: the oldest lock holds fire until its delay elapses, so sweeping a
	# lock over an enemy no longer deletes it the same instant.
	var front: Variant = _launch_queue[0]
	if front != null and int(_arm.get(front, 0)) > GameState.frame:
		return
	_launch_cd = LAUNCH_GAP
	var e: Variant = _launch_queue.pop_front()
	_arm.erase(e)
	if e == null or not is_instance_valid(e) or (e as Node).is_queued_for_deletion():
		return
	_launch_side = -_launch_side
	var m := Missile.new()
	m.target = e
	m.velocity = Vector3(_launch_side * 0.045, -0.02, 0.0)   # punch out sideways, then arc
	get_parent().add_child(m)
	m.global_position = global_position + Vector3(_launch_side * 0.08 * scale.x, 0.0, 0.0)
	TsgAudio.unit3_explosion()   # a beefy launch thud per rocket

func _shoot_combined() -> void:
	TsgAudio.unit3_sweep()
	var lv  := GameState.unit_level(3)
	var s   := scale.x
	var spd: float = 0.08 if lv <= 2 else (0.10 if lv <= 4 else 0.12)
	var col := Color(1.0, 0.9, 0.1, 1.0)
	match lv:
		1:
			_fire(Vector3(-0.12 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.12 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
		2, 3:
			_fire(Vector3(-0.08 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.08 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.12 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.12 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
		4, 5:
			_fire(Vector3(-0.06 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.06 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.09 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.09 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.12 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.12 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)

func _fire(offset: Vector3, vel: Vector3, col: Color) -> void:
	if get_tree().get_nodes_in_group("bullets").size() >= 54:
		return
	var b := bullet_scene.instantiate()
	b.color = col
	b.velocity = vel
	b.source_unit_id = 3
	get_parent().add_child(b)
	b.global_position = global_position + offset
