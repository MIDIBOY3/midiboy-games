class_name ResourceItem
extends Node3D

# Dropped by destroyed terrain blocks: a small spinning cube in the block's
# color. It scrolls down with the ground, magnets onto the player when close,
# and on pickup banks one unit of its resource type (plus a little score/EXP).

const COLLECT_RADIUS := 0.28
const MAGNET_RADIUS := 0.9
const LIFETIME := 420
const MAX_ACTIVE_COMMON := 36

var res_name: String = "ORE"
var color: Color = Color(0.6, 0.6, 0.6)
var rare: bool = false   # RARE drop: golden gem, banks toward the Golden robot

var t: int = 0
var _mat: StandardMaterial3D
var _holder: Node3D

static func spawn(parent: Node, drop: Dictionary) -> void:
	if drop.get("kind", "") == "oopart":
		var key := KeyItem.new()
		key.item_kind = "oopart"
		parent.add_child(key)
		key.global_position = drop["pos"]
		return
	var is_rare: bool = drop.get("rare", false)
	if not is_rare and parent.get_tree().get_nodes_in_group("resource_items").size() >= MAX_ACTIVE_COMMON:
		GameState.add_resource(str(drop["res"]), 1, false)
		GameState.score += 30
		GameState.add_exp(8)
		return
	var item := ResourceItem.new()
	item.res_name = str(drop["res"])
	item.color = drop["color"]
	item.rare = is_rare
	parent.add_child(item)
	item.global_position = drop["pos"]

func _ready() -> void:
	add_to_group("resource_items")
	# Rare resources read as a bright spinning gold gem, distinct from the
	# dull block-colored common cubes.
	if rare:
		color = Color(1.0, 0.82, 0.2)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 2.6 if rare else 1.2
	_holder = Node3D.new()
	add_child(_holder)
	var m := MeshInstance3D.new()
	if rare:
		var gem := SphereMesh.new()
		gem.radial_segments = 6
		gem.rings = 3
		gem.radius = 0.07
		gem.height = 0.15
		m.mesh = gem
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.07, 0.07)
		m.mesh = box
	m.material_override = _mat
	_holder.add_child(m)

func _process(_delta: float) -> void:
	t += 1
	var planet_item := GameState.stage == "planet" \
		and get_tree().get_first_node_in_group("planet_terrain") is TargetPlanet
	position.y -= PlanetTerrain.SCROLL * (0.35 if planet_item else 1.0)
	if t >= LIFETIME or position.y < -6.0:
		queue_free()
		return

	_holder.rotation_degrees += Vector3(1.3, 2.1, 0.0)
	if rare or (t & 3) == 0:
		_mat.emission_energy_multiplier = 1.0 + 0.6 * sin(t * 0.2)

	if GameState.game_over or GameState.in_transition():
		return
	# Rise toward the player's altitude plane once they come near, then magnet in.
	var pp := Vector2(GameState.px, GameState.py)
	var d := Vector2(position.x, position.y).distance_to(pp)
	var magnet_r := MAGNET_RADIUS * (11.0 if planet_item else 1.0)
	var collect_r := COLLECT_RADIUS * (4.8 if planet_item else 1.0)
	# On the star surface, drops spawn anywhere on the giant rotating sphere — far
	# out of the ship's confined play box — so a magnet radius can't catch them and
	# they expired uncollected. Planet drops ALWAYS home to the ship (no radius
	# gate), easing in over ~0.5s from wherever they spawned so every drop is
	# collectable. Space keeps the original short-range magnet.
	if planet_item or d < magnet_r:
		var pz := GameState.alt_to_z(GameState.alt)
		var pull := 0.16 if planet_item else 0.12
		position.z = lerpf(position.z, pz, 0.18 if planet_item else 0.2)
		position.x = lerpf(position.x, GameState.px, pull)
		position.y = lerpf(position.y, GameState.py, pull)
		d = Vector2(position.x, position.y).distance_to(pp)
	if d < collect_r:
		_collect()

func _collect() -> void:
	GameState.add_resource(res_name, 1, rare)
	# Mining banks navigation distance ONLY in open space — inside a star, navigation
	# is paused (boost lanes are the way to make progress there). No effect once the
	# gate is up / mid-crossing either.
	if not GameState.suppress_genesis_progression() \
			and GameState.stage == "space" and not GameState.transitioning and not GameState.gate_active:
		GameState.nav_distance = minf(GameState.NAV_LEG,
			GameState.nav_distance + (GameState.NAV_PER_RARE if rare else GameState.NAV_PER_RESOURCE))
	GameState.score += 200 if rare else 50
	GameState.add_exp(40 if rare else 15)
	TsgAudio.pickup(rare)
	var ex := Explosion.new()
	ex.color = color
	ex.count = 12 if rare else 5
	ex.strength = 0.9 if rare else 0.5
	get_parent().add_child(ex)
	ex.global_position = global_position
	# (No per-pickup RARE banner — it spammed; the Golden tier-up still announces itself.)
	queue_free()
