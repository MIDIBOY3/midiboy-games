extends Node3D

var alt_t: float    = 0.0
var cruise_t: float = 0.0
var robot_t: float  = 0.0
var bullet_scene: PackedScene = null
var _shoot_timer: int = 0
var _active_bomb: Node3D = null

func set_bullet_scene(s: PackedScene) -> void:
	bullet_scene = s

@onready var _center_conn:    MeshInstance3D = $body/center_conn
@onready var _left_body:      MeshInstance3D = $body/left_body
@onready var _right_body:     MeshInstance3D = $body/right_body
@onready var _bottom_center:  MeshInstance3D = $body/bottom_center
@onready var _left_engine:    MeshInstance3D = $left_engine
@onready var _right_engine:   MeshInstance3D = $right_engine
@onready var _left_flame:     MeshInstance3D = $left_engine/left_engine_flame
@onready var _right_flame:    MeshInstance3D = $right_engine/right_engine_flame
@onready var _rear_glow:      MeshInstance3D = $body/bottom_center/rear_glow

@onready var _left_wing_pivot:  Node3D        = $left_wing_pivot
@onready var _right_wing_pivot: Node3D        = $right_wing_pivot
@onready var _left_wing:        MeshInstance3D = $left_wing_pivot/left_wing
@onready var _right_wing:       MeshInstance3D = $right_wing_pivot/right_wing
@onready var _left_rear_fill:   MeshInstance3D = $left_wing_pivot/left_rear_fill
@onready var _right_rear_fill:  MeshInstance3D = $right_wing_pivot/right_rear_fill
@onready var _left_pod:         MeshInstance3D = $left_wing_pivot/left_pod
@onready var _right_pod:        MeshInstance3D = $right_wing_pivot/right_pod
@onready var _left_tip:         MeshInstance3D = $left_wing_pivot/left_tip
@onready var _right_tip:        MeshInstance3D = $right_wing_pivot/right_tip

func set_rig(p_alt_t: float, p_cruise_t: float) -> void:
	alt_t    = clamp(p_alt_t,    0.0, 1.0)
	cruise_t = clamp(p_cruise_t, 0.0, 1.0)

func set_robot(p_robot_t: float) -> void:
	robot_t = clamp(p_robot_t, 0.0, 1.0)

func _process(_delta: float) -> void:
	var eff_alt  := lerpf(alt_t, 0.0, robot_t)
	var low_fold := eff_alt * (1.0 - minf(1.0, cruise_t * 1.2))

	var wing_slide := cruise_t * 0.08
	var wing_in    := cruise_t * 0.06
	var rear_set   := cruise_t * 0.022

	# In robot mode: wings retract fully to pivot center, pivot moves to X=±0.04.
	# 0.24 keeps the waist-side wing parts within ±0.20 so the hip doesn't flare out.
	var robot_wing_in := robot_t * 0.24
	var eff_wing_in   := lerpf(wing_in, robot_wing_in, robot_t)
	var eff_slide     := lerpf(wing_slide, 0.0, robot_t)

	# Body Y positions (cruise shift)
	_center_conn.position.y   =  0.045 - rear_set
	_left_body.position.y     = -0.05  - rear_set
	_right_body.position.y    = -0.05  - rear_set
	_bottom_center.position.y = -0.18  - rear_set
	_left_engine.position.y   = -0.19  - rear_set
	_right_engine.position.y  = -0.19  - rear_set

	# Body halves and engines compress toward X=0 in robot mode
	_left_body.position.x    = lerpf(-0.15, -0.04, robot_t)
	_right_body.position.x   = lerpf( 0.15,  0.04, robot_t)
	_left_engine.position.x  = lerpf(-0.08, -0.03, robot_t)
	_right_engine.position.x = lerpf( 0.08,  0.03, robot_t)

	# Wing pivot rotation (fold when low alt, flat in robot mode)
	_left_wing_pivot.rotation_degrees  = Vector3(0.0, 0.0,  90.0 * low_fold)
	_right_wing_pivot.rotation_degrees = Vector3(0.0, 0.0, -90.0 * low_fold)

	# Wing pivots compress toward center in robot mode
	_left_wing_pivot.position.x  = lerpf(-0.22, -0.04, robot_t)
	_right_wing_pivot.position.x = lerpf( 0.22,  0.04, robot_t)

	# Wing children retract toward center (within pivot local frame)
	_left_wing.position       = Vector3(-0.06 + eff_wing_in,               -eff_slide,          0.0)
	_right_wing.position      = Vector3( 0.06 - eff_wing_in,               -eff_slide,          0.0)
	_left_rear_fill.position  = Vector3( 0.05 + eff_wing_in * 0.35, -0.08 - eff_slide * 0.75,  0.0)
	_right_rear_fill.position = Vector3(-0.05 - eff_wing_in * 0.35, -0.08 - eff_slide * 0.75,  0.0)
	_left_pod.position        = Vector3(-0.12 + eff_wing_in,               -eff_slide,          0.0)
	_right_pod.position       = Vector3( 0.12 - eff_wing_in,               -eff_slide,          0.0)
	_left_tip.position        = Vector3(-0.135 + eff_wing_in,    0.08 - eff_slide,              0.0)
	_right_tip.position       = Vector3( 0.135 - eff_wing_in,    0.08 - eff_slide,              0.0)

	# Robot: stow the glowing exhaust parts (crotch area of the waist) into the hull.
	var stow := maxf(0.001, 1.0 - robot_t * 1.25)
	_left_flame.scale.y     = stow
	_right_flame.scale.y    = stow
	_left_flame.position.y  = lerpf(-0.07, -0.02, robot_t)
	_right_flame.position.y = lerpf(-0.07, -0.02, robot_t)
	_rear_glow.scale.y      = stow
	_rear_glow.position.y   = lerpf(-0.062, -0.03, robot_t)
	_handle_shoot()

func _handle_shoot() -> void:
	if bullet_scene == null or robot_t > 0.5 or GameState.carrier_battle or GameState.ending_cinematic \
			or GameState.boss_intro_active or GameState.god_phase > 0:
		return
	var lv := GameState.unit_level(2)
	_shoot_timer += 1
	if GameState.sep_t > 0.5:
		# Carpet bombing: a steady cadence of bombs (faster with level), not one-at-a-time.
		var bi: int = 64 - lv * 8   # lv1≈56f … lv5≈24f between bombs
		if _shoot_timer < bi:
			return
		_shoot_timer = 0
		_shoot_formation()
	else:
		var interval: int = 8 if lv <= 2 else (6 if lv <= 4 else 4)
		if _shoot_timer < interval:
			return
		_shoot_timer = 0
		_shoot_combined()

# Formation: CARPET BOMBING — continuously lob wide-area bombs forward (no marking, no
# wait-for-explosion). They blanket the ground in craters (mining) and hit enemy groups.
# A live-count cap keeps the screen from flooding with blasts.
func _shoot_formation() -> void:
	if get_tree().get_nodes_in_group("bombs").size() >= 5:
		return
	TsgAudio.unit2_bomb_launch()
	var lv := GameState.unit_level(2)
	var b := Bomb.new()
	b.level = lv
	b.bomb_alt = GameState.alt
	# Lobbed forward with a little spread so successive bombs spread the carpet.
	b.velocity = Vector3(randf_range(-0.012, 0.012), 0.022 + 0.003 * lv, 0.0)
	get_parent().add_child(b)
	b.global_position = global_position + Vector3(randf_range(-0.15, 0.15), 0.0, 0.0)

func _shoot_combined() -> void:
	TsgAudio.unit_fire(2)
	var lv := GameState.unit_level(2)
	var s   := scale.x
	var spd: float = 0.08 if lv <= 2 else (0.10 if lv <= 4 else 0.12)
	var col := Color(1.0, 0.5, 0.1, 1.0)
	match lv:
		1:
			_fire(Vector3(-0.28 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.28 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
		2, 3:
			_fire(Vector3(-0.22 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.22 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.28 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.28 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
		4, 5:
			_fire(Vector3(-0.18 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.18 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.23 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.23 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3(-0.28 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)
			_fire(Vector3( 0.28 * s, 0.1 * s, 0.0), Vector3(0.0, spd, 0.0), col)


func _fire(offset: Vector3, vel: Vector3, col: Color) -> void:
	if get_tree().get_nodes_in_group("bullets").size() >= 54:
		return
	var b := bullet_scene.instantiate()
	b.color = col
	b.velocity = vel
	b.source_unit_id = 2
	get_parent().add_child(b)
	b.global_position = global_position + offset
