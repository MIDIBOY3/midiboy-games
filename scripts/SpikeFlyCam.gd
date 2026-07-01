extends Camera3D

# THROWAWAY free-fly camera for the Terrain3D verification spike. Delete this
# (and the spike scene) once we decide whether to adopt Terrain3D.
#   WASD = move, Q/E = down/up, hold RIGHT MOUSE = look, SHIFT = boost.
# Press F1 to print the current FPS to the Output panel.

@export var speed: float = 30.0

var _yaw: float = 0.0
var _pitch: float = 0.0

func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.45, 1.45)
		rotation = Vector3(_pitch, _yaw, 0.0)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		print("[SPIKE] FPS=%d" % Engine.get_frames_per_second())

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += transform.basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var boost := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		global_position += dir.normalized() * speed * boost * delta
