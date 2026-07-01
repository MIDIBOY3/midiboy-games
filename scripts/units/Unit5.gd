extends Node3D

var alt_t: float    = 0.0
var cruise_t: float = 0.0
var robot_t: float  = 0.0
var bullet_scene: PackedScene = null
var _shoot_timer: int = 6  # offset so units don't all fire on the same frame
var _spin_ang: float = 0.0
var _kick_s: float = 0.0   # smoothed kick envelope (avoids a 1-frame pose pop)

func set_bullet_scene(s: PackedScene) -> void:
	bullet_scene = s

@onready var _left_half:    Node3D = $left_half
@onready var _right_half:   Node3D = $right_half
@onready var _left_ck_top:    MeshInstance3D = $left_half/left_ck_top
@onready var _right_ck_top:   MeshInstance3D = $right_half/right_ck_top
@onready var _left_ck_upper:  MeshInstance3D = $left_half/left_ck_upper
@onready var _right_ck_upper: MeshInstance3D = $right_half/right_ck_upper
@onready var _left_ck_body:   MeshInstance3D = $left_half/left_ck_body
@onready var _right_ck_body:  MeshInstance3D = $right_half/right_ck_body
@onready var _left_nozzle:  MeshInstance3D = $left_half/left_nozzle
@onready var _right_nozzle: MeshInstance3D = $right_half/right_nozzle
@onready var _left_body_upper:  MeshInstance3D = $left_half/left_body_upper
@onready var _right_body_upper: MeshInstance3D = $right_half/right_body_upper

# F5 walk: the lower leg/foot (body_upper + ck*) below this half-local Y bends at a knee.
const KNEE_Y := -0.12
const KNEE_DEG := 34.0

func set_rig(p_alt_t: float, p_cruise_t: float) -> void:
	alt_t    = clamp(p_alt_t,    0.0, 1.0)
	cruise_t = clamp(p_cruise_t, 0.0, 1.0)

func set_robot(p_robot_t: float) -> void:
	robot_t = clamp(p_robot_t, 0.0, 1.0)

func _process(_delta: float) -> void:
	# Use the authoritative transform progress so the leg deformations always
	# match FormationManager's positioning (set_robot could lag/desync after a
	# formation toggle). The 180°X flip itself (cockpit tip → toe, nozzle → thigh
	# root) is owned by FormationManager, applied together with the body lean.
	robot_t = GameState.robot_t

	var eff_alt   := lerpf(alt_t, 0.0, robot_t)
	var in_slide  := eff_alt * 0.06
	var low_up    := eff_alt * 0.34

	var leg_spread := robot_t * 0.05

	var half_y_scale := lerpf(1.0, 1.5, robot_t)
	# (half scale is applied together with rotation as one basis at the end —
	# setting .scale and .rotation_degrees separately on this non-uniformly-scaled
	# node makes Godot flip between two basis decompositions every frame.)

	# Retract entire blue cockpit section (toe) in robot mode — all three parts shift together.
	var ck_retract: float     = lerpf(0.0, -0.08, robot_t)   # ck_upper + ck_body 共通収納量
	var ck_top_retract: float = lerpf(0.0, -0.08, robot_t)   # ck_top 個別収納量
	# (ck_* + body_upper are placed below via _place_shin so the knee can bend them.)

	# Extend nozzle (bright orange thigh root) downward for a longer thigh appearance.
	var nozzle_y: float = lerpf(-0.30, -0.36, robot_t)
	_left_nozzle.position.y  = nozzle_y
	_right_nozzle.position.y = nozzle_y
	var nozzle_extra: float = lerpf(1.0, 2.0, robot_t)
	_left_nozzle.scale.y  = nozzle_extra
	_right_nozzle.scale.y = nozzle_extra

	# Leg pendulum inertia: hip joint (nozzle/thigh-root) stays fixed while toe swings.
	# Rotation is applied in Unit5's local frame; the hip X correction keeps it from drifting.
	# Math: rotating the half by θ around its own pivot (at center, not at hip) shifts the
	# hip by hip_arm*sin(θ) in Unit5 local X — we subtract that to keep the hip stationary.
	var vx_c: float          = clampf(GameState.vx, -0.03, 0.03)
	var leg_swing_deg: float = 0.0 if GameState.robot_static else vx_c * robot_t * 60.0
	var hip_arm: float       = -nozzle_y * half_y_scale  # nozzle-to-half-center distance in Unit5 local

	# Toe spread: rotate each half outward around the hip joint.
	# Negative angle on left = toe points left (outward); positive on right = toe points right.
	var toe_spread_deg: float = robot_t * -9.0  # ← ここで開き具合を調整
	# Humanoid attack motion: the kicking leg swings out; a gentle idle weight
	# shift breathes the stance otherwise. The raw envelope from Unit1 snaps to 1
	# instantly, which (amplified by the hip-correction below) popped the leg a
	# big distance in a single frame — read a SMOOTHED value so the kick eases in.
	_kick_s = move_toward(_kick_s, GameState.robot_kick * robot_t, 0.18)
	var rk := _kick_s
	var l_kick := 0.0 if GameState.robot_static else (rk * 34.0 if GameState.robot_kick_side < 0 else 0.0)
	var r_kick := 0.0 if GameState.robot_static else (rk * -34.0 if GameState.robot_kick_side > 0 else 0.0)
	# Golden robot motion reverted (GameState.robot_static): leg_swing/kick are 0,
	# so the legs hold a fixed open pose (left +9° / right −9°). An anti-phase idle
	# sway also used to live here and was removed.
	var left_rot_deg:  float  = leg_swing_deg - toe_spread_deg + l_kick
	var right_rot_deg: float  = leg_swing_deg + toe_spread_deg + r_kick

	# F5 walk: fore/aft (X) thigh stride at the HIP, anti-phase L/R, + a knee bend on the
	# forward leg so the foot lifts (a real step). Gated behind golden_walk (normal Golden
	# static), faded by gait amplitude (idle → still) and robot_t.
	var l_step := 0.0   # thigh fore/aft swing (degrees)
	var r_step := 0.0
	var l_knee := 0.0   # lower-leg bend (radians)
	var r_knee := 0.0
	if GameState.golden_walk:
		var g: float   = GameState.golden_gait
		var amp: float = GameState.golden_gait_amp * robot_t
		l_step =  sin(g) * 26.0 * amp
		r_step = -sin(g) * 26.0 * amp
		l_knee = maxf(0.0, sin(g))      * deg_to_rad(KNEE_DEG) * amp
		r_knee = maxf(0.0, sin(g + PI)) * deg_to_rad(KNEE_DEG) * amp

	# Build each half's transform in ONE assignment: basis = rotX · rotZ · scaleY, plus the
	# origin. Setting .scale and .rotation_degrees SEPARATELY on this non-uniformly
	# scaled (y=1.5) node made Godot decompose/recompose a sheared basis every frame
	# and flip between two equivalent solutions → the leg snapped between 2 shapes
	# ("同じ脚が2角度で振動 / 2つの形状が繰り返される"). Assigning the basis directly
	# avoids the decomposition entirely.
	var scale_v := Vector3(1.0, half_y_scale, 1.0)
	# PIVOT THE THIGH ABOUT THE HIP (so the leg root stays pinned to the waist, not flung off):
	# the hip sits hip_arm above the half origin. The -hip_arm·sin(rotZ) term pins it under the
	# Z splay; the l_phi terms below pin it under the fore/aft (X) swing — y goes DOWN by
	# hip_arm·cos(rotZ)·(1-cosφ) and z forward by hip_arm·cos(rotZ)·sinφ (earlier these had the
	# wrong sign, which detached the leg from the hip).
	var l_phi := deg_to_rad(l_step)
	var r_phi := deg_to_rad(r_step)
	var l_cz := hip_arm * cos(deg_to_rad(left_rot_deg))
	var r_cz := hip_arm * cos(deg_to_rad(right_rot_deg))
	# Tiny opposite z offsets so the two legs never share an exact depth plane at the crotch.
	var l_pos := Vector3(
		lerpf(-in_slide, -leg_spread, robot_t) - hip_arm * sin(deg_to_rad(left_rot_deg)),
		low_up - l_cz * (1.0 - cos(l_phi)),
		0.006 * robot_t + l_cz * sin(l_phi))
	var r_pos := Vector3(
		lerpf( in_slide,  leg_spread, robot_t) - hip_arm * sin(deg_to_rad(right_rot_deg)),
		low_up - r_cz * (1.0 - cos(r_phi)),
		-0.006 * robot_t + r_cz * sin(r_phi))
	_left_half.transform  = Transform3D(Basis.from_euler(Vector3(l_phi, 0.0, deg_to_rad(left_rot_deg))).scaled_local(scale_v),  l_pos)
	_right_half.transform = Transform3D(Basis.from_euler(Vector3(r_phi, 0.0, deg_to_rad(right_rot_deg))).scaled_local(scale_v), r_pos)

	# Lower leg + foot bend at the knee (each part swung about KNEE_Y in ONE Transform → no
	# basis thrash). At knee=0 this exactly reproduces the rest pose → normal Golden untouched.
	_place_shin(_left_ck_top,     -0.1,   0.065 + ck_retract + ck_top_retract, l_knee)
	_place_shin(_left_ck_upper,   -0.1,   0.035 + ck_retract,                  l_knee)
	_place_shin(_left_ck_body,    -0.1,  -0.01  + ck_retract,                  l_knee)
	_place_shin(_left_body_upper, -0.09, -0.09,                                l_knee)
	_place_shin(_right_ck_top,     0.1,   0.065 + ck_retract + ck_top_retract, r_knee)
	_place_shin(_right_ck_upper,   0.1,   0.035 + ck_retract,                  r_knee)
	_place_shin(_right_ck_body,    0.1,  -0.01  + ck_retract,                  r_knee)
	_place_shin(_right_body_upper, 0.09, -0.09,                                r_knee)

	_handle_shoot()

# Place one lower-leg/foot mesh, rotated about the knee line (KNEE_Y) by `theta` (X axis).
# theta=0 → identity (exact rest pose; the normal Golden is unaffected).
func _place_shin(node: Node3D, px: float, py: float, theta: float) -> void:
	var oy := py - KNEE_Y
	node.transform = Transform3D(Basis.from_euler(Vector3(theta, 0.0, 0.0)),
		Vector3(px, KNEE_Y + oy * cos(theta), oy * sin(theta)))

func _handle_shoot() -> void:
	if bullet_scene == null or robot_t > 0.5 or GameState.carrier_battle or GameState.ending_cinematic \
			or GameState.boss_intro_active or GameState.god_phase > 0:
		return
	var lv := GameState.unit_level(5)
	var interval: int
	if GameState.sep_t > 0.5:
		interval = 9 - lv  # pinwheel fire rate: 8f → 4f with level
	else:
		interval = 8 if lv <= 2 else (6 if lv <= 4 else 4)
	_shoot_timer += 1
	if _shoot_timer < interval:
		return
	_shoot_timer = 0
	if GameState.sep_t > 0.5:
		_shoot_formation()
	else:
		_shoot_combined()

# Formation: HOMING SWARM — fan out small homing missiles that lock onto the nearest
# enemy, or (no enemy) onto the nearest surface block to mine it. No wasted shots.
# Level adds missiles per volley; a live-count cap keeps the swarm sane.
func _shoot_formation() -> void:
	if get_tree().get_nodes_in_group("swarm").size() >= 14:
		return
	TsgAudio.unit5_barrage()
	var lv := GameState.unit_level(5)
	var n := 1 + int((lv - 1) / 2.0)        # 1 → 2 → 3 per volley
	var enemies := GameState.marked_enemies()
	var tgt := _nearest_enemy(enemies)
	_spin_ang += 0.7
	for i in n:
		var m := Missile.new()
		m.add_to_group("swarm")
		m.speed = 0.04
		m.target = tgt
		var a := _spin_ang + TAU * float(i) / float(n)
		m.velocity = Vector3(cos(a), sin(a), 0.0) * 0.05   # initial fan-out
		get_parent().add_child(m)
		m.global_position = global_position
		m.scale = Vector3.ONE * 0.8

func _nearest_enemy(candidates: Array) -> Node3D:
	var best: Node3D = null
	var best_d := 9.0
	var p2 := Vector2(global_position.x, global_position.y)
	for e: Node3D in candidates:
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var d := p2.distance_to(Vector2(e.global_position.x, e.global_position.y))
		if d < best_d:
			best_d = d
			best = e
	return best

func _shoot_combined() -> void:
	TsgAudio.unit_fire(5)
	var lv  := GameState.unit_level(5)
	var s   := scale.x
	var spd: float = 0.08 if lv <= 2 else (0.10 if lv <= 4 else 0.12)
	var col := Color(0.2, 0.6, 1.0, 1.0)
	match lv:
		1:
			_fire(Vector3(-0.20 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.20 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
		2, 3:
			_fire(Vector3(-0.16 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.16 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.20 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.20 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
		4, 5:
			_fire(Vector3(-0.14 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.14 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.17 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.17 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.20 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.20 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)

func _fire(offset: Vector3, vel: Vector3, col: Color) -> void:
	if get_tree().get_nodes_in_group("bullets").size() >= 54:
		return
	var b := bullet_scene.instantiate()
	b.color = col
	b.velocity = vel
	b.source_unit_id = 5
	get_parent().add_child(b)
	b.global_position = global_position + offset
