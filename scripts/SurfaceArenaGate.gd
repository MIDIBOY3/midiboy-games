class_name SurfaceArenaGate
extends Node3D

# The UNDERGROUND GATE. Frames in from the top of a final-route star's surface ONLY while the
# ship is at MAX durability (spawned by Main._update_arena_gate_offer). Fly into it and the view
# zooms into the portal, then the golden-walk arena takes over (relic hunt → stoneface).

const FALL_SPEED := 0.006
const TOUCH_RADIUS := 0.42
const LIFETIME := 2200
const ENTER_FRAMES := 26     # portal swells to fill the screen, then the arena swaps in

var t: int = 0
var _entering: int = -1       # >=0 while the zoom-into-gate plays out
var _spin: Node3D
var _ring_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("arena_gate")
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.55, 0.25, 0.95)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.7, 0.35, 1.0)
	_ring_mat.emission_energy_multiplier = 3.2
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.05, 0.0, 0.12)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(0.30, 0.10, 0.55)
	_core_mat.emission_energy_multiplier = 1.6
	_spin = Node3D.new()
	add_child(_spin)
	# A ring of glowing shards around a dark portal core — an unmistakable "way down".
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.30
	cm.bottom_radius = 0.30
	cm.height = 0.04
	core.mesh = cm
	core.rotation_degrees.x = 90.0
	core.material_override = _core_mat
	_spin.add_child(core)
	for i in 10:
		var a := TAU * float(i) / 10.0
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.16, 0.07)
		shard.mesh = bm
		shard.position = Vector3(cos(a) * 0.34, sin(a) * 0.34, 0.0)
		shard.rotation_degrees.z = rad_to_deg(a)
		shard.material_override = _ring_mat
		_spin.add_child(shard)
	var lbl := Label3D.new()
	lbl.text = "▼"
	lbl.font_size = 96
	lbl.pixel_size = 0.0016
	lbl.modulate = Color(0.95, 0.85, 1.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0.0, 0.0, 0.06)
	add_child(lbl)

func _process(_delta: float) -> void:
	t += 1
	_spin.rotation_degrees.z += 1.6
	_ring_mat.emission_energy_multiplier = 2.6 + 1.4 * sin(t * 0.12)
	if _entering >= 0:
		_run_enter()
		return
	if t >= LIFETIME or position.y < -2.8:
		queue_free()
		return
	position.z = GameState.alt_to_z(GameState.alt)
	position.y -= FALL_SPEED
	position.x = lerpf(position.x, GameState.px, 0.010)   # ease toward the ship's lane so it's reachable
	if GameState.game_over or GameState.in_transition() or GameState.arena_active:
		return
	if Vector2(position.x, position.y).distance_to(Vector2(GameState.px, GameState.py)) < TOUCH_RADIUS:
		_entering = 0
		GameState.entry_tint = Color(0.5, 0.2, 0.7)

# Zoom INTO the gate: the portal swells toward the camera and the entry glow whites out, then the
# golden-walk arena swaps in (GoldenWalkCtl owns the rest: relic hunt → wall → stoneface).
func _run_enter() -> void:
	_entering += 1
	var k := clampf(float(_entering) / float(ENTER_FRAMES), 0.0, 1.0)
	scale = Vector3.ONE * lerpf(1.0, 7.0, k * k)   # rush up to fill the screen
	position.z = GameState.alt_to_z(GameState.alt) + lerpf(0.0, 2.2, k)   # ...and toward the camera
	GameState.entry_glow = k
	if _entering >= ENTER_FRAMES:
		get_tree().call_group("golden_ctl", "enter_from_gate")
		queue_free()
