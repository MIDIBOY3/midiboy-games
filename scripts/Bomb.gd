class_name Bomb
extends Node3D

# Unit2's wide-area time bomb: drifts forward, detonates after FUSE frames,
# damaging every enemy near the bomb's altitude band within the blast radius.
# Level scales radius, damage and travel speed. Unit2 fires the next bomb
# only after this one has exploded.

const FUSE := 120  # 2s at 60fps

var level: int = 1
var bomb_alt: float = 50.0
var velocity: Vector3 = Vector3.ZERO
var t: int = 0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("bombs")
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.08)
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.7, 0.35, 0.95)
	_mat.emission_enabled = true
	_mat.emission = Color(0.8, 0.3, 1.0)
	_mat.emission_energy_multiplier = 1.5
	_mesh.material_override = _mat
	add_child(_mesh)

func _process(_delta: float) -> void:
	t += 1
	position += velocity
	velocity *= 0.985
	_mesh.rotation_degrees += Vector3(2.0, 3.0, 1.0)

	# Pulse faster and hotter as the fuse runs down.
	var fuse_t := float(t) / float(FUSE)
	var pulse := 0.5 + 0.5 * sin(t * (0.15 + fuse_t * 0.5))
	_mat.emission_energy_multiplier = 1.2 + pulse * (1.0 + fuse_t * 3.0)
	_mesh.scale = Vector3.ONE * (1.0 + fuse_t * 0.5 + pulse * 0.15)

	if t >= FUSE:
		_explode()

func _explode() -> void:
	TsgAudio.unit2_bomb_burst()
	var radius := 0.4 + 0.12 * (level - 1)
	var dmg := 1 + int(level / 2.0)

	var ex := Explosion.new()
	ex.color = Color(0.85, 0.4, 1.0)
	ex.count = 14 + level * 3
	ex.strength = 1.0 + 0.25 * level
	get_parent().add_child(ex)
	ex.global_position = global_position

	var p2 := Vector2(global_position.x, global_position.y)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var ea: Variant = e.get("alt")
		if ea == null or absf(float(ea) * GameState.ALT_MAX - bomb_alt) > 14.0:
			continue
		if p2.distance_to(Vector2(e.global_position.x, e.global_position.y)) > radius:
			continue
		var pos: Vector3 = e.global_position
		var hue: Variant = e.get("hue")
		var mh: Variant = e.get("max_hp")
		for i in dmg:
			if e.has_method("take_hit") and e.call("take_hit", 2):
				GameState.score += 100
				GameState.add_exp(40 * (int(mh) if mh != null else 1))
				GameState.on_enemy_killed()   # feeds the 慢心 gauge
				var kex := Explosion.new()
				if hue != null:
					kex.color = Color.from_hsv(float(hue) / 360.0, 0.7, 1.0)
				get_parent().add_child(kex)
				kex.global_position = pos
				break
	# Mine the surface too: the blast breaks blocks in its radius and drops resources.
	var terr := get_tree().get_first_node_in_group("planet_terrain")
	if terr != null and terr.has_method("blast"):
		for d: Dictionary in terr.call("blast", global_position, radius):
			ResourceItem.spawn(get_tree().current_scene, d)
	queue_free()
