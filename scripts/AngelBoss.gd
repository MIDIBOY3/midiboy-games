class_name AngelBoss
extends Node3D

# THE FINAL BOSS before THE GENESIS — a COLOSSAL STANDING IDOL: a great Buddha-like
# angel-god of space carved from golden blocks, with vast golden wings and a radiant
# halo. It STANDS in your way down the whole space column: feet at GROUND_ALT (760),
# crown at ALT_MAX (1000). You CLIMB it by altitude — the body part at your current
# altitude slides to screen-centre (and is the only vulnerable LAYER); the rest of the
# towering figure extends off-screen above/below. Three layers, each with its own HP:
#   LOW  (lotus pedestal + robed legs, 760–840)
#   MID  (torso + mudra hands + the great GOLDEN WINGS, 840–920)
#   HIGH (neck rings + serene face + ushnisha + radiant HALO, 920–1000)
# Whittle each band down with your LEVELED-UP fire (the run's upgrades pay off here). It
# strikes back in self-defense. All three to zero → a great flash → THE GENESIS, and the
# ending rolls (Main._start_ending_cinematic).
#
# Hit detection is SELF-CONTAINED (the layers are NOT in the enemy group): only the
# active-band layer takes the player's bullets, so ramming can't cheese it.

# The idol is laid along the ALTITUDE (depth/Z) axis and ANCHORED in the column — you fly
# THROUGH it: at alt1000 you look straight down on the crown (頭頂部), descend to reach the
# feet at alt760. (X-rotated 90° so the upright Y-model's head→+Z=alt1000, feet→-Z=alt760.)
const SCREEN_Y0 := 0.84          # GOD TUNER approved boss baseline on the screen plane
const Z_ANCHOR := -0.22          # GOD TUNER approved depth anchor
const BODY_SCALE := 0.948        # GOD TUNER approved figure scale
const BODY_ROT_X := 72.0         # GOD TUNER approved depth angle
const DRIFT_X := 0.24            # broad but slow celestial drift around the tuned position
const DRIFT_Y := 0.16
const DRIFT_Z := 0.07
const LAYER_HP := 360            # per-layer hit points (hard — built for a maxed ship)

# Gold / heavenly palette.
const GOLD := Color(0.92, 0.70, 0.18)
const GOLD_HI := Color(1.0, 0.88, 0.45)
const GOLD_DK := Color(0.55, 0.40, 0.10)
const ROBE := Color(0.97, 0.93, 0.82)
const JADE := Color(0.35, 0.85, 0.70)
const HALO := Color(1.0, 0.95, 0.55)
const STONE := Color(0.62, 0.60, 0.66)
const FACE := Color(1.0, 0.93, 0.74)

class Layer extends Node3D:
	var hp: int = LAYER_HP
	var hp_full: int = LAYER_HP
	var hit_radius: float = 1.2
	var lo: float = 760.0
	var hi: float = 840.0
	var mats: Array[StandardMaterial3D] = []
	var base_emit: Array[float] = []
	var dead: bool = false

	func in_band() -> bool:
		return GameState.alt >= lo and GameState.alt < hi

	func set_active(active: bool, pulse: float) -> void:
		for i in mats.size():
			mats[i].emission_energy_multiplier = base_emit[i] * (1.7 + 0.9 * pulse if active else 0.30)

var _t := 0.0
# Pacifist mode: reused as the silent GOD / GENESIS idol in the true-route finale — it descends,
# floats and animates, but never fires, drops, takes damage, or starts the duel.
var pacifist := false
var _layers: Array[Layer] = []   # [low, mid, high]
var _fire_cd := 100
var _attack_phase := 0
var _heal_cd := 54
var _wing_roots: Array[Node3D] = []
var _halo_root: Node3D = null
var _core_mat: StandardMaterial3D = null
var _head_lock_hint_until := 0.0
var _dying := false
var _death_t := 0
var _ended := false
# --- ENTRANCE (舞い降り) ---
# The gate is crossed → the player's guns fall silent, a short HUSH passes, then the boss
# theme swells and GOD descends from high above the screen to its anchored pose. Nothing
# fights until it lands. Phase 0 = hush (figure waits high, all sound cut); phase 1 =
# descent (music playing, figure eases down); phase 2 = the duel proper.
const INTRO_HUSH := 1.4          # seconds of silence before the theme swells
const INTRO_DESCEND := 3.2       # seconds for the slow descent to the anchor
const INTRO_Y_HIGH := 6.6        # screen-Y the figure starts at, high above the view
var _intro_phase := 0
var _intro_t := 0.0
var _settle := 0.0               # 0→1 ease-in of the idle drift after landing (no snap)
# --- Live tuner (press \ to toggle): nudge position/rotation/scale in-game and read the
# values off the screen (and console) to bake into the constants. ---
var _tune := false
var _tune_label: Label = null

func _ready() -> void:
	add_to_group("space_boss")
	add_to_group("angel_boss")
	# Lay the upright Y-built idol along the ALTITUDE/depth axis (X-rotate 90°): the crown
	# points to +Z (alt1000, up toward the high-flying ship), the feet to -Z (alt760). The
	# top-down camera then looks straight DOWN onto the 頭頂部; descend altitude to travel
	# down the body to the feet. Anchored in the column — the player flies THROUGH it.
	rotation_degrees = Vector3(BODY_ROT_X, 0.0, 0.0)
	scale = Vector3.ONE * BODY_SCALE
	_layers.append(_build_legs(760.0, 840.0, -1.95))   # local y → world z (depth) after the rot
	_layers.append(_build_torso(840.0, 920.0, 0.35))
	_layers.append(_build_head(920.0, 1000.1, 2.45))
	# Begin the entrance: hold high above the screen in total silence; the descent and the
	# music are kicked off from _process once the hush passes.
	GameState.boss_intro_active = true
	GameState.boss_intro_hush = true
	position = Vector3(0.0, INTRO_Y_HIGH, Z_ANCHOR)
	_setup_tuner()

# Safety: never leave the entrance locks set if the idol is freed for any reason, or the
# player's guns (and the music) would stay dead forever.
func _exit_tree() -> void:
	GameState.boss_intro_active = false
	GameState.boss_intro_hush = false

# Dissolve the whole idol (used by the pacifist GOD as the FAITH gauge fills). Walks every mesh
# and fades its material to transparent; emission goes with the alpha so the glow fades too.
func set_fade(a: float) -> void:
	_fade_meshes(self, clampf(a, 0.0, 1.0))

func _fade_meshes(node: Node, a: float) -> void:
	for ch in node.get_children():
		if ch is MeshInstance3D:
			var mat := (ch as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var c := sm.albedo_color
				c.a = a
				sm.albedo_color = c
				if sm.emission_enabled:
					sm.emission = Color(sm.emission.r, sm.emission.g, sm.emission.b, a)
		_fade_meshes(ch, a)

func _solid(c: Color, emit: Color, emit_e: float, metal := 0.7, rough := 0.32) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.metallic_specular = 0.9
	m.roughness = rough
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = emit_e
	return m

static var _CUBE: BoxMesh

func _blk(layer: Layer, pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot_z := 0.0) -> MeshInstance3D:
	return _blk_on(layer, layer, pos, size, mat, rot_z)

func _blk_on(parent: Node3D, layer: Layer, pos: Vector3, size: Vector3,
		mat: StandardMaterial3D, rot_z := 0.0) -> MeshInstance3D:
	if _CUBE == null:
		_CUBE = BoxMesh.new()
		_CUBE.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _CUBE                     # one shared unit cube — scale per-instance (voxel build)
	mi.position = pos
	mi.scale = size
	mi.rotation.z = rot_z
	mi.material_override = mat
	parent.add_child(mi)
	layer.mats.append(mat)
	layer.base_emit.append(mat.emission_energy_multiplier)
	return mi

func _new_layer(lo: float, hi: float, ly: float, hit_r: float) -> Layer:
	var L := Layer.new()
	L.lo = lo
	L.hi = hi
	L.hit_radius = hit_r
	L.position = Vector3(0.0, ly, 0.0)
	add_child(L)
	return L

# VOXEL FILL: pack an ellipsoid volume (centre c, radii r) with little cubes of size
# `step` — a real solid mass with depth (front-to-back), like a terrain object. This is
# what makes the idol a true 3D figure (not a flat relief) that can stand and turn.
func _mass(L: Layer, c: Vector3, r: Vector3, step: float, mat: StandardMaterial3D, shell := false) -> void:
	var nx := int(ceil(r.x / step))
	var ny := int(ceil(r.y / step))
	var nz := int(ceil(r.z / step))
	for ix in range(-nx, nx + 1):
		for iy in range(-ny, ny + 1):
			for iz in range(-nz, nz + 1):
				var p := Vector3(float(ix), float(iy), float(iz)) * step
				var e := (p.x / r.x) ** 2 + (p.y / r.y) ** 2 + (p.z / r.z) ** 2
				if e > 1.0:
					continue
				if shell and e < 0.45:
					continue   # hollow core → fewer cubes for big shapes
				_blk(L, c + p, Vector3.ONE * step * 1.04, mat)

# LOW — a tiered LOTUS PEDESTAL and the robed lower body / feet, built solid from cubes.
func _build_legs(lo: float, hi: float, ly: float) -> Layer:
	var L := _new_layer(lo, hi, ly, 1.25)
	var gold := _solid(GOLD, GOLD * 0.55, 0.5)
	var goldhi := _solid(GOLD_HI, GOLD_HI * 0.7, 0.9)
	var stone := _solid(STONE, STONE * 0.4, 0.3, 0.2, 0.7)
	var robe := _solid(ROBE, ROBE * 0.45, 0.5, 0.2, 0.55)
	# Tiered stone base (two solid discs).
	_mass(L, Vector3(0.0, -1.45, 0.0), Vector3(1.7, 0.22, 0.95), 0.34, stone)
	_mass(L, Vector3(0.0, -1.12, 0.0), Vector3(1.45, 0.2, 0.8), 0.34, stone)
	# Lotus: a ring of upturned 3D petals around the rim.
	for i in 11:
		var a := TAU * float(i) / 11.0
		_mass(L, Vector3(cos(a) * 1.2, -0.78 + 0.12 * absf(sin(a)), sin(a) * 0.62),
			Vector3(0.26, 0.34, 0.22), 0.2, goldhi)
	# Robed lower body — a solid rounded mass with carved fold-lines.
	_mass(L, Vector3(0.0, 0.25, 0.0), Vector3(1.05, 0.95, 0.78), 0.3, robe, true)
	for sx: float in [-0.62, -0.2, 0.2, 0.62]:
		_blk(L, Vector3(sx, 0.2, 0.7), Vector3(0.1, 1.3, 0.16), gold)   # gold fold trim
	# Feet (solid) peeking from under the robe, with ankle bands.
	for sx: float in [-1.0, 1.0]:
		_mass(L, Vector3(sx * 0.48, -0.62, 0.42), Vector3(0.3, 0.18, 0.42), 0.16, goldhi)
		_blk(L, Vector3(sx * 0.48, -0.4, 0.32), Vector3(0.46, 0.14, 0.5), gold)
	return L

# MID — a solid torso, shoulders, arms, mudra hands, and the GREAT GOLDEN WINGS (each a
# layered, 3D fan of feather-masses with real front-to-back depth).
func _build_torso(lo: float, hi: float, ly: float) -> Layer:
	var L := _new_layer(lo, hi, ly, 1.7)
	var gold := _solid(GOLD, GOLD * 0.55, 0.5)
	var goldhi := _solid(GOLD_HI, GOLD_HI * 0.8, 1.0)
	var robe := _solid(ROBE, ROBE * 0.5, 0.55, 0.2, 0.5)
	var jade := _solid(JADE, JADE, 1.6, 0.3, 0.3)
	# Solid chest + a gold breast-core + a broad shoulder mass.
	_mass(L, Vector3(0.0, 0.0, 0.05), Vector3(0.95, 0.9, 0.7), 0.26, robe, true)
	_mass(L, Vector3(0.0, 0.15, 0.5), Vector3(0.55, 0.6, 0.3), 0.2, gold)
	_mass(L, Vector3(0.0, 0.85, 0.05), Vector3(1.15, 0.32, 0.62), 0.24, goldhi)
	# Jeweled collar across the shoulders.
	for i in 7:
		_blk(L, Vector3(-0.9 + float(i) * 0.3, 0.62, 0.48), Vector3(0.15, 0.15, 0.15), jade)
	# Mudra: cupped hands at the lap holding a glowing jewel.
	_mass(L, Vector3(0.0, -0.6, 0.55), Vector3(0.5, 0.18, 0.3), 0.18, goldhi)
	_core_mat = _solid(JADE, JADE, 2.4, 0.3, 0.24)
	_blk(L, Vector3(0.0, -0.42, 0.74), Vector3(0.34, 0.34, 0.3), _core_mat)
	for sx: float in [-1.0, 1.0]:
		# Arm (solid).
		_mass(L, Vector3(sx * 0.95, -0.1, 0.05), Vector3(0.24, 0.72, 0.3), 0.22, gold)
		# A GREAT WING: feathers in THREE depth-layers (z) so it's a volumetric wing, not a
		# flat panel — sweeping up-and-out from the shoulder.
		var wing := Node3D.new()
		wing.name = "WingLeft" if sx < 0.0 else "WingRight"
		wing.position = Vector3(sx * 0.95, 0.55, 0.0)
		L.add_child(wing)
		_wing_roots.append(wing)
		for zl in 3:
			var zoff := -0.45 + float(zl) * 0.32
			for f in 7:
				var ft := float(f) / 6.0
				var wx := sx * ft * 2.7
				var wy := -0.40 + ft * 2.0 - float(zl) * 0.12
				var fl := 2.0 - ft * 1.1
				_blk_on(wing, L, Vector3(wx, wy, zoff), Vector3(0.42, fl, 0.3),
					goldhi if (f + zl) % 2 == 0 else gold, sx * (0.45 + ft * 0.55))
	return L

# HIGH — a solid neck and 3D head with a serene face on the FRONT (+Z), an ushnisha crown,
# elongated ears, and a great radiant HALO ring standing behind the head.
func _build_head(lo: float, hi: float, ly: float) -> Layer:
	var L := _new_layer(lo, hi, ly, 1.15)
	var gold := _solid(GOLD, GOLD * 0.55, 0.6)
	var goldhi := _solid(GOLD_HI, GOLD_HI * 0.8, 1.0)
	var halo := _solid(HALO, HALO, 3.2, 0.2, 0.3)
	var face := _solid(FACE, FACE * 0.6, 0.7, 0.25, 0.4)
	var dark := _solid(Color(0.2, 0.15, 0.08), Color(0.1, 0.07, 0.03), 0.2, 0.3, 0.6)
	var eye := _solid(Color(0.55, 0.92, 1.0), Color(0.55, 0.92, 1.0), 3.0, 0.1, 0.2)
	# Radiant halo: separate pivot so the sacred ring can rotate independently of the face.
	_halo_root = Node3D.new()
	_halo_root.name = "LivingHalo"
	_halo_root.position = Vector3(0.0, 0.35, -0.35)
	L.add_child(_halo_root)
	for i in 26:
		var a := TAU * float(i) / 26.0
		_blk_on(_halo_root, L, Vector3(cos(a) * 1.5, sin(a) * 1.5, 0.0),
			Vector3(0.2, 0.2, 0.18), halo, a)
	# Neck (solid).
	_mass(L, Vector3(0.0, -1.05, 0.05), Vector3(0.34, 0.34, 0.34), 0.2, gold)
	# Head (a real solid 3D mass) + hair cap + ushnisha crown-bump.
	_mass(L, Vector3(0.0, -0.2, 0.05), Vector3(0.58, 0.62, 0.58), 0.2, face)
	_mass(L, Vector3(0.0, 0.35, -0.05), Vector3(0.56, 0.34, 0.5), 0.2, dark)
	_mass(L, Vector3(0.0, 0.72, -0.05), Vector3(0.2, 0.24, 0.2), 0.16, goldhi)
	# Face features on the FRONT (+Z): downcast glowing eyes, brows, ears, urna, nose, mouth.
	for sx: float in [-1.0, 1.0]:
		_blk(L, Vector3(sx * 0.24, -0.12, 0.6), Vector3(0.24, 0.07, 0.1), eye)
		_blk(L, Vector3(sx * 0.24, -0.01, 0.58), Vector3(0.28, 0.045, 0.08), dark)
		_mass(L, Vector3(sx * 0.6, -0.2, 0.1), Vector3(0.12, 0.34, 0.16), 0.14, face)  # long earlobe
	_blk(L, Vector3(0.0, 0.12, 0.64), Vector3(0.11, 0.11, 0.09), halo)            # urna jewel
	_blk(L, Vector3(0.0, -0.2, 0.64), Vector3(0.1, 0.26, 0.14), face)            # nose
	_blk(L, Vector3(0.0, -0.46, 0.62), Vector3(0.3, 0.06, 0.1), dark)            # serene mouth
	return L

func _process(delta: float) -> void:
	_t += delta
	# ENTRANCE timeline: runs before any combat. It owns the figure's position (a slow
	# descent from high above), keeps GOD's wings/halo alive for spectacle, but lets nobody
	# fire until the idol lands at its anchor.
	if _intro_phase < 2 and not _tune:
		_update_intro(delta)
		return
	# Anchored in the altitude column (no scroll, no tracking): you fly THROUGH it by changing
	# altitude — alt1000 looks down on the crown (頭頂部), alt760 reaches the feet. Its tuned
	# pose is the centre of a slow celestial dance, not a static display prop.
	if not _tune and not _dying:
		# Ease the celestial drift IN from the exact landed pose so there's no snap at the
		# entrance→duel handoff: at s=0 this is (0, SCREEN_Y0, Z_ANCHOR)/(BODY_ROT_X,0,0),
		# which is precisely where the descent ended.
		_settle = minf(1.0, _settle + delta * 0.5)
		var s := _settle * _settle * (3.0 - 2.0 * _settle)
		position = Vector3(
			(DRIFT_X * sin(_t * 0.31) + DRIFT_X * 0.28 * sin(_t * 0.73 + 1.4)) * s,
			SCREEN_Y0 + DRIFT_Y * sin(_t * 0.25 + 1.1) * s,
			Z_ANCHOR + DRIFT_Z * sin(_t * 0.43 + 2.4) * s
		)
		rotation_degrees = Vector3(
			BODY_ROT_X + sin(_t * 0.27 + 0.8) * 6.5 * s,
			sin(_t * 0.19 + 1.8) * 9.0 * s,
			sin(_t * 0.34) * 5.5 * s
		)
		_animate_sanctuary()
	if _tune:
		_tune_step()

	if _dying:
		_update_dying()
		return

	if pacifist:
		return   # GOD / GENESIS: floats in silence — no layers, no fire, no drops, no damage
	# (set_fade lives below; the pacifist GOD is dissolved by Main during the faith→GENESIS turn.)

	# Active band = the layer you're level with; blaze it, dim the rest.
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var active: Layer = null
	var live := 0
	for L in _layers:
		if is_instance_valid(L) and not L.dead:
			live += 1
			var on := L.in_band()
			L.set_active(on, pulse)
			if on:
				active = L

	if live == 0:
		_begin_dying()
		return

	if active != null:
		_apply_bullet_hits(active)

	# Phase one is a pure ship duel: sustain comes from visible healing crosses, never from
	# a carrier beacon. They enter from above with enough time to be deliberately collected.
	_heal_cd -= 1
	if _heal_cd <= 0:
		_heal_cd = 72 + randi() % 48
		_drop_blessing()

	# Self-defense fire: aimed volleys, faster as it loses layers (cornered → desperate).
	_fire_cd -= 1
	if _fire_cd <= 0:
		_fire_volley(live)
		_fire_cd = 34 + live * 13

# The 舞い降り entrance. Phase 0: hush — the figure waits high above while every voice is
# cut, then the boss theme is released. Phase 1: a slow eased descent from INTRO_Y_HIGH to
# the screen anchor (SCREEN_Y0), wings beating and halo turning the whole way. When it
# lands, the hush/lock lift and the duel begins (phase 2).
func _update_intro(delta: float) -> void:
	_intro_t += delta
	# Keep the sanctuary alive (wings flap, halo spins, core breathes) during the descent.
	_animate_sanctuary()
	if _intro_phase == 0:
		# Hold high, in silence. Slow drift overhead so it doesn't read as a frozen prop.
		position = Vector3(DRIFT_X * 0.4 * sin(_t * 0.6), INTRO_Y_HIGH, Z_ANCHOR)
		rotation_degrees = Vector3(BODY_ROT_X + sin(_t * 0.5) * 4.0, sin(_t * 0.4) * 6.0, 0.0)
		if _intro_t >= INTRO_HUSH:
			# The hush lifts. The combat GOD swells its theme and voices its arrival; the pacifist
			# idol descends in total silence (the finale's god_phase keeps the cosmos quiet).
			GameState.boss_intro_hush = false
			if not pacifist:
				TsgAudio.angel_boss_voice(true)
				get_tree().call_group("star_hud", "show_message",
					"GOD DESCENDS", "...")
			_intro_phase = 1
			_intro_t = 0.0
		return
	# Phase 1: ease the figure down to its anchored pose (smoothstep so it settles gently).
	var p := clampf(_intro_t / INTRO_DESCEND, 0.0, 1.0)
	var e := p * p * (3.0 - 2.0 * p)
	position = Vector3(
		DRIFT_X * 0.4 * sin(_t * 0.6) * (1.0 - e),
		lerpf(INTRO_Y_HIGH, SCREEN_Y0, e),
		Z_ANCHOR)
	rotation_degrees = Vector3(BODY_ROT_X + sin(_t * 0.5) * 4.0 * (1.0 - e),
		sin(_t * 0.4) * 6.0 * (1.0 - e), 0.0)
	# Periodic descending cry so the arrival feels alive, not silent.
	if Engine.get_frames_drawn() % 70 == 0:
		TsgAudio.angel_boss_voice(false)
	if p >= 1.0:
		# Landed at the anchor: combat may begin for both sides.
		GameState.boss_intro_active = false
		_intro_phase = 2
		get_tree().call_group("star_hud", "show_message",
			"GOD BARS THE WAY", "FLY THE COLUMN - STRIKE EACH ALTITUDE (HIGH/MID/LOW)")

# Scan the player's bullets; any within the active layer's screen hit-zone damages it.
func _apply_bullet_hits(active: Layer) -> void:
	var lx := active.global_position.x
	var ly := active.global_position.y
	var rr := active.hit_radius * scale.x
	var r2 := rr * rr
	for b_node in get_tree().get_nodes_in_group("bullets"):
		var b := b_node as Node3D
		if b == null or not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var dx := b.global_position.x - lx
		var dy := b.global_position.y - ly
		if dx * dx + dy * dy > r2:
			continue
		var dmg_v: Variant = b.get("damage")
		var dmg: int = maxi(1, int(dmg_v) if dmg_v != null else 1)
		b.queue_free()
		TsgAudio.enemy_hit()
		var head_sealed := _is_head_layer(active) and _head_is_sealed()
		if head_sealed and active.hp - dmg <= 0:
			# The face can be worn down now, but its last life is protected until the body falls.
			active.hp = 1
			if _t >= _head_lock_hint_until:
				_head_lock_hint_until = _t + 2.5
				get_tree().call_group("star_hud", "show_message",
					"THE CROWN IS SEALED", "BREAK THE BODY AND WINGS FIRST")
		else:
			active.hp -= dmg
		_spark(Vector3(b.global_position.x, b.global_position.y, position.z))
		if active.hp <= 0:
			_kill_layer(active)
			return

func _is_head_layer(layer: Layer) -> bool:
	return _layers.size() >= 3 and layer == _layers[2]

func _head_is_sealed() -> bool:
	for i in 2:
		var body_layer := _layers[i]
		if is_instance_valid(body_layer) and not body_layer.dead:
			return true
	return false

func _animate_sanctuary() -> void:
	# The wings have their own shoulder pivots, so their motion reads as a living body rather
	# than a whole sculpted mesh being rotated. The asymmetry avoids mechanical flapping.
	for i in _wing_roots.size():
		var wing := _wing_roots[i]
		if wing == null or not is_instance_valid(wing):
			continue
		var side := -1.0 if i == 0 else 1.0
		var beat := sin(_t * 1.12 + float(i) * 0.55)
		wing.rotation_degrees = Vector3(beat * 5.0, side * (12.0 + beat * 8.0), side * beat * 3.5)
	if _halo_root != null and is_instance_valid(_halo_root):
		_halo_root.rotation_degrees = Vector3(sin(_t * 0.62) * 5.0, sin(_t * 0.38) * 7.0, _t * 18.0)
		var halo_breath := 1.0 + sin(_t * 1.55) * 0.055
		_halo_root.scale = Vector3.ONE * halo_breath
	if _core_mat != null:
		_core_mat.emission_energy_multiplier = 2.2 + (sin(_t * 3.2) * 0.5 + 0.5) * 2.5

func _kill_layer(L: Layer) -> void:
	L.dead = true
	GameState.score += 1500
	GameState.add_exp(300)
	_blast(L.global_position, 48, 3.4)
	TsgAudio.enemy_destroy()
	TsgAudio.angel_boss_voice(true)
	L.queue_free()

func _fire_volley(live: int) -> void:
	var origin := Vector3(position.x, position.y, GameState.alt_to_z(GameState.alt))
	var to_player := Vector3(GameState.px - origin.x, GameState.py - origin.y, 0.0)
	if to_player.length() < 0.01:
		to_player = Vector3(0, -1, 0)
	var base := to_player.normalized()
	var fury := 4 - live
	match _attack_phase % 3:
		0:
			# JUDGEMENT FAN: a broad golden curtain aimed from the idol's heart.
			var count := 9 + fury * 3
			for i in count:
				var spread := lerpf(-0.70, 0.70, float(i) / float(maxi(1, count - 1)))
				_spawn_bolt(origin, base.rotated(Vector3(0, 0, 1), spread) * (0.032 + fury * 0.004), "divine")
		1:
			# HALO BLOOM: rotating concentric light rings leave lanes to weave through.
			var count := 14 + fury * 3
			var turn := _t * 0.85
			for i in count:
				var a := turn + TAU * float(i) / float(count)
				_spawn_bolt(origin, Vector3(cos(a), sin(a), 0.0) * (0.026 + fury * 0.003), "halo")
		_:
			# HEAVENLY LANCES: a staggered wall bends toward the player but remains dodgeable.
			for i in 7 + fury:
				var off := float(i) - float(6 + fury) * 0.5
				var lance_origin := origin + Vector3(off * 0.22, 0.12 * sin(_t + off), 0.0)
				var lance_dir := Vector3(GameState.px - lance_origin.x, GameState.py - lance_origin.y, 0.0).normalized()
				_spawn_bolt(lance_origin, lance_dir * (0.040 + fury * 0.004), "lance")
	_attack_phase += 1
	TsgAudio.angel_boss_voice(false)

func _spawn_bolt(origin: Vector3, velocity: Vector3, kind: String) -> void:
	var b := EnemyBullet.new()
	b.bullet_type = kind
	b.alt = GameState.alt / GameState.ALT_MAX
	b.velocity = velocity
	get_parent().add_child(b)
	b.global_position = origin

func _drop_blessing() -> void:
	if get_parent() == null:
		return
	var heal := RepairItem.new()
	get_parent().add_child(heal)
	heal.global_position = Vector3(
		clampf(GameState.px + randf_range(-1.25, 1.25), -2.35, 2.35),
		GameState.py + randf_range(1.7, 2.35),
		GameState.alt_to_z(GameState.alt)
	)

# All layers gone → a great escalating explosion, then THE GENESIS / the ending.
func _begin_dying() -> void:
	_dying = true
	_death_t = 0
	get_tree().call_group("star_hud", "show_message",
		"GOD HAS FALLEN", "...AND THE GENESIS DAWNS")
	TsgAudio.boss_destroy()

func _update_dying() -> void:
	_death_t += 1
	if _death_t % 6 == 0 and _death_t < 150:
		var off := Vector3(randf_range(-2.6, 2.6), randf_range(-3.0, 3.0), 0.0)
		_blast(position + off, 42, 3.2)
		TsgAudio.boss_death_blast()   # 連打もBOSS_DESTROY_DBで一括減衰させる(enemy_destroyは対象外だった)
	if _death_t == 150:
		_blast(position, 130, 6.5)   # the great final flash
	if _death_t >= 200 and not _ended:
		_ended = true
		# The idol is only the seal. Its fall reveals THE GENESIS, which owns the actual
		# final carrier duel and is the only fight allowed to start the ending.
		if get_parent() != null and get_parent().has_method("_begin_genesis_battle"):
			get_parent().call_deferred("_begin_genesis_battle")
		queue_free()

func _blast(at: Vector3, count: int, strength: float) -> void:
	var ex := Explosion.new()
	ex.color = GOLD_HI
	ex.count = count
	ex.strength = strength
	get_parent().add_child(ex)
	ex.global_position = at

func _spark(at: Vector3) -> void:
	var ex := Explosion.new()
	ex.color = GOLD_HI
	ex.count = 4
	ex.strength = 0.5
	get_parent().add_child(ex)
	ex.global_position = at

# --- HUD accessors (StarTargets reads these for the 3 layer bars) ---
func layer_count() -> int:
	return _layers.size()

func layer_frac(i: int) -> float:
	if i < 0 or i >= _layers.size() or not is_instance_valid(_layers[i]) or _layers[i].dead:
		return 0.0
	return clampf(float(_layers[i].hp) / float(maxi(1, _layers[i].hp_full)), 0.0, 1.0)

func layer_active(i: int) -> bool:
	return i >= 0 and i < _layers.size() and is_instance_valid(_layers[i]) \
		and not _layers[i].dead and _layers[i].in_band()

# --- Live transform tuner (dev) -------------------------------------------
# Press \ to toggle. Hold the keys to nudge; the on-screen readout (and the console on
# toggle-off) shows the exact pos/rot/scale to bake into Z_ANCHOR / SCREEN_Y0 / BODY_SCALE /
# the _ready rotation. Doesn't touch gameplay (hits use global_position, which follows).
func _setup_tuner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	_tune_label = Label.new()
	_tune_label.position = Vector2(20, 90)
	_tune_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_tune_label.add_theme_font_size_override("font_size", 16)
	_tune_label.visible = false
	layer.add_child(_tune_label)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_BACKSLASH:
		_tune = not _tune
		if _tune_label != null:
			_tune_label.visible = _tune
		if not _tune:
			print("[GOD] pos=(%.3f, %.3f, %.3f)  rot=(%.1f, %.1f, %.1f)  scale=%.3f" % [
				position.x, position.y, position.z,
				rotation_degrees.x, rotation_degrees.y, rotation_degrees.z, scale.x])

func _tune_step() -> void:
	var pd := 0.02    # position units / frame
	var rd := 0.8     # rotation degrees / frame
	var sd := 0.006   # scale / frame
	if Input.is_key_pressed(KEY_LEFT):      position.x -= pd
	if Input.is_key_pressed(KEY_RIGHT):     position.x += pd
	if Input.is_key_pressed(KEY_UP):        position.y += pd
	if Input.is_key_pressed(KEY_DOWN):      position.y -= pd
	if Input.is_key_pressed(KEY_PAGEUP):    position.z += pd
	if Input.is_key_pressed(KEY_PAGEDOWN):  position.z -= pd
	if Input.is_key_pressed(KEY_T):         rotation_degrees.x += rd
	if Input.is_key_pressed(KEY_Y):         rotation_degrees.x -= rd
	if Input.is_key_pressed(KEY_U):         rotation_degrees.y += rd
	if Input.is_key_pressed(KEY_I):         rotation_degrees.y -= rd
	if Input.is_key_pressed(KEY_BRACKETLEFT):  rotation_degrees.z -= rd
	if Input.is_key_pressed(KEY_BRACKETRIGHT): rotation_degrees.z += rd
	if Input.is_key_pressed(KEY_MINUS):     scale -= Vector3.ONE * sd
	if Input.is_key_pressed(KEY_EQUAL):     scale += Vector3.ONE * sd
	var s := maxf(0.05, scale.x)
	scale = Vector3(s, s, s)
	if _tune_label != null:
		_tune_label.text = "GOD TUNER  ( \\ off )\n" \
			+ "pos (%.2f, %.2f, %.2f)\n" % [position.x, position.y, position.z] \
			+ "rot (%.0f, %.0f, %.0f)\n" % [rotation_degrees.x, rotation_degrees.y, rotation_degrees.z] \
			+ "scale %.3f   alt %d\n" % [scale.x, int(GameState.alt)] \
			+ "←→pos.x  ↑↓pos.y  PgUp/Dn pos.z\n" \
			+ "T/Y rot.x  U/I rot.y  [ / ] rot.z  - / = scale"
