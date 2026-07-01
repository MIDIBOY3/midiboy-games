extends Node3D

var velocity: Vector3 = Vector3(0, 0.08, 0)
var color: Color = Color(0.666667, 0.933333, 1, 1)
var hits_lower_alt: bool = false
var breaks_terrain: bool = false  # GERWALK shot: detonate voxel blocks on contact
var homing: bool = false        # curve onto same-altitude ("marked") enemies
var homing_lower: bool = false  # Unit4: precise homing onto lower-layer enemies
var damage: int = 1
var source_unit_id: int = 1
var base_scale: float = 0.5     # visual size multiplier (Unit1 fires slightly smaller)
var _terrain_pen_cd: int = 0    # frames between craters while a GERWALK bolt plows through breakable terrain
var _pen_origin: Vector3 = Vector3.ZERO   # GERWALK bolt's spawn position, for a travel-distance lifespan
var _pen_origin_set: bool = false
const PEN_RANGE := 11.0         # how far a terrain-busting bolt travels before expiring
const SEALED_REACH := 1.8       # only bolts fired within this of the sealed wall chip it (point-blank)

const HOMING_RADIUS := 0.6
const TURN_RATE := 0.22
const HOMING_RADIUS_LOWER := 1.2
const TURN_RATE_LOWER := 0.35

@onready var _mesh: MeshInstance3D = $MeshInstance3D

# Bullets only use a handful of colors — share one material per color
# instead of allocating a new one per shot.
static var _mat_cache: Dictionary = {}
static var _trail_mat_cache: Dictionary = {}

var _trail: MeshInstance3D
var _planet_curve_ready := false
var _planet_start_y := 0.0
var _planet_start_z := 0.0
var _planet_arc_dist := 0.0
var _planet_lon := 0.0
var _planet_lat0 := -0.34
var _planet_start_global := Vector3.ZERO  # muzzle world pos: arc eases off it onto the sphere

func _ready() -> void:
	add_to_group("bullets")
	add_to_group("player_projectiles")
	var key := color.to_rgba32()
	var mat: StandardMaterial3D = _mat_cache.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.4
		_mat_cache[key] = mat
	_mesh.set_surface_override_material(0, mat)
	scale = Vector3.ONE * base_scale
	_make_trail(key)
	if breaks_terrain:
		# Point the bolt along its travel so a sideways/diagonal shot isn't a vertical sliver.
		rotation.z = atan2(-velocity.x, velocity.y)

func _process(_delta: float) -> void:
	if homing and (GameState.frame & 1) == 0:
		_steer(GameState.marked_enemies(), HOMING_RADIUS, TURN_RATE)
	elif homing_lower and (GameState.frame & 1) == 0:
		_steer(GameState.lower_enemies(), HOMING_RADIUS_LOWER, TURN_RATE_LOWER)
	position += velocity
	if breaks_terrain:
		if _terrain_pen_cd > 0:
			_terrain_pen_cd -= 1
		var terr := get_tree().get_first_node_in_group("planet_terrain")
		if terr != null and terr.has_method("collides") \
				and terr.collides(global_position.x, global_position.y, global_position.z, 0.06):
			# Arena flank walls are a hard barrier: the bolt stops dead (blast spares them).
			# Everything else — the central block field and its decor — is breakable, so the
			# bolt craters a channel and KEEPS FLYING across the arena instead of dying on the
			# first dune or spire it grazes.
			if terr.has_method("is_arena_wall") and terr.is_arena_wall(global_position.x):
				var wex := Explosion.new()
				wex.color = color
				wex.count = 12
				wex.strength = 1.3
				get_tree().current_scene.add_child(wex)
				wex.global_position = global_position
				TsgAudio.arena_block_break()
				queue_free()
				return
			elif terr.has_method("is_sealed_wall_at") \
					and terr.is_sealed_wall_at(global_position.x, global_position.y):
				# Sealed relic gate: the bolt STOPS here (no tunnelling), so the wall can't be
				# pre-drilled from across the arena. It only chips when fired point-blank — the
				# GERWALK has to press up against it and grind a passage over time.
				var reached := _pen_origin_set and position.distance_to(_pen_origin) < SEALED_REACH
				if reached and terr.has_method("blast"):
					terr.blast(global_position, 0.20)   # a small bite out of the barrier face
				var sex := Explosion.new()
				sex.color = color
				sex.count = 8
				sex.strength = 1.0
				get_tree().current_scene.add_child(sex)
				sex.global_position = global_position
				TsgAudio.arena_block_break()
				queue_free()
				return
			elif terr.has_method("blast") and _terrain_pen_cd <= 0:
				# Crater a chunk of the breakable field and KEEP FLYING. The cooldown keeps
				# craters ~0.64u apart < the 0.68 radius, so they overlap into one clean
				# tunnel while sparing the terrain a fresh rebuild every single frame.
				_terrain_pen_cd = 4
				var drops: Array = terr.blast(global_position, 0.68)
				TsgAudio.arena_block_break()
				for drop: Dictionary in drops:
					ResourceItem.spawn(get_tree().current_scene, drop)
				var ex := Explosion.new()
				ex.color = color
				ex.count = 22
				ex.strength = 1.7
				get_tree().current_scene.add_child(ex)
				ex.global_position = global_position
	if breaks_terrain:
		# The GERWALK arena scrolls nothing — the player walks out into world space, so the
		# absolute ±6 bound below would kill bolts fired anywhere past y=6. Bound these by
		# travel distance from their muzzle instead, so they reach the same range everywhere.
		if not _pen_origin_set:
			_pen_origin_set = true
			_pen_origin = position
		if position.distance_to(_pen_origin) > PEN_RANGE:
			queue_free()
		return
	# Cull off-screen relative to the CAMERA — the world scrolls (ZAKO design), so an absolute
	# ±6 test would kill HERO shots the moment the HERO advances past world-y 6.
	var rel_y := position.y - GameState.cam_y
	if rel_y > 6.0 or rel_y < -6.0 or abs(position.x) > 8.0:
		queue_free()

func _make_trail(key: int) -> void:
	_trail = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.034, 0.20, 0.018)
	_trail.mesh = mesh
	_trail.position = Vector3(0.0, -0.075, 0.0)
	_trail.scale = Vector3(0.75, 1.0, 0.75)
	var mat: StandardMaterial3D = _trail_mat_cache.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, 0.38)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.7
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat_cache[key] = mat
	_trail.material_override = mat
	add_child(_trail)

func _planet_gravity_pull(planet: TargetPlanet) -> float:
	if planet == null or not is_instance_valid(planet) or planet.is_queued_for_deletion():
		return 0.0
	if GameState.stage == "planet":
		return 1.0
	return clampf((GameState.ALT_MAX - GameState.alt) \
		/ (GameState.ALT_MAX - GameState.GROUND_ALT), 0.0, 1.0)

func _init_planet_arc(planet: TargetPlanet = null, camera: Camera3D = null) -> void:
	_planet_curve_ready = true
	_planet_start_y = position.y
	_planet_start_z = position.z
	_planet_start_global = global_position
	_planet_arc_dist = 0.0
	# Fallback (legacy fixed band) if there's no live camera/planet to solve against.
	_planet_lon = clampf(position.x / 2.8, -1.0, 1.0) * 0.42
	_planet_lat0 = -0.34
	if planet == null or camera == null \
			or not is_instance_valid(planet) or planet.is_queued_for_deletion():
		return
	# Ship + muzzle live in the near play-plane; surface enemies/terrain live on the
	# far giant sphere. Pick the sphere lon/lat whose SCREEN position matches the muzzle
	# so bullets visibly leave the ship — instead of a fixed band tuned to one camera.
	var res := _solve_sphere_lonlat(planet, camera,
		camera.unproject_position(global_position))
	_planet_lon = clampf(res.x, -0.72, 0.72)
	# At low altitude the camera looks along the surface, so the muzzle can sit BELOW
	# the lowest sphere latitude the view can show: the solve then clamps and the entry
	# point lands above the ship. We allow a lower band here AND ease off the real muzzle
	# world position in _advance_planet_arc, so the shot always starts on the ship.
	_planet_lat0 = clampf(res.y, -0.9, 0.5)

func _sphere_screen(planet: TargetPlanet, camera: Camera3D, lon: float, lat: float) -> Vector2:
	var n := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()
	var local := n * (TargetPlanet.SURFACE_RADIUS + 0.038)
	return camera.unproject_position(planet.global_transform * local)

# Coordinate descent: screen-Y is monotonic in lat, screen-X in lon over the small
# visible band. A few bisection passes nail the muzzle to within a pixel or two.
func _solve_sphere_lonlat(planet: TargetPlanet, camera: Camera3D, target: Vector2) -> Vector2:
	var lon := clampf(position.x / 2.8, -1.0, 1.0) * 0.42
	var lat := -0.2
	for _outer in 3:
		lat = _bisect_axis(planet, camera, lon, target.y, true, -0.7, 0.74)
		lon = _bisect_axis(planet, camera, lat, target.x, false, -0.9, 0.9)
	return Vector2(lon, lat)

func _bisect_axis(planet: TargetPlanet, camera: Camera3D, fixed: float,
		target: float, solve_lat: bool, lo: float, hi: float) -> float:
	var sample := func(v: float) -> float:
		var sp := _sphere_screen(planet, camera, fixed, v) if solve_lat \
			else _sphere_screen(planet, camera, v, fixed)
		return sp.y if solve_lat else sp.x
	var flo: float = sample.call(lo)
	if is_equal_approx(flo, sample.call(hi)):
		return (lo + hi) * 0.5
	for _i in 16:
		var mid := (lo + hi) * 0.5
		var fm: float = sample.call(mid)
		if (fm < target) == (flo < target):
			lo = mid
			flo = fm
		else:
			hi = mid
	return (lo + hi) * 0.5

func _apply_planet_gravity(pull: float = 1.0) -> void:
	var spd := velocity.length()
	if spd <= 0.0001:
		return
	# On a spherical planet, shots should skim the curvature instead of drawing a
	# flat vertical line. Pull the trail gently toward the centreline and flatten
	# forward speed as it travels toward the horizon.
	var travel_t := clampf((position.y - _planet_start_y) / 11.5, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, -position.x * 0.010, (0.035 + travel_t * 0.018) * pull)
	velocity.y = lerpf(velocity.y, maxf(0.058, velocity.y * 0.970), 0.030 * pull)
	velocity.z = lerpf(velocity.z, 0.0, (0.10 + travel_t * 0.06) * pull)
	velocity = velocity.normalized() * spd

func _advance_planet_arc(planet: TargetPlanet) -> void:
	if planet == null or not is_instance_valid(planet) or planet.is_queued_for_deletion():
		position += velocity
		return
	var spd := maxf(0.058, velocity.length())
	_planet_arc_dist += spd * 1.15
	_planet_lon += velocity.x * 0.035
	_planet_lon = clampf(_planet_lon, -0.72, 0.72)
	var travel_t := clampf(_planet_arc_dist / 5.8, 0.0, 1.0)
	var lat := lerpf(_planet_lat0, 0.74, smoothstep(0.0, 1.0, travel_t))
	var n := Vector3(sin(_planet_lon) * cos(lat), sin(lat), cos(_planet_lon) * cos(lat)).normalized()
	var local := n * (TargetPlanet.SURFACE_RADIUS + 0.038)
	var sphere_pos := planet.global_transform * local
	# Ease from the muzzle (near play-plane) onto the far sphere over the first stretch
	# of flight. The solved entry already matches the muzzle at mid/high altitude, so
	# this is a no-op there; at low altitude it closes the gap that the latitude clamp
	# would otherwise leave between the ship and the first visible bullet.
	var onset := smoothstep(0.0, 0.30, travel_t)
	global_position = _planet_start_global.lerp(sphere_pos, onset)
	var right := Vector3.UP.cross(n)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := n.cross(right).normalized()
	global_transform.basis = (planet.global_transform.basis * Basis(right, up, n)).orthonormalized()
	var fade_t := smoothstep(0.82, 1.0, travel_t)
	scale = Vector3.ONE * base_scale * lerpf(1.0, 0.72, fade_t)
	if _trail != null:
		_trail.scale = Vector3(0.75, 1.0, 0.75) * lerpf(1.0, 0.58, fade_t)

# Curve toward the nearest candidate enemy within radius.
# Never turns more than 90 degrees — passed enemies are not chased backwards.
# Candidate lists come from GameState (built once per frame, shared by all bullets).
func _steer(candidates: Array, radius: float, turn_rate: float) -> void:
	var best: Node3D = null
	var best_d := radius
	var p2 := Vector2(global_position.x, global_position.y)
	for e: Node3D in candidates:
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var d := p2.distance_to(Vector2(e.global_position.x, e.global_position.y))
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var spd := velocity.length()
	var dir := best.global_position - global_position
	dir.z = 0.0
	if dir.length_squared() < 0.000001:
		return
	var desired := dir.normalized() * spd
	if velocity.dot(desired) < -0.25:
		return
	velocity = velocity.lerp(desired, turn_rate).normalized() * spd

func _steer_sphere_enemies(radius_px_scale: float, turn_rate: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var bullet_sp := camera.unproject_position(global_position)
	var best: Node3D = null
	var best_d := 124.0 * radius_px_scale
	for node in get_tree().get_nodes_in_group("sphere_enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if String(e.get_meta("kind", "")) != "enemy":
			continue
		var sp := camera.unproject_position(e.global_position)
		if sp.x < -80.0 or sp.x > sz.x + 80.0 or sp.y < -80.0 or sp.y > sz.y + 120.0:
			continue
		var d := bullet_sp.distance_to(sp)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var spd := velocity.length()
	if spd <= 0.0001:
		return
	var dir := best.global_position - global_position
	dir.z = 0.0
	if dir.length_squared() < 0.000001:
		return
	var desired := dir.normalized() * spd
	if velocity.dot(desired) < -0.45:
		return
	velocity = velocity.lerp(desired, turn_rate).normalized() * spd
