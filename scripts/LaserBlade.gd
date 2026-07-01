class_name LaserBlade
extends Node3D

# Unit4's launched laser blade: a long lance that detaches at full length. Its
# ORIENTATION (dir) is fixed — the blade stays a vertical bar — while it DRIFTS
# along a separate move_dir. Unit4 fires one MAIN blade drifting straight up plus
# SUB blades that keep the same vertical shape but slide sideways / diagonally,
# so the volley sweeps across-screen instead of shooting off the top edge.

const TICK_INTERVAL := 4

var dir: Vector3 = Vector3(0, 1, 0)       # blade orientation (kept vertical)
var move_dir: Vector3 = Vector3(0, 0, 0)  # travel direction (defaults to dir)
var speed: float = 0.12
var blade_len: float = 1.0   # world units
var width: float = 0.07      # world units (hit half-width)
var vis_scale: float = 1.0   # visual thickness scale

var _tick: int = 0
var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("player_projectiles")
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 1.0, 0.03)
	m.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 1.0, 0.55, 0.9)
	_mat.emission_enabled = true
	_mat.emission = Color(0.5, 1.0, 0.5)
	_mat.emission_energy_multiplier = 3.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = _mat
	m.scale = Vector3(vis_scale, blade_len, vis_scale)
	add_child(m)
	# Orient by dir only (vertical for Unit4's blades) — never by travel direction.
	rotation.z = atan2(dir.y, dir.x) - PI / 2.0
	if move_dir.length_squared() < 0.000001:
		move_dir = dir
	move_dir = move_dir.normalized()

func _process(_delta: float) -> void:
	position += move_dir * speed
	if position.y > 6.5 or position.y < -6.5 or absf(position.x) > 8.0:
		queue_free()
		return

	# Hit enemies EVERY frame so a fast-drifting blade can't tunnel past them.
	_hit_enemies()

	# Terrain carving stays throttled (rebuilds are expensive).
	_tick += 1
	if _tick < TICK_INTERVAL:
		return
	_tick = 0
	var lterr := get_tree().get_first_node_in_group("planet_terrain")
	if lterr != null and lterr.has_method("mine_at"):
		var ld := Vector3(dir.x, dir.y, 0.0).normalized()
		for s in 5:
			var off := (float(s) / 4.0 - 0.5) * blade_len
			lterr.call("mine_at", global_position + ld * off, 3)

# Damage every same-band enemy lying along the blade's full length (±half) and
# within its hit half-width. Widen the band a little so grazing hits still count.
func _hit_enemies() -> void:
	var d2 := Vector2(dir.x, dir.y)
	if d2.length_squared() < 0.000001:
		return
	d2 = d2.normalized()
	var half := blade_len * 0.5
	# Cover the distance travelled since the last check so nothing slips between frames.
	var hw := width + Vector2(move_dir.x, move_dir.y).length() * speed * 0.5
	var c2 := Vector2(global_position.x, global_position.y)
	for e: Node3D in GameState.marked_enemies():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var rel := Vector2(e.global_position.x, e.global_position.y) - c2
		var along := rel.dot(d2)
		if absf(along) > half:
			continue
		if absf(rel.cross(d2)) > hw:
			continue
		var pos: Vector3 = e.global_position
		var hue: Variant = e.get("hue")
		var mh: Variant = e.get("max_hp")
		if e.has_method("take_hit") and e.call("take_hit", 4):
			GameState.score += 100
			GameState.add_exp(40 * (int(mh) if mh != null else 1))
			GameState.on_enemy_killed()   # feeds the 慢心 gauge
			var ex := Explosion.new()
			if hue != null:
				ex.color = Color.from_hsv(float(hue) / 360.0, 0.7, 1.0)
			get_parent().add_child(ex)
			ex.global_position = pos
