class_name BlackHoleBoss
extends Node3D

# The black-hole mid-boss: a GORGEOUS, vicious multi-jointed block-polygon monster
# fought in clean dark space (no structures). Spawned by Main._update_blackhole after
# three blind gate crossings. Every joint is an independently destructible Part (in the
# "enemies" group with its own take_hit), so normal ship fire whittles it down piece by
# piece — no special damage plumbing needed.
#
# Unified kill model for all variants: a pile of MINIONS (body segments / limb modules /
# escorts) shields an invulnerable CORE. Clear every minion → the core unseals → destroy
# the core to win. Each variant only differs in how it's built and how it MOVES.
#
# Threat model: the CORE fires a signature pattern on its own cadence, and EVERY surviving
# minion contributes a cycling volley — so the boss is most dangerous while fully assembled
# and eases as you strip it down. Tank-grade HP across the board (these are mid-BOSSES).
#
# Variants (random encounter):
#   0 DRAGON   — a long, fast serpent of jointed vertebrae swimming across altitudes.
#   1 COMBINER — a giant mech that assembles from six role-shaped limb-modules (head,
#                chest, arms, legs), then splits apart and orbits, re-combining on a cycle;
#                a reactor core sits at the chest.
#   2 FLEET    — a broadside dreadnought with a bridge core, bristling turrets and engine
#                glow, escorted by a wing of fighter gunships.
#
# Behind it all: a dark accretion-disk backdrop kept centred on screen. Geometry/timing
# are TUNE values (no engine here to verify).

const SPAWN_Y := 6.5            # frames in from above the screen
const SETTLE_Y := 0.8           # settles to here, then moves
const SETTLE_LERP := 0.014

# Dragon shape/tuning — long, fast, many joints.
const DRAGON_SEGMENTS := 18
const DRAGON_HEAD_HP := 150
const DRAGON_SEG_HP := 14
const DRAGON_SPEED := 2.6       # spine phase speed (faster, whippier serpent)
const DRAGON_Z_WEAVE := 1.7     # depth (altitude) sweep

# Combiner tuning.
const COMBINER_MODULES := 6
const COMBINER_MOD_HP := 34
const COMBINER_CORE_HP := 170
const COMB_CYCLE := 5.4         # one assemble→hold→scatter→orbit loop

# Fleet tuning.
const FLEET_ESCORTS := 8
const FLEET_ESC_HP := 26
const FLEET_CORE_HP := 180

# Menacing palette: bruised magenta hull, blade-cyan trim, a hot core, bone-white spikes.
# (The black-hole VOID is the space_background shader — Background.gd drives dark_mix while
# blackhole_active — so the boss carries no backdrop of its own.)
const HULL    := Color(0.24, 0.10, 0.32)
const HULL_HI := Color(0.46, 0.20, 0.56)
const TRIM    := Color(0.40, 1.0, 1.0)
const CORE    := Color(1.0, 0.20, 0.14)
const SPIKE   := Color(0.86, 0.82, 0.92)

var variant: int = 0

var _t: float = 0.0
var _settle: float = 0.0
var _alive: bool = true
var _core: Part = null
var _minions: Array = []        # destructible shields; clear them to expose the core
var _core_exposed: bool = false
var _fire_cd: int = 70          # core signature cadence
var _volley_cd: int = 40        # cycling per-minion volley cadence
var _volley_idx: int = 0

# Combiner state.
var _modules_home: Array = []   # combined-formation local slots, per module
var _flag: Node3D = null        # fleet flagship hull (decorative; carries the bridge core)

var _hull_mat: StandardMaterial3D
var _hull_hi_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _spike_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D

# ---------------------------------------------------------------------------
# A single destructible joint. In the "enemies" group so the normal bullet→enemy
# collision damages it. No is_in_player_range → hittable at any altitude, and no
# contact damage (the boss threatens only through its fire).
class Part extends Node3D:
	var hp: int = 5
	var max_hp: int = 5
	var hue: float = 295.0
	var hit_radius: float = 0.26
	var invuln: bool = false
	var phase: float = 0.0     # stable per-minion orbit phase (so deaths don't reshuffle)
	var ring: int = 0          # which guard ring this escort belongs to

	func _ready() -> void:
		add_to_group("enemies")

	func take_hit(_uid: int = 0) -> bool:
		if invuln:
			return false           # core sealed: hit sound plays but no damage lands
		hp -= 1
		if hp <= 0:
			queue_free()
			return true
		return false
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("blackhole_boss")
	_make_materials()
	match variant:
		1: _build_combiner()
		2: _build_fleet()
		_: _build_dragon()
	position.y = SPAWN_Y

func _make_materials() -> void:
	_hull_mat    = _solid(HULL, 0.6, 0.45, HULL * 0.7, 0.6)
	_hull_hi_mat = _solid(HULL_HI, 0.5, 0.45, HULL_HI * 0.8, 1.1)
	_trim_mat    = _solid(TRIM, 0.35, 0.3, TRIM, 2.8)
	_spike_mat   = _solid(SPIKE, 0.3, 0.6, SPIKE * 0.5, 0.6)
	_core_mat    = _solid(CORE, 0.2, 0.3, CORE, 2.8)

func _solid(c: Color, rough: float, metal: float, em: Color, em_e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = em
	m.emission_energy_multiplier = em_e
	return m

func _blk(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, spin_z: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	m.mesh = bm
	m.position = pos
	m.scale = size
	m.rotation.z = spin_z
	m.material_override = mat
	parent.add_child(m)
	return m

# A vicious spike (tapered fang/horn) pointing along +y, rotated by spin_z.
func _spike(parent: Node3D, pos: Vector3, len: float, spin_z: float = 0.0) -> void:
	var m := _blk(parent, pos, Vector3(0.06, len, 0.06), _spike_mat, spin_z)
	m.rotation.z = spin_z

func _new_part(hp: int, radius: float, hue: float, invuln: bool) -> Part:
	var p := Part.new()
	p.hp = hp
	p.max_hp = hp
	p.hit_radius = radius
	p.hue = hue
	p.invuln = invuln
	add_child(p)
	return p

# ===========================================================================
# DRAGON  (kept — the well-liked variant — just buffed)
# ===========================================================================
func _build_dragon() -> void:
	_core = _new_part(DRAGON_HEAD_HP, 0.50, 318.0, true)
	_decorate_dragon_head(_core)
	_minions.clear()
	for i in DRAGON_SEGMENTS:
		var p := _new_part(DRAGON_SEG_HP, 0.27, 288.0, false)
		_decorate_dragon_segment(p, i)
		_minions.append(p)

func _decorate_dragon_head(p: Part) -> void:
	var s := 1.9
	_blk(p, Vector3(0, 0, 0), Vector3(0.36, 0.32, 0.36) * s, _hull_mat)
	_blk(p, Vector3(0, 0.16 * s, 0), Vector3(0.42, 0.12, 0.30) * s, _hull_hi_mat)   # crown
	_blk(p, Vector3(0, -0.22 * s, 0.08), Vector3(0.34, 0.14, 0.24) * s, _hull_mat)  # jaw
	# Hot twin eyes + central crest.
	_blk(p, Vector3(-0.11 * s, 0.05 * s, 0.20 * s), Vector3(0.08, 0.08, 0.08) * s, _core_mat)
	_blk(p, Vector3(0.11 * s, 0.05 * s, 0.20 * s), Vector3(0.08, 0.08, 0.08) * s, _core_mat)
	_blk(p, Vector3(0, 0.06 * s, 0.18 * s), Vector3(0.05, 0.20, 0.05) * s, _trim_mat)
	# Horns + a row of fangs along the jaw → menacing skull.
	_spike(p, Vector3(0.18 * s, 0.30 * s, 0), 0.32 * s, 0.5)
	_spike(p, Vector3(-0.18 * s, 0.30 * s, 0), 0.32 * s, -0.5)
	for k in 4:
		var fx := (float(k) / 3.0 - 0.5) * 0.40 * s
		_spike(p, Vector3(fx, -0.30 * s, 0.14 * s), 0.16 * s, PI)   # downward fangs

func _decorate_dragon_segment(p: Part, i: int) -> void:
	var taper := 1.0 - 0.4 * (float(i) / float(DRAGON_SEGMENTS))
	_blk(p, Vector3.ZERO, Vector3(0.30, 0.28, 0.30) * taper, _hull_mat)
	_blk(p, Vector3(0, 0.04 * taper, 0.15 * taper), Vector3(0.16, 0.12, 0.06) * taper, _trim_mat)  # glowing spine
	_spike(p, Vector3(0, 0.22 * taper, 0), 0.26 * taper)                                          # dorsal spike
	_spike(p, Vector3(0.20 * taper, 0, 0), 0.18 * taper, 1.05)                                    # side spikes
	_spike(p, Vector3(-0.20 * taper, 0, 0), 0.18 * taper, -1.05)

func _anim_dragon(_delta: float) -> void:
	position.x = sin(_t * 0.8) * 1.2 + cos(_t * 1.9) * 0.35   # restless lateral prowl
	position.y += sin(_t * 1.1) * 0.3
	if is_instance_valid(_core):
		_place_chain(_core, 0)
	for j in _minions.size():
		_place_chain(_minions[j], j + 1)

func _dragon_local(i: int) -> Vector3:
	var ph := _t * DRAGON_SPEED - float(i) * 0.5
	# Whippier S-curve: bigger lateral throw + a coiling lunge that surges the head forward.
	var surge := 0.4 * sin(_t * 1.6)
	return Vector3(
		sin(ph) * (2.4 + surge),
		cos(ph * 0.9) * 0.9 - float(i) * 0.03,
		sin(ph * 0.6) * DRAGON_Z_WEAVE)

func _place_chain(p: Node3D, i: int) -> void:
	var here := _dragon_local(i)
	p.position = here
	var ahead := _dragon_local(maxi(0, i - 1))
	var d := ahead - here
	if d.length_squared() > 0.0001:
		p.rotation.z = atan2(d.y, d.x) - PI / 2.0

# ===========================================================================
# COMBINER  — a real assembling mech, each module shaped for its role
# ===========================================================================
func _build_combiner() -> void:
	# Reactor torso CORE (sealed until the limbs are stripped away).
	_core = _new_part(COMBINER_CORE_HP, 0.46, 0.0, true)
	_blk(_core, Vector3.ZERO, Vector3(0.54, 0.62, 0.42), _hull_mat)          # torso frame
	_blk(_core, Vector3(0, 0.30, 0.0), Vector3(0.78, 0.18, 0.42), _hull_hi_mat)  # collar
	_blk(_core, Vector3(0, -0.02, 0.16), Vector3(0.34, 0.34, 0.14), _core_mat)   # reactor heart
	for a in 6:
		_blk(_core, Vector3(0, -0.02, 0.13), Vector3(0.66, 0.06, 0.06), _trim_mat,
			TAU * float(a) / 6.0)                                            # reactor spokes
	_blk(_core, Vector3(0, -0.30, 0.10), Vector3(0.46, 0.12, 0.30), _hull_hi_mat)  # belt
	# Six limb-modules with their combined (humanoid) home slots.
	_modules_home = [
		Vector3(0.0, 1.18, 0.0),    # head
		Vector3(0.0, 0.46, 0.06),   # chest plate (hides reactor when combined)
		Vector3(-0.86, 0.50, 0.0),  # left arm
		Vector3(0.86, 0.50, 0.0),   # right arm
		Vector3(-0.36, -0.62, 0.0), # left leg
		Vector3(0.36, -0.62, 0.0),  # right leg
	]
	_minions.clear()
	for i in COMBINER_MODULES:
		var p := _new_part(COMBINER_MOD_HP, 0.42, 268.0 + float(i) * 8.0, false)
		_decorate_combiner_module(p, i)
		_minions.append(p)

func _decorate_combiner_module(p: Part, i: int) -> void:
	match i:
		0: _mech_head(p)
		1: _mech_chest(p)
		2: _mech_arm(p, -1.0)
		3: _mech_arm(p, 1.0)
		4: _mech_leg(p, -1.0)
		_: _mech_leg(p, 1.0)

func _mech_head(p: Part) -> void:
	_blk(p, Vector3.ZERO, Vector3(0.40, 0.42, 0.40), _hull_mat)              # skull
	_blk(p, Vector3(0, -0.05, 0.20), Vector3(0.30, 0.16, 0.12), _hull_hi_mat)   # faceplate
	_blk(p, Vector3(-0.09, 0.0, 0.24), Vector3(0.08, 0.05, 0.06), _core_mat)    # eye L
	_blk(p, Vector3(0.09, 0.0, 0.24), Vector3(0.08, 0.05, 0.06), _core_mat)     # eye R
	_blk(p, Vector3(0, 0.12, 0.18), Vector3(0.05, 0.22, 0.05), _trim_mat)       # forehead crest
	_blk(p, Vector3(-0.22, 0.02, 0.0), Vector3(0.07, 0.22, 0.12), _hull_hi_mat) # ear vent L
	_blk(p, Vector3(0.22, 0.02, 0.0), Vector3(0.07, 0.22, 0.12), _hull_hi_mat)  # ear vent R
	_spike(p, Vector3(-0.18, 0.28, 0), 0.26, 0.45)                              # horn L
	_spike(p, Vector3(0.18, 0.28, 0), 0.26, -0.45)                             # horn R

func _mech_chest(p: Part) -> void:
	_blk(p, Vector3.ZERO, Vector3(0.70, 0.54, 0.44), _hull_mat)             # torso plate
	_blk(p, Vector3(0, 0.24, 0.02), Vector3(0.92, 0.18, 0.42), _hull_hi_mat)   # shoulders
	_blk(p, Vector3(0, -0.02, 0.24), Vector3(0.30, 0.30, 0.10), _core_mat)     # chest reactor glow
	for k in 3:
		var vy := (float(k) - 1.0) * 0.12
		_blk(p, Vector3(0, vy, 0.26), Vector3(0.20, 0.04, 0.04), _trim_mat)    # vent slats
	_spike(p, Vector3(-0.42, 0.30, 0), 0.24, 0.7)                              # shoulder spike L
	_spike(p, Vector3(0.42, 0.30, 0), 0.24, -0.7)                             # shoulder spike R

func _mech_arm(p: Part, s: float) -> void:
	_blk(p, Vector3(0.04 * s, 0.20, 0), Vector3(0.34, 0.28, 0.36), _hull_hi_mat)  # pauldron
	_spike(p, Vector3(0.10 * s, 0.36, 0), 0.24, -0.35 * s)                       # pauldron spike
	_blk(p, Vector3(0, -0.04, 0), Vector3(0.24, 0.36, 0.26), _hull_mat)          # upper arm
	_blk(p, Vector3(0, -0.36, 0.02), Vector3(0.28, 0.32, 0.30), _hull_mat)       # forearm
	_blk(p, Vector3(0, -0.34, 0.18), Vector3(0.10, 0.10, 0.10), _trim_mat)       # knuckle trim
	_blk(p, Vector3(0, -0.56, 0.10), Vector3(0.20, 0.22, 0.34), _core_mat)       # arm-cannon muzzle

func _mech_leg(p: Part, s: float) -> void:
	_blk(p, Vector3(0, 0.22, 0), Vector3(0.30, 0.32, 0.32), _hull_hi_mat)        # thigh
	_blk(p, Vector3(0.16 * s, 0.10, 0.0), Vector3(0.10, 0.18, 0.16), _hull_mat)  # knee guard
	_spike(p, Vector3(0.22 * s, 0.06, 0), 0.18, -1.2 * s)                        # knee spike
	_blk(p, Vector3(0, -0.16, 0), Vector3(0.26, 0.36, 0.28), _hull_mat)          # shin
	_blk(p, Vector3(0, -0.42, 0.10), Vector3(0.32, 0.16, 0.42), _hull_mat)       # foot
	_blk(p, Vector3(0, -0.34, -0.18), Vector3(0.18, 0.18, 0.10), _core_mat)      # heel thruster glow

# Phased so it SNAPS into a clean mech and holds (instead of forever half-merged), then
# bursts apart and strafes. cyc∈[0,COMB_CYCLE):
#   [0,0.7)  ASSEMBLE  — modules rush in and lock upright
#   [0.7,2.7) MECH      — fully formed; the giant lunges and throws punches
#   [2.7,3.3) SCATTER   — explodes apart
#   [3.3,end) ORBIT     — modules spin out on fast wide orbits and strafe
func _anim_combiner(_delta: float) -> void:
	var cyc := fmod(_t, COMB_CYCLE)
	var combine: float
	var spin: float
	var punch := 0.0
	if cyc < 0.7:
		combine = smoothstep(0.0, 1.0, cyc / 0.7)
		spin = 1.0 - combine
	elif cyc < 2.7:
		combine = 1.0
		spin = 0.0
		punch = sin((cyc - 0.7) * TAU * 1.5)   # alternating arm thrusts
	elif cyc < 3.3:
		combine = 1.0 - smoothstep(0.0, 1.0, (cyc - 2.7) / 0.6)
		spin = 1.0 - combine
	else:
		combine = 0.0
		spin = 1.0

	# Whole-body motion: lively strafing always; a hard lunge while assembled.
	position.x = sin(_t * 0.9) * 1.1 + cos(_t * 1.7) * 0.3
	position.y += sin(_t * 1.4) * 0.22
	if combine > 0.5:
		position.x += sin(_t * 2.4) * 0.6 * combine          # mech dash/sway
		position.y += -0.18 * maxf(0.0, sin((cyc - 0.7) * TAU * 1.5)) * combine  # stomp dip

	for i in _minions.size():
		var p: Node3D = _minions[i]
		var home: Vector3 = _modules_home[i] if i < _modules_home.size() else Vector3.ZERO
		var ang := _t * 2.4 + TAU * float(i) / float(COMBINER_MODULES)
		var split := Vector3(cos(ang) * 2.7, sin(ang) * 2.0 + 0.2, sin(ang * 1.3) * 1.3)
		var pos := split.lerp(home, combine)
		# Arms (upper, off-centre slots) punch down/forward while the mech is whole.
		if combine > 0.9 and home.y > 0.3 and absf(home.x) > 0.5:
			var ph := punch * (1.0 if home.x > 0.0 else -1.0)
			pos.y += minf(0.0, ph) * 0.45
			pos.z += maxf(0.0, ph) * 0.35
		p.position = pos
		p.rotation.z = spin * ang * 2.0
	if is_instance_valid(_core):
		_core.position = Vector3(0, 0.40, -0.06)
		_core.rotation.z = _t * (3.0 if combine < 0.5 else 0.5)   # reactor spins up when bared

# ===========================================================================
# FLEET  — a broadside dreadnought with fighter-gunship escorts
# ===========================================================================
func _build_fleet() -> void:
	# Flagship hull (decorative blocks) carrying the bridge CORE.
	_flag = Node3D.new()
	add_child(_flag)
	# Long layered hull.
	_blk(_flag, Vector3.ZERO, Vector3(2.3, 0.46, 0.66), _hull_mat)               # main spine
	_blk(_flag, Vector3(0, 0.22, 0.04), Vector3(1.8, 0.22, 0.50), _hull_hi_mat)  # upper armour deck
	_blk(_flag, Vector3(0, -0.20, 0.06), Vector3(2.05, 0.18, 0.50), _hull_mat)   # lower hull
	# Prow rams at each end.
	for sx in [-1.0, 1.0]:
		_blk(_flag, Vector3(1.22 * sx, 0, 0), Vector3(0.5, 0.30, 0.42), _hull_hi_mat)
		_spike(_flag, Vector3(1.52 * sx, 0, 0), 0.5, -PI / 2.0 * sx)
		# Engine nacelle + thruster glow at the rear corners.
		_blk(_flag, Vector3(1.0 * sx, 0.28, -0.18), Vector3(0.34, 0.30, 0.34), _hull_mat)
		_blk(_flag, Vector3(1.0 * sx, 0.28, -0.34), Vector3(0.22, 0.20, 0.10), _core_mat)
	# Gun turrets bristling along the underside, each with a downward barrel.
	for k in 7:
		var tx := (float(k) / 6.0 - 0.5) * 1.9
		_blk(_flag, Vector3(tx, -0.30, 0.20), Vector3(0.16, 0.14, 0.18), _hull_hi_mat)
		_spike(_flag, Vector3(tx, -0.46, 0.20), 0.20, PI)
	# Window strip + sensor masts.
	for k in 11:
		var lx := (float(k) / 10.0 - 0.5) * 1.7
		_blk(_flag, Vector3(lx, 0.10, 0.30), Vector3(0.07, 0.07, 0.05), _trim_mat)
	_spike(_flag, Vector3(-0.5, 0.40, 0.0), 0.42)
	_spike(_flag, Vector3(0.5, 0.40, 0.0), 0.42)
	# Bridge tower CORE rising from the spine.
	_core = _new_part(FLEET_CORE_HP, 0.48, 198.0, true)
	_blk(_core, Vector3(0, 0.0, 0.0), Vector3(0.40, 0.34, 0.40), _hull_hi_mat)   # tower base
	_blk(_core, Vector3(0, 0.22, 0.04), Vector3(0.30, 0.26, 0.30), _hull_mat)    # command deck
	_blk(_core, Vector3(0, 0.06, 0.22), Vector3(0.22, 0.18, 0.10), _core_mat)    # bridge glow
	_spike(_core, Vector3(0, 0.42, 0), 0.34)                                     # comms mast
	# Escort gunships fly a guard SCREEN that revolves around the mothership: two rings
	# (one in the screen plane, one tilted through depth) for a protective shell.
	_minions.clear()
	var per_ring := int(ceil(float(FLEET_ESCORTS) / 2.0))
	for i in FLEET_ESCORTS:
		var p := _new_part(FLEET_ESC_HP, 0.30, 188.0 + float(i) * 6.0, false)
		p.ring = i % 2
		p.phase = TAU * float(i / 2) / float(per_ring)
		_decorate_fleet_escort(p)
		_minions.append(p)

func _decorate_fleet_escort(p: Part) -> void:
	_blk(p, Vector3.ZERO, Vector3(0.20, 0.16, 0.46), _hull_mat)              # fuselage
	_blk(p, Vector3(0, 0.0, -0.16), Vector3(0.52, 0.10, 0.20), _hull_hi_mat)    # swept wings
	_spike(p, Vector3(-0.30, 0.0, -0.14), 0.20, 1.4)                            # wingtip L
	_spike(p, Vector3(0.30, 0.0, -0.14), 0.20, -1.4)                           # wingtip R
	_blk(p, Vector3(0, 0.04, 0.24), Vector3(0.10, 0.08, 0.12), _trim_mat)       # canopy
	_blk(p, Vector3(0, 0.0, -0.30), Vector3(0.12, 0.10, 0.08), _core_mat)       # engine glow

func _anim_fleet(_delta: float) -> void:
	# Flagship makes wide banking broadside passes instead of hovering.
	position.x = sin(_t * 0.5) * 1.5
	position.y += sin(_t * 0.9) * 0.2
	var bank := sin(_t * 0.7) * 0.20
	var ship := Vector3(0, 0.9 + sin(_t * 1.1) * 0.18, 0)
	if _flag != null:
		_flag.position = ship
		_flag.rotation.z = bank
		_flag.rotation.x = sin(_t * 0.5) * 0.12
	if is_instance_valid(_core):
		_core.position = ship + Vector3(0, 0.16, 0.04)
		_core.rotation.z = bank
	# Escorts revolve around the mothership as a guard screen — two rings forming a shell.
	for m in _minions:
		var p := m as Part
		if p == null:
			continue
		var a := _t * 0.9 + p.phase
		var off: Vector3
		if p.ring == 0:
			# Screen-plane ring: circles around the hull as seen by the player.
			off = Vector3(cos(a) * 2.5, sin(a) * 1.5, sin(a) * 0.5)
		else:
			# Depth-tilted ring: sweeps in front of and behind the mothership.
			off = Vector3(cos(a) * 2.2, 0.5 + sin(a) * 0.6, sin(a) * 1.6)
		p.position = ship + off
		p.rotation.z = a + PI * 0.5                  # nose along the orbit
		p.rotation.y = sin(_t * 1.5 + p.phase) * 0.3

# ===========================================================================
# Shared per-frame update
# ===========================================================================
func _process(delta: float) -> void:
	if not _alive:
		return
	_t += delta
	_settle = minf(1.0, _settle + SETTLE_LERP)
	position.y = lerpf(SPAWN_Y, SETTLE_Y, _settle)

	_minions = _minions.filter(func(p: Variant) -> bool:
		return is_instance_valid(p) and not (p as Node).is_queued_for_deletion())

	match variant:
		1: _anim_combiner(delta)
		2: _anim_fleet(delta)
		_: _anim_dragon(delta)

	# Minions cleared → the core unseals (it flares and becomes vulnerable).
	if not _core_exposed and _minions.is_empty() and is_instance_valid(_core):
		_core_exposed = true
		_core.invuln = false
		_core_mat.emission_energy_multiplier = 5.0
		get_tree().call_group("star_hud", "show_message",
			"THE CORE IS EXPOSED", "STRIKE IT DOWN")

	# Core destroyed → boss defeated.
	if not is_instance_valid(_core) or _core.is_queued_for_deletion():
		_die()
		return
	if _core_exposed:
		_core_mat.emission_energy_multiplier = 4.0 + 1.6 * sin(_t * 6.0)

	if _settle <= 0.5:
		return

	# Core signature pattern — enraged once it's bare.
	_fire_cd -= 1
	if _fire_cd <= 0:
		_fire_core()

	# Every surviving minion contributes a cycling volley → most dangerous while whole.
	_volley_cd -= 1
	if _volley_cd <= 0 and not _minions.is_empty():
		_volley_cd = 22 if _core_exposed else 26
		_fire_volley()

# Direction from a muzzle toward the player ship.
func _aim(o: Vector3) -> float:
	return atan2(GameState.py - o.y, GameState.px - o.x)

func _spawn_shot(o: Vector3, ang: float, speed: float) -> void:
	var b := EnemyBullet.new()
	b.bullet_type = "shot"
	b.alt = GameState.alt / GameState.ALT_MAX     # always in the player's band → it can hit
	b.velocity = Vector3(cos(ang), sin(ang), 0.0) * speed
	b.position = Vector3(o.x, o.y, GameState.alt_to_z(GameState.alt))
	get_parent().add_child(b)

func _fire_core() -> void:
	if not is_instance_valid(_core):
		return
	var o: Vector3 = _core.global_position
	match variant:
		1:  # COMBINER — spinning radial reactor burst when exposed, twin aimed bolts sealed.
			if _core_exposed:
				_fire_cd = 40
				var n := 9
				for k in n:
					_spawn_shot(o, _t * 1.3 + TAU * float(k) / float(n), 0.026)
			else:
				_fire_cd = 64
				var base := _aim(o)
				_spawn_shot(o, base - 0.10, 0.030)
				_spawn_shot(o, base + 0.10, 0.030)
		2:  # FLEET — broadside fan from the bridge battery.
			_fire_cd = 38 if _core_exposed else 64
			var base := _aim(o)
			var n := 5 if _core_exposed else 3
			for k in n:
				_spawn_shot(o, base + (float(k) - float(n - 1) * 0.5) * 0.16, 0.029)
		_:  # DRAGON — a hot breath spread from the maw.
			_fire_cd = 34 if _core_exposed else 54
			var base := _aim(o)
			var n := 5 if _core_exposed else 3
			for k in n:
				_spawn_shot(o, base + (float(k) - float(n - 1) * 0.5) * 0.20, 0.033)

func _fire_volley() -> void:
	var idx := _volley_idx % _minions.size()
	_volley_idx += 1
	var m: Variant = _minions[idx]
	if not is_instance_valid(m):
		return
	var o: Vector3 = (m as Node3D).global_position
	var base := _aim(o)
	match variant:
		1:  # arm-cannon burst
			for k in 3:
				_spawn_shot(o, base + (float(k) - 1.0) * 0.13, 0.030)
		2:  # escort snipe
			_spawn_shot(o, base, 0.037)
		_:  # serpent spit
			_spawn_shot(o, base, 0.034)

func _die() -> void:
	_alive = false
	for c in [Color(1.0, 0.5, 1.0), Color(1.0, 0.85, 0.5)]:
		var ex := Explosion.new()
		ex.color = c
		ex.count = 54
		ex.strength = 3.2
		get_parent().add_child(ex)
		ex.global_position = global_position
	TsgAudio.enemy_destroy()
	queue_free()
