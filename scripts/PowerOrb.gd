class_name PowerOrb
extends Node3D

const UNIT_COLORS := {
	1: Color(0.85, 0.95, 1.0),
	2: Color(0.7, 0.35, 0.95),
	3: Color(0.95, 0.75, 0.1),
	4: Color(0.35, 0.85, 0.35),
	5: Color(1.0, 0.5, 0.1),
}
const LIFETIME := 900        # safety cap; orbs normally leave via the bottom edge
const FALL_SPEED := 0.0065   # lane descent per frame (frames in from the top)
const COLLECT_RADIUS := 0.35  # world units, altitude-agnostic (xy only)

var unit_id: int = 1
var t: int = 0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D

func _ready() -> void:
	add_to_group("power_orbs")
	var col: Color = UNIT_COLORS.get(unit_id, Color.WHITE)

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.12)
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = col
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 1.8
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = _mat
	add_child(_mesh)

	_label = Label3D.new()
	_label.text = str(unit_id)
	_label.font_size = 96
	_label.pixel_size = 0.002
	_label.outline_size = 24
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, 0, 0.1)
	add_child(_label)

func _process(_delta: float) -> void:
	t += 1
	# Descend down the lane; gone once it leaves the bottom of the screen.
	position.y -= FALL_SPEED
	if t >= LIFETIME or position.y < -2.6:
		queue_free()
		return

	# Snap to the player's altitude plane every frame: no parallax, so the orb
	# is collectable at ANY altitude exactly where it appears on screen.
	position.z = GameState.alt_to_z(GameState.alt)

	_mesh.rotation_degrees += Vector3(0.8, 1.4, 0.6)
	var pulse := 0.5 + 0.5 * sin(t * 0.1)
	_mat.emission_energy_multiplier = 1.2 + pulse * 1.2

	if GameState.game_over:
		return
	if Vector2(position.x, position.y).distance_to(Vector2(GameState.px, GameState.py)) < COLLECT_RADIUS:
		_collect()

func _collect() -> void:
	var idx := unit_id - 1
	GameState.unit_levels[idx] = mini(GameState.unit_levels[idx] + 1, 5)
	GameState.powerups_taken += 1

	# Taking a power-up lane also fully repairs every owned unit.
	for i in 5:
		if (i + 1) in GameState.collected_units:
			GameState.unit_life[i] = GameState.life_cap()

	var ex := Explosion.new()
	ex.color = UNIT_COLORS.get(unit_id, Color.WHITE)
	ex.count = 8
	ex.strength = 0.7
	get_parent().add_child(ex)
	ex.global_position = global_position

	# The choice is made — every remaining orb (including this one) disappears.
	for node in get_tree().get_nodes_in_group("power_orbs"):
		if is_instance_valid(node):
			node.queue_free()
