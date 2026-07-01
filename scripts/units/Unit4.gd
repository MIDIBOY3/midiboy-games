extends Node3D

var alt_t: float    = 0.0
var cruise_t: float = 0.0
var robot_t: float  = 0.0
var bullet_scene: PackedScene = null
var _tick: int = 0

func set_bullet_scene(s: PackedScene) -> void:
	bullet_scene = s

@onready var _left_cannon:  Node3D = $left_cannon_group
@onready var _right_cannon: Node3D = $right_cannon_group
@onready var _bridge:       Node3D = $bridge_group

var _beam_l: MeshInstance3D
var _beam_r: MeshInstance3D
var _beam_mat: StandardMaterial3D

func _ready() -> void:
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = Color(0.5, 1.0, 0.5, 0.85)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(0.45, 1.0, 0.45)
	_beam_mat.emission_energy_multiplier = 2.5
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_l = _make_beam()
	_beam_r = _make_beam()
	_left_cannon.add_child(_beam_l)
	_right_cannon.add_child(_beam_r)

func _make_beam() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 1.0, 0.022)
	m.mesh = box
	m.material_override = _beam_mat
	m.visible = false
	return m

func set_rig(p_alt_t: float, p_cruise_t: float) -> void:
	alt_t    = clamp(p_alt_t,    0.0, 1.0)
	cruise_t = clamp(p_cruise_t, 0.0, 1.0)

func set_robot(p_robot_t: float) -> void:
	robot_t = clamp(p_robot_t, 0.0, 1.0)

func _process(_delta: float) -> void:
	var cannon_merge  := cruise_t * 0.024
	var cannon_down   := cruise_t * 0.020
	var cannon_spread := alt_t    * 0.080
	var bridge_dy     := alt_t * 0.070 - cruise_t * 0.012

	# Robot back mode:
	# Cannons slide outward only to the fuselage edge (≈±0.10) and descend slightly.
	# Both cannon_spread and cannon_merge are cancelled so robot_cx is the only x offset.
	# Fuselage half-width from tscn: fuse_top = 0.20 wide → 0.10 half. Cannon starts at ±0.025.
	# robot_cx = 0.075 → final x = ±(0.025 + 0.075) = ±0.10, exactly at fuselage edge. ✓
	var eff_spread := lerpf(cannon_spread, 0.0, robot_t)
	var eff_merge  := lerpf(cannon_merge,  0.0, robot_t)
	# Robot: cannons spread to fuselage edge (±0.10) and drop into Unit3 shoulder area.
	# Unit4 is positioned at +0.05Y (inside Unit3) so cannon world y ≈ +0.14 = shoulder level.
	var robot_cx      := robot_t * 0.055
	var robot_cy_drop := robot_t * 0.07

	_left_cannon.position  = Vector3(
		-0.025 + eff_merge - eff_spread - robot_cx,
		 0.27  - cannon_down - robot_cy_drop,
		 0.0
	)
	_right_cannon.position = Vector3(
		 0.025 - eff_merge + eff_spread + robot_cx,
		 0.27  - cannon_down - robot_cy_drop,
		 0.0
	)

	_bridge.position.y = 0.06 + bridge_dy - robot_t * 0.04
	_update_laser()

# Unit4's weapon cycle (formation only):
#   GROW — the twin beams extend from the cannons (sword phase: anything the
#          growing edge sweeps through gets cut),
#   FIRE — at full length both blades detach and fly forward (LaserBlade),
#   COOL — short pause, then grow again.
# Level grows the max LENGTH (0.7 → 2.5), cut tick rate and blade speed.
const GROW_FRAMES := 50
const COOL_FRAMES := 25

var _phase: String = "grow"
var _phase_t: int = 0

func _update_laser() -> void:
	var active: bool = bullet_scene != null and robot_t < 0.5 \
		and GameState.sep_t > 0.5 and not GameState.game_over and not GameState.carrier_battle \
		and not GameState.ending_cinematic and not GameState.boss_intro_active \
		and GameState.god_phase == 0
	if not active:
		_beam_l.visible = false
		_beam_r.visible = false
		_phase = "grow"
		_phase_t = 0
		return

	if _phase == "cool":
		_beam_l.visible = false
		_beam_r.visible = false
		_phase_t += 1
		if _phase_t >= COOL_FRAMES:
			_phase = "grow"
			_phase_t = 0
		return

	# GROW phase
	_phase_t += 1
	var lv := GameState.unit_level(4)
	var max_len := 0.7 + 0.45 * (lv - 1)
	var grow_t := minf(1.0, float(_phase_t) / float(GROW_FRAMES))
	var blen: float = max_len * grow_t

	_beam_l.visible = true
	_beam_r.visible = true
	var pulse := 1.0 + 0.25 * sin(GameState.frame * 0.4)
	for b: MeshInstance3D in [_beam_l, _beam_r]:
		b.position = Vector3(0, 0.14 + blen * 0.5, 0)
		b.scale = Vector3(pulse, maxf(0.01, blen), pulse)
	_beam_mat.emission_energy_multiplier = 2.0 + 0.8 * sin(GameState.frame * 0.4)

	_cut_tick(blen, lv)

	if grow_t >= 1.0:
		_fire_blades(blen, lv)
		_phase = "cool"
		_phase_t = 0

# Sword phase damage: every same-band enemy touching either growing beam.
func _cut_tick(blen: float, lv: int) -> void:
	_tick += 1
	var tick_interval: int = 8 - int(lv / 2.0)
	if _tick < tick_interval:
		return
	_tick = 0

	var s := scale.x
	var dirv := global_transform.basis.y.normalized()
	var d2 := Vector2(dirv.x, dirv.y)
	if d2.length_squared() < 0.000001:
		return
	d2 = d2.normalized()
	var world_len := blen * s
	var width := 0.07 * s
	var starts: Array[Vector3] = [
		_left_cannon.global_position + dirv * (0.14 * s),
		_right_cannon.global_position + dirv * (0.14 * s),
	]
	for e: Node3D in GameState.marked_enemies():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var hit := false
		for sp in starts:
			var rel := Vector2(e.global_position.x - sp.x, e.global_position.y - sp.y)
			var along := rel.dot(d2)
			if along < 0.0 or along > world_len:
				continue
			if absf(rel.cross(d2)) <= width:
				hit = true
				break
		if not hit:
			continue
		var pos: Vector3 = e.global_position
		var hue: Variant = e.get("hue")
		var mh: Variant = e.get("max_hp")
		TsgAudio.enemy_hit()
		if e.has_method("take_hit") and e.call("take_hit", 4):
			TsgAudio.enemy_destroy()
			GameState.score += 100
			GameState.add_exp(40 * (int(mh) if mh != null else 1))
			var ex := Explosion.new()
			if hue != null:
				ex.color = Color.from_hsv(float(hue) / 360.0, 0.7, 1.0)
			get_parent().add_child(ex)
			ex.global_position = pos

# FIRE phase: at full length the beams detach. Each cannon launches a MAIN blade
# straight ahead; from the same launch point SUB blades peel off to the sides and
# diagonally up so the volley fans across the screen before it can leave the top.
func _fire_blades(blen: float, lv: int) -> void:
	TsgAudio.unit4_laser_fire()
	var s := scale.x
	var dirv := global_transform.basis.y.normalized()
	var world_len := blen * s
	# MAINS — one blade from each cannon, drifting straight up (keeps twin look).
	for cannon: Node3D in [_left_cannon, _right_cannon]:
		_spawn_blade(dirv, dirv, cannon.global_position + dirv * (0.14 * s + world_len * 0.5),
			world_len, s, lv)
	# SUBS — same VERTICAL blade shape, but sliding 真横 / 斜め上 across-screen.
	var centre: Vector3 = (_left_cannon.global_position + _right_cannon.global_position) * 0.5 \
		+ dirv * (0.14 * s + world_len * 0.5)
	for deg in _sub_angles(lv):
		_spawn_blade(dirv, _rotate_xy(dirv, deg_to_rad(deg)), centre, world_len, s, lv)

# Sub-blade angle offsets from straight-ahead, widening with level.
# Positive leans toward one side, mirrored for the other. 90° = 真横, 45° = 斜め上.
func _sub_angles(lv: int) -> Array:
	if lv <= 1:
		return [45.0, -45.0]
	elif lv <= 3:
		return [45.0, -45.0, 90.0, -90.0]
	return [35.0, -35.0, 65.0, -65.0, 90.0, -90.0]

func _rotate_xy(v: Vector3, ang: float) -> Vector3:
	var r := Vector2(v.x, v.y).rotated(ang)
	return Vector3(r.x, r.y, v.z).normalized()

func _spawn_blade(orient: Vector3, move: Vector3, origin: Vector3, world_len: float, s: float, lv: int) -> void:
	var blade := LaserBlade.new()
	blade.dir = orient        # blade stays oriented this way (vertical)
	blade.move_dir = move     # …while it drifts along here (横 / 斜め)
	blade.speed = 0.10 + 0.012 * lv
	blade.blade_len = world_len
	blade.width = 0.13 * s
	blade.vis_scale = s
	get_parent().add_child(blade)
	blade.global_position = origin
