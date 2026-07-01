class_name GoldenIcon
extends Node3D

# The G icon: frames in ONCE per star system the moment the full 5-unit formation is
# assembled (spawned by Main._update_golden_offer). Fly into it to auto-transform into
# the invincible Golden robot for GameState.GOLDEN_DURATION (see activate_golden). It
# drifts down the screen, easing toward the ship's column so it's catchable; if it
# scrolls off, this system's one chance is spent.

const FALL_SPEED := 0.006
const COLLECT_RADIUS := 0.34
const LIFETIME := 1400

var t: int = 0
var _spin: Node3D
var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("golden_icon")
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.82, 0.2)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.78, 0.18)
	_mat.emission_energy_multiplier = 3.0
	# Spinning glowing gold plate.
	_spin = Node3D.new()
	add_child(_spin)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.24, 0.24, 0.05)
	plate.mesh = pm
	plate.material_override = _mat
	_spin.add_child(plate)
	# A big "G" billboarded so it always faces the player — unmistakable.
	var lbl := Label3D.new()
	lbl.text = "G"
	lbl.font_size = 130
	lbl.pixel_size = 0.0016
	lbl.modulate = Color(0.16, 0.10, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0.0, 0.0, 0.04)
	add_child(lbl)

func _process(_delta: float) -> void:
	t += 1
	if t >= LIFETIME or position.y < -2.8:
		queue_free()
		return
	position.z = GameState.alt_to_z(GameState.alt)
	position.y -= FALL_SPEED
	# Ease toward the ship's column so the reward is catchable, not a coin toss.
	position.x = lerpf(position.x, GameState.px, 0.012)
	_spin.rotation_degrees.y += 3.0
	_mat.emission_energy_multiplier = 2.2 + 1.2 * sin(t * 0.16)
	if GameState.game_over or GameState.golden_active:
		return
	if Vector2(position.x, position.y).distance_to(Vector2(GameState.px, GameState.py)) < COLLECT_RADIUS:
		_collect()

func _collect() -> void:
	GameState.activate_golden()
	TsgAudio.pickup(true)
	get_tree().call_group("star_hud", "show_message",
		"GOLDEN!", "10 SECONDS OF OVERWHELMING POWER")
	var ex := Explosion.new()
	ex.color = Color(1.0, 0.85, 0.3)
	ex.count = 22
	ex.strength = 1.9
	get_parent().add_child(ex)
	ex.global_position = global_position
	queue_free()
