class_name RepairItem
extends Node3D

# Dropped occasionally by dying enemies. Collecting it heals EVERY owned unit
# by the same amount. Snaps to the player's altitude plane every frame (no
# parallax — collectable exactly where it appears, at any altitude).

const HEAL := 25.0
const FALL_SPEED := 0.004
const COLLECT_RADIUS := 0.3
const LIFETIME := 600

var t: int = 0
var _mat: StandardMaterial3D
var _holder: Node3D

# Arena loot mode: instead of snapping to the player's plane, the item rains down
# through ALTITUDE from high up and pools at the cave floor, collected there.
var arena_fall: bool = false
var fall_alt: float = 0.0
const ARENA_FALL_SPEED := 1.6
const ARENA_REST_LIFE := 2400

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 1.0, 0.55)
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 1.0, 0.5)
	_mat.emission_energy_multiplier = 1.8
	_holder = Node3D.new()
	add_child(_holder)
	var h := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.1, 0.034, 0.034)
	h.mesh = hb
	h.material_override = _mat
	_holder.add_child(h)
	var v := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.034, 0.1, 0.0355)
	v.mesh = vb
	v.material_override = _mat
	_holder.add_child(v)

func _process(_delta: float) -> void:
	t += 1
	if arena_fall:
		# Rain down through altitude and pool at the cave floor, then ride the terrain
		# flow (scroll) like any ground item until it drifts off-screen.
		fall_alt = maxf(GameState.ARENA_FLOOR_ALT, fall_alt - ARENA_FALL_SPEED)
		position.z = GameState.alt_to_z(fall_alt)
		position.y -= PlanetTerrain.SCROLL
		_holder.rotation_degrees.y += 2.0
		_mat.emission_energy_multiplier = 1.4 + 0.8 * sin(t * 0.15)
		if t >= ARENA_REST_LIFE or position.y < -6.0:
			queue_free()
			return
		if GameState.game_over:
			return
		# Collect only when the ship is at this item's depth AND near it in x/y.
		if absf(GameState.alt - fall_alt) < 35.0 \
				and Vector2(position.x, position.y).distance_to(Vector2(GameState.px, GameState.py)) < COLLECT_RADIUS:
			_collect()
		return

	position.y -= FALL_SPEED
	if t >= LIFETIME or position.y < -2.6:
		queue_free()
		return

	position.z = GameState.alt_to_z(GameState.alt)
	_holder.rotation_degrees.y += 2.0
	_mat.emission_energy_multiplier = 1.4 + 0.8 * sin(t * 0.15)

	if GameState.game_over:
		return
	if Vector2(position.x, position.y).distance_to(Vector2(GameState.px, GameState.py)) < COLLECT_RADIUS:
		_collect()

func _collect() -> void:
	for i in 5:
		if (i + 1) in GameState.collected_units:
			GameState.unit_life[i] = minf(GameState.life_cap(), GameState.unit_life[i] + HEAL)
	var ex := Explosion.new()
	ex.color = Color(0.4, 1.0, 0.6)
	ex.count = 6
	ex.strength = 0.6
	get_parent().add_child(ex)
	ex.global_position = global_position
	queue_free()
