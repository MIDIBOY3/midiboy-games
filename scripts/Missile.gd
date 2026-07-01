class_name Missile
extends Node3D

# Unit3's lock-on missile (RayStorm style): launched sideways, accelerates and
# arcs hard onto its locked target, detonating with a flashy explosion.
# Deals 2 damage on impact.

const LIFETIME := 300
const HIT_RADIUS := 0.16
const DAMAGE := 5

var target: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var speed: float = 0.03
var t: int = 0

var _mesh: Node3D          # rocket body container, rotated to face travel
var _mat: StandardMaterial3D
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D

func _block(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _ready() -> void:
	# A chunky rocket built from blocks: hull + red nose + tail fins + a roaring flame.
	_mesh = Node3D.new()
	add_child(_mesh)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.85, 0.88, 0.95)
	_mat.metallic = 0.6
	_mat.roughness = 0.35
	_mat.emission_enabled = true
	_mat.emission = Color(0.7, 0.8, 1.0)
	_mat.emission_energy_multiplier = 0.6
	var nose := StandardMaterial3D.new()
	nose.albedo_color = Color(1.0, 0.3, 0.2)
	nose.emission_enabled = true
	nose.emission = Color(1.0, 0.25, 0.15)
	nose.emission_energy_multiplier = 1.4
	_block(_mesh, Vector3(0.0, 0.0, 0.0), Vector3(0.07, 0.20, 0.07), _mat)        # hull
	_block(_mesh, Vector3(0.0, 0.13, 0.0), Vector3(0.07, 0.06, 0.07), nose)       # nose cap
	_block(_mesh, Vector3(-0.055, -0.08, 0.0), Vector3(0.03, 0.07, 0.05), nose)   # fin L
	_block(_mesh, Vector3(0.055, -0.08, 0.0), Vector3(0.03, 0.07, 0.05), nose)    # fin R
	_flame = MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.05, 0.12, 0.05)
	_flame.mesh = fb
	_flame.position = Vector3(0.0, -0.16, 0.0)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_color = Color(1.0, 0.7, 0.2)
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.6, 0.15)
	_flame_mat.emission_energy_multiplier = 5.0
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame.material_override = _flame_mat
	_mesh.add_child(_flame)

func _process(_delta: float) -> void:
	t += 1
	if t > LIFETIME:
		queue_free()
		return

	speed = minf(speed + 0.0048, 0.17)

	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		var dir := target.global_position - global_position
		if dir.length_squared() > 0.000001:
			velocity = velocity.lerp(dir.normalized() * speed, 0.3).normalized() * speed
	else:
		# No enemy: lock onto the nearest surface BLOCK and home in to mine it.
		target = null
		var nb := Vector3.INF
		var pterr := get_tree().get_first_node_in_group("planet_terrain")
		if pterr != null and pterr.has_method("nearest_block_world"):
			nb = pterr.call("nearest_block_world", global_position)
		if nb.is_finite():
			var bd := nb - global_position
			if bd.length_squared() > 0.000001:
				velocity = velocity.lerp(bd.normalized() * speed, 0.25).normalized() * speed
		else:
			velocity = velocity.normalized() * speed
	position += velocity

	# Point the body along the flight direction.
	if velocity.length_squared() > 0.000001:
		_mesh.rotation.z = atan2(velocity.y, velocity.x) - PI / 2.0
	# Roaring exhaust flame.
	if _flame != null:
		var fl := 0.7 + 0.5 * sin(float(t) * 0.9) + randf() * 0.3
		_flame.scale = Vector3(1.0, fl, 1.0)
		_flame_mat.emission_energy_multiplier = 4.0 + 3.0 * fl

	if target != null and is_instance_valid(target):
		if Vector2(global_position.x, global_position.y).distance_to(
				Vector2(target.global_position.x, target.global_position.y)) < HIT_RADIUS:
			_detonate()
			return

	# Without an enemy target, the missile mines: it breaks a surface block it reaches.
	if target == null:
		var terr := get_tree().get_first_node_in_group("planet_terrain")
		if terr != null and terr.has_method("mine_at"):
			if terr.call("mine_at", global_position, DAMAGE):
				queue_free()
				return

	if position.y > 6.0 or position.y < -6.0 or absf(position.x) > 8.0:
		queue_free()

func _detonate() -> void:
	var pos: Vector3 = target.global_position
	var hue: Variant = target.get("hue")
	var mh: Variant = target.get("max_hp")
	TsgAudio.unit3_explosion()
	for i in DAMAGE:
		TsgAudio.enemy_hit()
		if target.has_method("take_hit") and target.call("take_hit", 3):
			TsgAudio.enemy_destroy()
			GameState.score += 100
			GameState.add_exp(40 * (int(mh) if mh != null else 1))
			GameState.on_enemy_killed()   # feeds the 慢心 gauge
			break

	var ex := Explosion.new()
	ex.color = Color(1.0, 0.7, 0.25) if hue == null else \
			Color.from_hsv(float(hue) / 360.0, 0.6, 1.0).lerp(Color(1.0, 0.7, 0.25), 0.5)
	ex.count = 10
	ex.strength = 1.0
	get_parent().add_child(ex)
	ex.global_position = pos
	queue_free()
