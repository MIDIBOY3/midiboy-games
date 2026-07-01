extends Node3D

@onready var _nose_tip: MeshInstance3D = $body/nose_tip
@onready var _nose_mid: MeshInstance3D = $body/nose_mid
@onready var _left_wing_pivot:    Node3D = $left_wing_pivot
@onready var _right_wing_pivot:   Node3D = $right_wing_pivot
@onready var _left_wing_outer:    Node3D = $left_wing_pivot/left_wing_outer
@onready var _right_wing_outer:   Node3D = $right_wing_pivot/right_wing_outer
@onready var _left_engine_group:  Node3D = $left_engine_group
@onready var _right_engine_group: Node3D = $right_engine_group
@onready var _left_engine:  Node3D = $left_engine_group/left_engine
@onready var _right_engine: Node3D = $right_engine_group/right_engine
@onready var _left_arm:  Node3D = $left_arm
@onready var _right_arm: Node3D = $right_arm
@onready var _left_missile:  MeshInstance3D = $left_engine_group/left_missile
@onready var _right_missile: MeshInstance3D = $right_engine_group/right_missile
@onready var _body:  Node3D = $body
@onready var _left_nozzle:  MeshInstance3D = $left_engine_group/left_nozzle
@onready var _right_nozzle:  MeshInstance3D = $right_engine_group/right_nozzle

const NOSE_TIP_Y: float = 0.225
const NOSE_MID_Y: float = 0.185

var wide_mode: bool = false
var wide_t: float = 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				wide_mode = !wide_mode
				GameState.wide_shot = wide_mode
			MOUSE_BUTTON_WHEEL_UP:
				GameState.tAlt = clamp(GameState.tAlt + 0.05, 0.0, 1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				GameState.tAlt = clamp(GameState.tAlt - 0.05, 0.0, 1.0)

func _physics_process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var world_pos := camera.project_position(mouse_pos, camera.global_position.z)
	GameState.px = world_pos.x
	GameState.py = world_pos.y
	global_position = Vector3(GameState.px, GameState.py, 0.0)

	GameState.alt = lerp(GameState.alt, GameState.tAlt, 0.1)
	var s: float = lerp(2.0, 0.5, GameState.alt)
	scale = Vector3(s, s, s)

	wide_t = lerp(wide_t, 1.0 if wide_mode else 0.0, 0.08)
	
	_left_wing_pivot.rotation_degrees  = Vector3(0, 0, lerp(0.0,  90.0, wide_t))
	_right_wing_pivot.rotation_degrees = Vector3(0, 0, lerp(0.0, -90.0, wide_t))

	_left_wing_outer.position.x = lerp(-0.16, -0.12, wide_t)
	_right_wing_outer.position.x = lerp(0.16, 0.12, wide_t)

	var engine_bulge := sin(wide_t * PI) * 0.08

	_left_engine_group.position.x = lerp(-0.03, -0.18, wide_t)
	_right_engine_group.position.x = lerp(0.03, 0.18, wide_t)

	_left_engine_group.position.y = lerp(-0.08, -0.03, wide_t) - engine_bulge
	_right_engine_group.position.y = lerp(-0.08, -0.03, wide_t) - engine_bulge
	
	_left_engine.scale.x  = lerp(1.0, 1.0, wide_t)
	_right_engine.scale.x = lerp(1.0, 1.0, wide_t)
	
	_left_engine.scale.y  = lerp(3.0, 3.0, wide_t)
	_right_engine.scale.y  = lerp(3.0, 3.0, wide_t)
	
	_left_engine.position.y  = lerp(0.03, 0.03, wide_t)
	_right_engine.position.y  = lerp(0.03, 0.03, wide_t)

	_left_nozzle.position.y  = lerp(-0.07, -0.1, wide_t)
	_right_nozzle.position.y  = lerp(-0.07, -0.1, wide_t)

	_left_nozzle.scale.y  = lerp(2.0, 3.0, wide_t)
	_right_nozzle.scale.y  = lerp(2.0, 3.0, wide_t)

	# アームが胴体端からエンジングループまで正確に伸びる
	var body_edge: float = -0.04
	var engine_x: float = lerp(-0.03, -0.18, wide_t)
	var arm_len: float = abs(engine_x - body_edge)
	var arm_cx: float = (body_edge + engine_x) / 2.0
	_left_arm.position.x  = arm_cx
	_right_arm.position.x = -arm_cx
	_left_arm.position.y  = lerp(-0.05, -0.03, wide_t)
	_right_arm.position.y = lerp(-0.05, -0.03, wide_t)
	_left_arm.scale.x  = max(0.01, arm_len / 0.02)
	_right_arm.scale.x = max(0.01, arm_len / 0.02)

	_body.position.y = lerp(0.00, -0.12, wide_t)

	_nose_mid.position.y = lerp(0.19, 0.26, wide_t)

	_nose_tip.scale.y = lerp(2.0, 2.0, wide_t)

	_nose_tip.position.y = lerp(0.25, 0.22, wide_t)

	var missile_t: float = clamp((wide_t - 0.6) / 0.4, 0.0, 1.0)
	_left_missile.visible  = missile_t > 0.0
	_right_missile.visible = missile_t > 0.0
	_left_missile.scale.y  = missile_t
	_right_missile.scale.y = missile_t
	
