class_name SpaceBoss
extends Node3D

# THE GENESIS: the origin of the universe, rendered as a living sacred architecture.
# Its seven articulated rays retain the rich multi-jointed motion of the old design,
# but now read as light, mercy, and creative force rather than an enemy's tentacles.

const TENTACLES := 7
const SEGMENTS := 9
const SEG_LEN := 0.62
const SETTLE_Y := 1.6          # where it settles after framing in from the top
const SPAWN_Y := 7.0           # starts above the screen
const SETTLE_LERP := 0.007     # a long, ceremonial descent into view

# Pearl, gold, jade and rose: a warm divine palette with no hostile creature hues.
const HULL := Color(0.83, 0.88, 0.94)
const HULL_HI := Color(1.0, 0.92, 0.70)
const TENT := Color(0.52, 0.86, 0.91)
const TENT_TIP := Color(1.0, 0.78, 0.30)
const CORE := Color(1.0, 0.72, 0.88)
const GOLD := Color(1.0, 0.78, 0.30)
const HALO := Color(0.72, 0.96, 1.0)
const REQUIRED_NORMAL_HITS := 18

var hp: float = 240.0
var max_hp: float = 240.0
var alive: bool = true
var departing: bool = false   # true-route TRUE END: GENESIS ascends away instead of being destroyed

# The offering is complete (SCORE spent) — GENESIS rises back up and out of view, then frees itself.
func begin_depart() -> void:
	departing = true

var _t: float = 0.0
var _tentacles: Array = []     # Array[Array[Node3D]] — joints per tentacle
var _core_mat: StandardMaterial3D
var _hull_mat: StandardMaterial3D
var _hull_hi_mat: StandardMaterial3D
var _tent_mat: StandardMaterial3D
var _tent_tip_mat: StandardMaterial3D
var _gold_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _halo_roots: Array[Node3D] = []
var _wing_roots: Array[Node3D] = []
var _lotus_root: Node3D = null
var _heart_light: OmniLight3D = null
var _normal_hits := 0
var _shield_flash := 0.0
var _beacon_released := false
var _cry_cd := 0.55
var _base_y: float = SPAWN_Y    # the eased descent height; the idle bob rides on top of it

func _ready() -> void:
	add_to_group("space_boss")
	add_to_group("genesis_boss")
	_make_materials()
	_build_core()
	_build_tentacles()
	_build_halos()
	_build_wings()
	_build_heart_light()
	position.y = SPAWN_Y

func _make_materials() -> void:
	# Only the heart and halo emit. All other forms receive real light, preserving their color.
	_hull_mat = _solid(HULL, 0.46, 0.42, HULL, 0.0)
	_hull_hi_mat = _solid(HULL_HI, 0.48, 0.38, HULL_HI, 0.0)
	_tent_mat = _solid(TENT, 0.28, 0.34, TENT, 0.0)
	_tent_tip_mat = _solid(TENT_TIP, 0.42, 0.30, TENT_TIP, 0.0)
	_gold_mat = _solid(GOLD, 0.55, 0.32, GOLD, 0.0)
	_halo_mat = _solid(HALO, 0.12, 0.25, HALO, 1.45, true)
	_core_mat = _solid(CORE, 0.10, 0.22, CORE, 2.5, true)

func _solid(albedo: Color, metallic: float, rough: float, emit: Color, emit_e: float,
		glowing: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = rough
	m.emission_enabled = glowing
	if glowing:
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	return m

static var _SOFT_BLOCK: SphereMesh

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	# A low-resolution smooth sphere scaled as a cuboid: Genesis-only soft voxels with
	# rounded shading, while the silhouette still reads as assembled blocks.
	if _SOFT_BLOCK == null:
		_SOFT_BLOCK = SphereMesh.new()
		_SOFT_BLOCK.radius = 0.5
		_SOFT_BLOCK.height = 1.0
		_SOFT_BLOCK.radial_segments = 12
		_SOFT_BLOCK.rings = 6
	mi.mesh = _SOFT_BLOCK
	mi.position = pos
	mi.scale = size
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _build_heart_light() -> void:
	_heart_light = OmniLight3D.new()
	_heart_light.light_color = Color(1.0, 0.78, 0.58)
	_heart_light.light_energy = 1.8
	_heart_light.omni_range = 8.0
	_heart_light.omni_attenuation = 1.4
	_heart_light.shadow_enabled = false
	_heart_light.position = Vector3(0.0, -0.05, 1.25)
	add_child(_heart_light)

# A symmetrical sanctuary built around a mandala lotus, not an enemy eye.
func _build_core() -> void:
	_box(self, Vector3(0.0, -0.05, 0.0), Vector3(1.45, 1.75, 1.05), _hull_mat)
	_box(self, Vector3(0.0, 0.72, 0.04), Vector3(2.55, 0.34, 0.92), _hull_hi_mat)
	_box(self, Vector3(0.0, -0.98, 0.08), Vector3(1.9, 0.36, 0.92), _hull_hi_mat)
	# Crown and vertical sanctuary spine.
	_box(self, Vector3(0.0, 1.34, -0.02), Vector3(0.62, 0.62, 0.72), _gold_mat)
	_box(self, Vector3(0.0, 1.78, -0.02), Vector3(0.22, 0.36, 0.34), _halo_mat)
	_build_lotus_mandala()

func _build_lotus_mandala() -> void:
	_lotus_root = Node3D.new()
	_lotus_root.name = "CreationLotusMandala"
	_lotus_root.position = Vector3(0.0, -0.06, 0.82)
	add_child(_lotus_root)
	# Two concentric petal crowns wrap the nucleus. They are layered in depth to avoid
	# reading as four detached ellipses from the front camera.
	for ring_i in 2:
		var count := 12 if ring_i == 0 else 8
		var radius_x := 0.88 if ring_i == 0 else 0.52
		var radius_y := 0.74 if ring_i == 0 else 0.44
		for i in count:
			var a := TAU * float(i) / float(count) + (0.0 if ring_i == 0 else PI / float(count))
			var petal := _box(_lotus_root,
				Vector3(cos(a) * radius_x, sin(a) * radius_y, -float(ring_i) * 0.10),
				Vector3(0.32 if ring_i == 0 else 0.28, 0.78 if ring_i == 0 else 0.60, 0.15),
				_gold_mat if (i + ring_i) % 2 == 0 else _hull_hi_mat)
			petal.rotation.z = a - PI * 0.5
	# The small rounded core is now a lotus seed, held inside the petals rather than exposed.
	_box(_lotus_root, Vector3(0.0, 0.0, 0.16), Vector3(0.34, 0.34, 0.18), _core_mat)

func _build_tentacles() -> void:
	for ti in TENTACLES:
		var ang := TAU * float(ti) / float(TENTACLES) - PI * 0.5
		var root := Node3D.new()
		# Seven articulated rays from the sanctuary rim: generous, flowing, never claw-like.
		root.position = Vector3(cos(ang) * 1.0, sin(ang) * 0.9, 0.2)
		root.rotation.z = ang - PI * 0.5
		add_child(root)
		var joints: Array = []
		var parent: Node3D = root
		for si in SEGMENTS:
			var joint := Node3D.new()
			joint.position = Vector3(0.0, SEG_LEN if si > 0 else 0.0, 0.0)
			parent.add_child(joint)
			var taper := 1.0 - float(si) / float(SEGMENTS) * 0.58
			var mat := _tent_tip_mat if si >= SEGMENTS - 2 else _tent_mat
			# Box spans from the parent joint to this one (centered behind +Y).
			_box(joint, Vector3(0.0, -SEG_LEN * 0.5, 0.0),
				Vector3(0.28 * taper, SEG_LEN * 1.04, 0.28 * taper), mat)
			joints.append(joint)
			parent = joint
		_tentacles.append(joints)

func _build_halos() -> void:
	for ring_i in 2:
		var root := Node3D.new()
		root.name = "GenesisHalo%d" % ring_i
		root.position = Vector3(0.0, 0.30, -0.62 - float(ring_i) * 0.18)
		add_child(root)
		_halo_roots.append(root)
		var radius := 2.05 + float(ring_i) * 0.42
		var count := 18 + ring_i * 6
		for i in count:
			var a := TAU * float(i) / float(count)
			var block := _box(root, Vector3(cos(a) * radius, sin(a) * radius, 0.0),
				Vector3(0.18, 0.18, 0.14), _halo_mat if (i & 1) == 0 else _gold_mat)
			block.rotation.z = a

func _build_wings() -> void:
	for sx: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "GenesisWingLeft" if sx < 0.0 else "GenesisWingRight"
		wing.position = Vector3(sx * 1.05, 0.40, -0.22)
		add_child(wing)
		_wing_roots.append(wing)
		for i in 6:
			var u := float(i) / 5.0
			_box(wing, Vector3(sx * (0.34 + u * 1.50), 0.10 + u * 0.88, 0.0),
				Vector3(0.30, 1.42 - u * 0.68, 0.26), _hull_hi_mat if (i & 1) == 0 else _gold_mat)

func _process(delta: float) -> void:
	_t += delta
	if departing:
		# Rise back up and out of the top of the view — a slow, grateful frame-out — then free.
		_base_y = lerpf(_base_y, SPAWN_Y + 6.0, 0.012)
		position.y = _base_y
		position.z = GameState.alt_to_z(GameState.alt) - 4.0
		if _base_y > SPAWN_Y + 3.0:
			queue_free()
		return
	# Frame in from the top, then hold and bob; track the player's depth plane so it
	# stays framed on screen as the ship climbs/descends in the space band. The descent
	# height eases down continuously and the idle bob is faded IN as it arrives (amplitude
	# scaled by how far it has settled), so it never snaps into the bob at a random phase.
	_base_y = lerpf(_base_y, SETTLE_Y, SETTLE_LERP)
	var arrived := clampf((SPAWN_Y - _base_y) / (SPAWN_Y - SETTLE_Y), 0.0, 1.0)
	position.y = _base_y + 0.25 * sin(_t * 0.6) * arrived
	position.z = GameState.alt_to_z(GameState.alt) - 4.0
	rotation.z = 0.06 * sin(_t * 0.5)
	_cry_cd -= delta
	if _cry_cd <= 0.0:
		_cry_cd = 2.6 + randf() * 1.6
		TsgAudio.genesis_cry()
	# Travelling-wave motion turns the seven articulated rays into a slow celestial bloom.
	for ti in _tentacles.size():
		var joints: Array = _tentacles[ti]
		for si in range(1, joints.size()):
			var amp := 0.10 + 0.022 * float(si)
			var j := joints[si] as Node3D
			j.rotation.z = sin(_t * 1.15 - float(si) * 0.42 + float(ti) * 0.90) * amp
	for i in _halo_roots.size():
		var halo := _halo_roots[i]
		if halo != null and is_instance_valid(halo):
			halo.rotation_degrees = Vector3(sin(_t * 0.38 + float(i)) * 6.0,
				sin(_t * 0.24 + float(i)) * 7.0, _t * (18.0 if i == 0 else -12.0))
			var breath := 1.0 + sin(_t * 1.05 + float(i)) * 0.045
			halo.scale = Vector3.ONE * breath
	for i in _wing_roots.size():
		var wing := _wing_roots[i]
		if wing != null and is_instance_valid(wing):
			var side := -1.0 if i == 0 else 1.0
			var beat := sin(_t * 0.92 + float(i) * 0.65)
			wing.rotation_degrees = Vector3(beat * 4.0, side * (8.0 + beat * 5.0), side * beat * 3.0)
	if _lotus_root != null and is_instance_valid(_lotus_root):
		_lotus_root.rotation_degrees = Vector3(sin(_t * 0.46) * 4.0,
			sin(_t * 0.31) * 5.0, _t * 9.0)
		_lotus_root.scale = Vector3.ONE * (1.0 + sin(_t * 1.35) * 0.035)
	# Creative heart pulse.
	if _core_mat != null:
		_core_mat.emission_energy_multiplier = 2.25 + 0.95 * sin(_t * 2.4) + _shield_flash * 2.2
	if _heart_light != null:
		_heart_light.light_energy = 1.55 + 0.45 * sin(_t * 2.4) + _shield_flash * 0.65
	_shield_flash = maxf(0.0, _shield_flash - delta * 4.0)
	_absorb_normal_fire()

# The Genesis deliberately takes normal fire long enough for the player to read the
# invulnerability. Bullets are visibly consumed, but only the carrier beam can lower HP.
func _absorb_normal_fire() -> void:
	for b_node in get_tree().get_nodes_in_group("bullets"):
		var b := b_node as Node3D
		if b == null or not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var dx := b.global_position.x - global_position.x
		var dy := b.global_position.y - global_position.y
		if dx * dx + dy * dy > 2.25:
			continue
		b.queue_free()
		_normal_hits += 1
		_shield_flash = 1.0
		TsgAudio.genesis_wound()
		if _normal_hits == 1:
			get_tree().call_group("star_hud", "show_message",
				"THE GENESIS IS IMMUNE", "NORMAL WEAPONS HAVE NO EFFECT")
		elif _normal_hits == 8:
			get_tree().call_group("star_hud", "show_message",
				"ARMOR UNBROKEN", "KEEP FIRING - FIND ANOTHER WAY")
		if _normal_hits % 4 == 0:
			var ex := Explosion.new()
			ex.color = Color(0.7, 0.95, 1.0)
			ex.count = 5
			ex.strength = 0.45
			get_parent().add_child(ex)
			ex.global_position = b.global_position
		if _normal_hits >= REQUIRED_NORMAL_HITS and not _beacon_released:
			_beacon_released = true
			if get_parent() != null and get_parent().has_method("_release_genesis_beacon"):
				get_parent().call_deferred("_release_genesis_beacon")
		return

# Heavy carrier strike (stage C wires this in). Normal ship fire never calls it.
func take_carrier_damage(d: float) -> void:
	if not alive:
		return
	hp = maxf(0.0, hp - d)
	if hp <= 0.0:
		alive = false
		GameState.final_boss_defeated = true
