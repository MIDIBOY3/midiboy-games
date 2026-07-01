class_name MothershipBeacon
extends Node3D

# A periodic "carrier call" signal. Instead of a carrier simply appearing on
# its own, this holographic beacon frames in from the top of the screen and
# bobs at the player's depth. Fly the ship into it to summon a carrier (which
# then frames in from above and scrolls down as usual). Left untouched, it
# drifts off the bottom and is gone — the next signal comes around later.

const LIFE := 660          # frames on screen before it gives up and leaves
const TOUCH_R := 0.30      # world radius the ship must reach to trigger it
const DRIFT := 0.0055      # slow downward drift while waiting

var _t: int = 0
var _triggered: bool = false
var _icon_mat: StandardMaterial3D
var _ring: MeshInstance3D

func _ready() -> void:
	add_to_group("mothership_beacon")
	_build()
	_place()
	get_tree().call_group("star_hud", "show_message",
		"CARRIER SIGNAL DETECTED", "FLY INTO THE BEACON TO CALL A CARRIER")

func _build() -> void:
	_icon_mat = StandardMaterial3D.new()
	_icon_mat.albedo_color = Color(0.45, 0.95, 1.0)
	_icon_mat.emission_enabled = true
	_icon_mat.emission = Color(0.4, 0.9, 1.0)
	_icon_mat.emission_energy_multiplier = 2.0
	_icon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_icon_mat.albedo_color.a = 0.9

	# Outer ring (faces the camera: torus default lies in XZ → tip up to XY).
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.17
	torus.outer_radius = 0.23
	torus.rings = 48         # smooth circle (was 6 = a hexagon — rings = segments around the ring)
	torus.ring_segments = 6  # tube cross-section
	_ring.mesh = torus
	_ring.material_override = _icon_mat
	_ring.rotation_degrees.x = 90.0
	add_child(_ring)

	# Tiny carrier silhouette inside the ring: deck slab + island tower.
	var deck := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(0.11, 0.20, 0.02)
	deck.mesh = db
	deck.material_override = _icon_mat
	add_child(deck)
	var isl := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(0.035, 0.055, 0.05)
	isl.mesh = ib
	isl.material_override = _icon_mat
	isl.position = Vector3(0.045, 0.0, 0.03)
	add_child(isl)

func _place() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pz := GameState.alt_to_z(GameState.alt)
	var sz := get_viewport().get_visible_rect().size
	var depth: float = cam.global_position.z - pz
	# Frame in from above, somewhere across the central band of the screen.
	var top := cam.project_position(Vector2(sz.x * (0.28 + randf() * 0.44), 0.0), depth)
	global_position = Vector3(top.x, top.y + 0.5, pz)

func _process(_delta: float) -> void:
	if _triggered:
		return
	if GameState.game_over:
		queue_free()
		return
	_t += 1
	global_position.y -= DRIFT
	_icon_mat.emission_energy_multiplier = 1.4 + 0.9 * sin(_t * 0.16)
	_ring.rotation_degrees.z += 1.6

	# Touch test: the ship reaching the beacon (x/y) calls the carrier.
	if not GameState.in_transition() and not GameState.on_carrier:
		var d := Vector2(GameState.px - global_position.x,
			GameState.py - global_position.y).length()
		if d < TOUCH_R:
			_trigger()
			return

	# Gave up: drifted off the bottom or waited too long.
	if _t > LIFE or global_position.y < -(3.5):
		queue_free()

func _trigger() -> void:
	_triggered = true
	var main := get_parent()
	if main != null and main.has_method("spawn_carrier"):
		main.call("spawn_carrier")
	get_tree().call_group("star_hud", "show_message",
		"CARRIER INBOUND", "BOARD ITS DECK TO REPAIR / RECOVER UNITS")
	queue_free()
