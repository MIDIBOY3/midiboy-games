class_name Mothership
extends Node3D

# Giant friendly carrier — terrain-like: frames in from the top and scrolls
# through to the bottom (fast; even faster once the player has taken a unit).
# It gently follows the player's lateral movement so the deck is easy to ride.
#
# Riding: enter by matching altitude (±10) over the deck → the player sinks to
# a special deck-skim altitude (camera follows), altitude control is locked,
# life repairs. The deck is a SAFE ZONE (AA guns kill intruding enemies and
# bullets). Express lanes flank the runway (2,3 left / 4,5 right): riding one
# scrolls the carrier past fast, and that lane's unit waits on a pad at its
# bow end — take ONE, then the player auto-climbs back to the entry altitude
# while the carrier speeds away.

const DECK_LEN := 5.0
const DECK_W := 2.2
const SCROLL := 0.008
const DEPART_BOOST := 3.5
const REPAIR_MIN := 0.3    # life/frame at the runway edge
const REPAIR_MAX := 1.4    # life/frame on the centerline
const ZONE_ALT := 25.0
# Express lanes flanking the runway: 2,3 on the left / 4,5 on the right.
# Riding a lane scrolls the carrier past at LANE_BOOST speed, and the lane's
# unit waits on a pad at its bow end — pick your lane, grab your unit, gone.
const LANE_W := 0.44
const LANE_BOOST := 3.2
const LANE_X := {2: -2.20, 3: -1.76, 4: 1.76, 5: 2.20}
const FULL_HALF_W := 2.42  # runway + all lanes (boarding / AA-zone footprint)
# Side utility strips between the runway and the inner express lanes. They no
# longer launch or enter planets; altitude alone handles planet travel.
const LAUNCH_X := 1.32
const LAUNCH_W := 0.40
const LAUNCH_FRAMES := 120
# Deck-skim altitude offset: high enough that no ship mesh sinks into the deck.
const SKIM_ALT := 4.0
# Landing band: the deck line is the FLOOR; the player may board from up to
# ENTRY_ABOVE higher (the carrier is conceptually beneath the player).
const ENTRY_BELOW := 2.0
const ENTRY_ABOVE := 15.0
# How long the carrier waits off-screen for the player to come to its band.
const WAIT_LIMIT := 1800

var ship_alt: float = 250.0   # surface-air band (200..300)
var auto_engage: bool = false  # spawned as the player's ride: engaged at once
var _t: int = 0
var _engaged: bool = false   # stays off-screen until the player enters the band
var _boost_mode: String = ""  # "enter"/"exit"/"arrive": flying a transition
var _rider_off := Vector2.ZERO  # ship's deck position relative to the carrier
# Arrival cinematic: "planet" = shrink in from screen-filling (atmosphere
# descent), "space" = rise from below while growing (orbit climb). The ship
# is locked to the runway rear the whole way.
var arrive_from: String = ""
var _arrive_t: int = 0
var _arrive_init: bool = false
var _arrive_target := Vector3.ZERO
var _offered: Array = []
var _gave_unit: bool = false
var _entry_alt: float = 50.0
var _releasing: bool = false
var _release_t: int = 0

# Final boss (stage C) carrier-pilot battle.
const BATTLE_SCALE := 0.45   # the carrier shrinks as it descends to the boss
const BATTLE_INTRO := 120    # frames to shrink/descend into the fight
const BATTLE_DPS := 0.28     # boss life drained per frame by the beam
const BATTLE_FOLLOW := 0.025 # mouse-follow lerp — LOW = heavy/sluggish carrier
var _battle_init := false
var _battle_t := 0
var _battle_alt := 0.0       # altitude frozen for the duration (stable camera plane)
var _beam: MeshInstance3D = null
var _beam_mat: StandardMaterial3D = null
# Stage D: after the kill the carrier lifts away (the hero ship has detached and now
# descends into the homeworld on its own — Main handles the homeworld + ending).
var _departing := false
var _depart_t := 0
# Title intro: frame in from the bottom with the ship on the deck, then it takes off.
const INTRO_REST_Y := -1.6
const INTRO_RISE_FRAMES := 100
const INTRO_TAKEOFF_FRAMES := 80
var intro := false
var _intro_t := 0

var _launch_t: int = 0
var _upgrade_cd: int = 0   # paces resource→durability/Golden purchases while docked
var _dash_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _repair_mat: StandardMaterial3D
var _launch_mat: StandardMaterial3D
var _repair_marks: Array[Node3D] = []
# Tiny navigation-lamp materials (blink on offset phases in _process for a lively
# string-of-lights look): red = port, green = starboard, white = strobe, amber = deck.
var _nav_red: StandardMaterial3D
var _nav_grn: StandardMaterial3D
var _nav_wht: StandardMaterial3D
var _nav_amb: StandardMaterial3D
var _conduit_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("mothership")
	_engaged = auto_engage
	_build_meshes()
	if arrive_from != "":
		_boost_mode = "arrive"
		_rider_off = Vector2(0.0, -(DECK_LEN * 0.5 - 0.8))  # central runway rear
		GameState.boost_ship = self
		GameState.arrive_lock = true

func _build_meshes() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.32, 0.36, 0.46)
	hull.metallic = 0.6
	hull.roughness = 0.4
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.46, 0.5, 0.56)
	deck.metallic = 0.45
	deck.roughness = 0.45
	var deck_hi := StandardMaterial3D.new()
	deck_hi.albedo_color = Color(0.56, 0.6, 0.66)
	deck_hi.metallic = 0.4
	deck_hi.roughness = 0.45
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.66, 0.74)
	steel.metallic = 0.7
	steel.roughness = 0.32
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.92, 0.95)
	white.metallic = 0.2
	white.roughness = 0.5
	_dash_mat = StandardMaterial3D.new()
	_dash_mat.albedo_color = Color(0.5, 0.95, 1.0)
	_dash_mat.emission_enabled = true
	_dash_mat.emission = Color(0.45, 0.9, 1.0)
	_dash_mat.emission_energy_multiplier = 1.4
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = Color(0.4, 1.0, 0.6)
	_edge_mat.emission_enabled = true
	_edge_mat.emission = Color(0.35, 1.0, 0.55)
	_edge_mat.emission_energy_multiplier = 1.2
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.25, 0.15)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.25, 0.15)
	_beacon_mat.emission_energy_multiplier = 2.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.9, 1.0)
	glass.metallic = 0.0
	glass.roughness = 0.05
	glass.emission_enabled = true
	glass.emission = Color(0.4, 0.85, 1.0)
	glass.emission_energy_multiplier = 1.2
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(1.0, 0.8, 0.35)
	pad.emission_enabled = true
	pad.emission = Color(1.0, 0.75, 0.3)
	pad.emission_energy_multiplier = 1.0
	# Surface detailing materials: dark panel seams, glowing data conduits, amber lamps.
	var panel := StandardMaterial3D.new()
	panel.albedo_color = Color(0.22, 0.25, 0.32)
	panel.metallic = 0.6
	panel.roughness = 0.45
	_conduit_mat = StandardMaterial3D.new()
	_conduit_mat.albedo_color = Color(0.3, 0.95, 1.0)
	_conduit_mat.emission_enabled = true
	_conduit_mat.emission = Color(0.3, 0.95, 1.0)
	_conduit_mat.emission_energy_multiplier = 3.0
	var conduit := _conduit_mat
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(1.0, 0.7, 0.2)
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.65, 0.18)
	amber.emission_energy_multiplier = 3.2
	# Bright bean-grain nav lamps. Vivid albedo + strong emission so each reads as a
	# crisp point of light; they blink on staggered phases in _process.
	_nav_red = _lamp_mat(Color(1.0, 0.15, 0.12))
	_nav_grn = _lamp_mat(Color(0.2, 1.0, 0.3))
	_nav_wht = _lamp_mat(Color(0.95, 0.98, 1.0))
	_nav_amb = _lamp_mat(Color(1.0, 0.72, 0.2))
	# Brighten the existing electricals so the whole hull glows harder.
	_dash_mat.emission_energy_multiplier = 2.2
	_edge_mat.emission_energy_multiplier = 1.8

	# Hull mass + deck + runway strip
	_add_box(Vector3(2.3, 5.1, 0.12), Vector3(0, 0, -0.09), hull)
	_add_box(Vector3(DECK_W, DECK_LEN, 0.08), Vector3.ZERO, deck)
	_add_box(Vector3(1.0, 4.8, 0.084), Vector3.ZERO, deck_hi)
	_add_box(Vector3(1.8, 0.5, 0.07), Vector3(0, -DECK_LEN * 0.5 - 0.2, -0.02), hull)   # stern ramp
	_add_box(Vector3(1.4, 0.55, 0.07), Vector3(0, DECK_LEN * 0.5 + 0.22, -0.02), hull)  # bow block

	# Runway markings: stern threshold stripes + centerline dashes
	for i in 5:
		_add_box(Vector3(0.8, 0.07, 0.088), Vector3(0, -2.15 + float(i) * 0.16, 0), white)
	for i in 8:
		_add_box(Vector3(0.07, 0.4, 0.09), Vector3(0, -1.6 + float(i) * 0.45, 0), _dash_mat)

	# Edge light rails + side sponsons
	_add_box(Vector3(0.05, 4.6, 0.095), Vector3(-DECK_W * 0.5 + 0.07, 0, 0), _edge_mat)
	_add_box(Vector3(0.05, 4.6, 0.095), Vector3(DECK_W * 0.5 - 0.07, 0, 0), _edge_mat)
	_add_box(Vector3(0.2, 4.2, 0.07), Vector3(-1.25, 0, -0.01), steel)
	_add_box(Vector3(0.2, 4.2, 0.07), Vector3(1.25, 0, -0.01), steel)

	# Island tower (starboard, outboard of all lanes) with glowing
	# bridge, antenna and blinking beacon
	_add_box(Vector3(0.3, 1.2, 0.09), Vector3(2.70, 0.7, -0.02), hull)  # tower sponson
	_add_box(Vector3(0.26, 0.8, 0.26), Vector3(2.70, 0.7, 0.14), hull)
	_add_box(Vector3(0.28, 0.2, 0.07), Vector3(2.70, 0.85, 0.3), glass)
	_add_box(Vector3(0.025, 0.025, 0.34), Vector3(2.63, 1.05, 0.32), steel)
	_add_box(Vector3(0.06, 0.06, 0.06), Vector3(2.63, 1.05, 0.52), _beacon_mat)

	# AA turrets on the four corners (the lore behind the safe zone)
	for corner: Vector2 in [Vector2(-0.95, 2.2), Vector2(0.95, 2.2), Vector2(-0.95, -2.2), Vector2(0.95, -2.2)]:
		_add_box(Vector3(0.14, 0.14, 0.1), Vector3(corner.x, corner.y, 0.06), steel)
		var bdir := 1.0 if corner.y > 0.0 else -1.0
		_add_box(Vector3(0.03, 0.26, 0.03), Vector3(corner.x - 0.032, corner.y + bdir * 0.16, 0.1), hull)
		_add_box(Vector3(0.03, 0.26, 0.03), Vector3(corner.x + 0.032, corner.y + bdir * 0.16, 0.1), hull)

	# --- Fine surface detailing: panel seams, data conduits, deck electronics ---
	# Panel seam grid across the central deck (thin recessed dark lines).
	for gy in 9:
		_add_box(Vector3(1.9, 0.018, 0.082), Vector3(0, -2.0 + float(gy) * 0.5, 0.0), panel)
	for gx: float in [-0.72, -0.36, 0.36, 0.72]:
		_add_box(Vector3(0.018, 4.8, 0.082), Vector3(gx, 0, 0.0), panel)
	# Glowing data conduits running fore-aft just inboard of the edge rails,
	# with cross-rungs every half unit for a "circuit board" read.
	for cx: float in [-DECK_W * 0.5 + 0.17, DECK_W * 0.5 - 0.17]:
		_add_box(Vector3(0.028, 4.4, 0.09), Vector3(cx, 0, 0.0), conduit)
		for k in 9:
			_add_box(Vector3(0.11, 0.026, 0.09), Vector3(cx, -2.0 + float(k) * 0.5, 0.0), conduit)
	# Machinery clusters on the clear stern & bow hull blocks: gear boxes, vent
	# grilles, amber status lamps and whip antennae (kept off the runway/lanes).
	for cy2: float in [-2.62, 2.66]:
		for sx2: float in [-0.55, -0.18, 0.18, 0.55]:
			_add_box(Vector3(0.2, 0.22, 0.12), Vector3(sx2, cy2, 0.04), steel)          # gear box
			_add_box(Vector3(0.22, 0.04, 0.13), Vector3(sx2, cy2 - 0.09, 0.05), panel)  # vent grille
			_add_box(Vector3(0.035, 0.035, 0.05), Vector3(sx2 + 0.07, cy2 + 0.07, 0.11), amber)  # status lamp
			_add_box(Vector3(0.02, 0.02, 0.2), Vector3(sx2 - 0.07, cy2, 0.15), steel)   # whip antenna
	# Sensor dome + second mast/beacon by the island tower.
	_add_box(Vector3(0.16, 0.16, 0.16), Vector3(2.70, -0.2, 0.12), steel)
	_add_box(Vector3(0.13, 0.13, 0.04), Vector3(2.70, -0.2, 0.22), glass)
	_add_box(Vector3(0.02, 0.02, 0.18), Vector3(2.55, 1.05, 0.30), steel)
	_add_box(Vector3(0.05, 0.05, 0.05), Vector3(2.55, 1.05, 0.46), _beacon_mat)
	# --- Bean-grain navigation lamps: dense strings of tiny blinking lights ---
	# Edge running lights: a double row down each flank — RED to port (-x),
	# GREEN to starboard (+x), nautical convention. Fine spacing = "string of pearls".
	var n_edge := 34
	for k in n_edge:
		var ry := -DECK_LEN * 0.5 + 0.2 + float(k) * (DECK_LEN - 0.4) / float(n_edge - 1)
		_lamp(Vector3(-DECK_W * 0.5 + 0.02, ry, 0.07), _nav_red, 0.022)
		_lamp(Vector3(-DECK_W * 0.5 + 0.10, ry, 0.065), _nav_red, 0.018)
		_lamp(Vector3(DECK_W * 0.5 - 0.02, ry, 0.07), _nav_grn, 0.022)
		_lamp(Vector3(DECK_W * 0.5 - 0.10, ry, 0.065), _nav_grn, 0.018)
	# Centreline strobe lamps studding the runway dashes (white).
	for k in 22:
		_lamp(Vector3(0.0, -2.1 + float(k) * 0.2, 0.075), _nav_wht, 0.02)
	# Amber lamps marching along both data conduits (circuit nodes).
	for cx: float in [-DECK_W * 0.5 + 0.17, DECK_W * 0.5 - 0.17]:
		for k in 19:
			_lamp(Vector3(cx, -2.1 + float(k) * 0.225, 0.1), _nav_amb, 0.02)
	# Tiny lamps tracing each express-lane edge rail, in the lane's own colour.
	for uid2: int in LANE_X:
		var lx2: float = LANE_X[uid2]
		var lcm := _lamp_mat(PowerOrb.UNIT_COLORS[uid2])
		for k in 16:
			var ly2 := -DECK_LEN * 0.5 + 0.3 + float(k) * (DECK_LEN - 0.6) / 15.0
			_lamp(Vector3(lx2 - LANE_W * 0.5 + 0.03, ly2, 0.12), lcm, 0.018)
			_lamp(Vector3(lx2 + LANE_W * 0.5 - 0.03, ly2, 0.12), lcm, 0.018)
	# Crown the bow & stern blocks and the island mast with white marker lamps.
	for bx: float in [-0.6, -0.2, 0.2, 0.6]:
		_lamp(Vector3(bx, DECK_LEN * 0.5 + 0.22, 0.06), _nav_wht, 0.022)
		_lamp(Vector3(bx, -DECK_LEN * 0.5 - 0.2, 0.06), _nav_red, 0.022)

	# Express lanes: outboard support decks, then per-lane strip, colored edge
	# rails, dashes, big lane numbers, and the unit pickup pad at the bow end.
	var lane_deck := StandardMaterial3D.new()
	lane_deck.albedo_color = Color(0.36, 0.40, 0.47)
	lane_deck.metallic = 0.5
	lane_deck.roughness = 0.5
	_add_box(Vector3(1.35, DECK_LEN * 0.92, 0.1), Vector3(-1.78, 0, -0.06), hull)
	_add_box(Vector3(1.35, DECK_LEN * 0.92, 0.1), Vector3(1.78, 0, -0.06), hull)
	for uid: int in LANE_X:
		var lx: float = LANE_X[uid]
		var lc: Color = PowerOrb.UNIT_COLORS[uid]
		_add_box(Vector3(LANE_W, DECK_LEN * 0.92, 0.072), Vector3(lx, 0, -0.004), lane_deck)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = lc
		lmat.emission_enabled = true
		lmat.emission = lc
		lmat.emission_energy_multiplier = 1.3
		_add_box(Vector3(0.04, DECK_LEN * 0.88, 0.08), Vector3(lx - LANE_W * 0.5 + 0.03, 0, 0), lmat)
		_add_box(Vector3(0.04, DECK_LEN * 0.88, 0.08), Vector3(lx + LANE_W * 0.5 - 0.03, 0, 0), lmat)
		for i in 4:
			_add_box(Vector3(0.05, 0.3, 0.082), Vector3(lx, -1.7 + float(i) * 1.0, 0), lmat)
		for ly: float in [-DECK_LEN * 0.5 + 0.45, 0.6]:
			var lbl := Label3D.new()
			lbl.text = str(uid)
			lbl.font_size = 160
			lbl.pixel_size = 0.002
			lbl.outline_size = 28
			lbl.modulate = lc
			lbl.no_depth_test = true
			lbl.position = Vector3(lx, ly, 0.07)
			add_child(lbl)
		_add_box(Vector3(0.3, 0.3, 0.086), Vector3(lx, DECK_LEN * 0.5 - 0.3, 0), pad)

	# Lv-lane markings: the strips flanking the runway are the DURABILITY-upgrade lane —
	# ride one to spend mined resources on durability (elsewhere they just accrue).
	_launch_mat = StandardMaterial3D.new()
	_launch_mat.albedo_color = Color(1.0, 0.86, 0.32)
	_launch_mat.emission_enabled = true
	_launch_mat.emission = Color(1.0, 0.78, 0.22)
	_launch_mat.emission_energy_multiplier = 1.4
	for lsx: float in [-LAUNCH_X, LAUNCH_X]:
		_add_box(Vector3(LAUNCH_W, DECK_LEN * 0.92, 0.072), Vector3(lsx, 0, -0.003), lane_deck)
		_add_box(Vector3(0.035, DECK_LEN * 0.88, 0.08),
			Vector3(lsx - LAUNCH_W * 0.5 + 0.025, 0, 0), _launch_mat)
		_add_box(Vector3(0.035, DECK_LEN * 0.88, 0.08),
			Vector3(lsx + LAUNCH_W * 0.5 - 0.025, 0, 0), _launch_mat)
		# Forward-pointing chevrons, built left-right symmetric like the space
		# dash-panel arrows: both arms share the SAME y, mirrored x and rotation,
		# so the apex sits dead-centre instead of staggered.
		for i in 5:
			var cy := -1.9 + float(i) * 0.95
			for sgn: float in [-1.0, 1.0]:
				var seg := MeshInstance3D.new()
				var sb := BoxMesh.new()
				sb.size = Vector3(0.18, 0.045, 0.085)
				seg.mesh = sb
				seg.material_override = _launch_mat
				seg.position = Vector3(lsx + sgn * 0.088, cy, 0.0)
				seg.rotation_degrees.z = -38.0 * sgn
				add_child(seg)
		for ly: float in [-DECK_LEN * 0.5 + 0.45, 0.6]:   # match the lane 2-5 label positions
			var llbl := Label3D.new()
			llbl.text = "Lv"
			llbl.font_size = 160
			llbl.pixel_size = 0.0015                       # a touch smaller so "Lv" fits the strip
			llbl.outline_size = 28
			llbl.modulate = Color(1.0, 0.9, 0.45)
			llbl.no_depth_test = true
			llbl.position = Vector3(lsx, ly, 0.07)
			add_child(llbl)

	# Repair conveyor: green medic crosses flowing up the runway — the
	# "this strip heals you" signal. They glow harder while the player rides.
	_repair_mat = StandardMaterial3D.new()
	_repair_mat.albedo_color = Color(0.35, 1.0, 0.55)
	_repair_mat.emission_enabled = true
	_repair_mat.emission = Color(0.3, 1.0, 0.5)
	_repair_mat.emission_energy_multiplier = 1.2
	for i in 3:
		var holder := Node3D.new()
		holder.position = Vector3(0, -1.6 + float(i) * 1.2, 0)
		add_child(holder)
		var h := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.34, 0.09, 0.087)
		h.mesh = hb
		h.material_override = _repair_mat
		holder.add_child(h)
		var v := MeshInstance3D.new()
		var vb := BoxMesh.new()
		vb.size = Vector3(0.09, 0.34, 0.0885)
		v.mesh = vb
		v.material_override = _repair_mat
		holder.add_child(v)
		_repair_marks.append(holder)

func _add_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = pos
	add_child(m)

# Bright emissive material for a bean-grain nav lamp.
func _lamp_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.4
	return m

# One tiny lamp (a ~2cm glowing cube sitting just above the deck).
func _lamp(pos: Vector3, mat: StandardMaterial3D, sz: float = 0.024) -> void:
	_add_box(Vector3(sz, sz, sz), pos, mat)

func _contains(p: Vector2) -> bool:
	return absf(p.x - global_position.x) < FULL_HALF_W \
		and absf(p.y - global_position.y) < DECK_LEN * 0.5

# Which express lane (uid 2-5) is under this world x — 0 for none/runway.
func _lane_uid(px: float) -> int:
	var dx := px - global_position.x
	for uid: int in LANE_X:
		if absf(dx - float(LANE_X[uid])) < LANE_W * 0.5:
			return uid
	return 0

func _process(_delta: float) -> void:
	_t += 1

	# Any non-offering mode (transition flight, finale battle, departing, intro): the
	# pads stop tracking the hull, so drop pending pickups — otherwise a waiting unit
	# freezes in world space, gets left behind by the scrolling deck, and stays
	# collectable (a free second unit).
	if intro or _boost_mode != "" or GameState.carrier_battle or _departing:
		_clear_my_offers()

	# Title intro: this carrier frames in from the bottom with the ship on its deck,
	# then the ship takes off and the carrier climbs out — then normal play begins.
	if intro:
		_run_intro()
		return

	# Booster flight: carrying the transition, then gone. The arrival-side
	# carrier is spawned fresh by the stage-switch code.
	if _boost_mode == "arrive":
		_run_arrive()
		return
	if _boost_mode != "":
		_run_boost()
		return

	# Final boss (stage C): once boarded during FINAL_BOSS, this carrier becomes the
	# player-piloted weapon. After the kill the hero ship detaches (stage D) and the
	# carrier lifts away while the player descends into the homeworld on their own.
	if GameState.carrier_battle:
		_run_battle()
		return
	if _departing:
		_run_depart()
		return

	# Fixed terrain: the carrier never tracks the player. It waits off-screen
	# (only the HUD band marker shows) and frames in once the player moves
	# into its altitude band — so the player is never underneath it.
	if not _engaged:
		var da := GameState.alt - ship_alt
		if da >= -ENTRY_BELOW and da <= ENTRY_ABOVE and not GameState.game_over:
			_engaged = true
			_t = 0
		elif _t > WAIT_LIMIT:
			queue_free()
		return

	# Express-lane riding blasts the carrier past at LANE_BOOST speed.
	var boost := 1.0
	if _gave_unit:
		boost = DEPART_BOOST
	elif GameState.on_carrier and _lane_uid(GameState.px) != 0:
		boost = LANE_BOOST
	position.y -= SCROLL * boost
	# In space the camera pans with the player while riding, so settle the hull
	# toward screen-center x: that keeps both outer express lanes symmetric and
	# within reach (the random spawn offset would otherwise push one off-edge).
	if GameState.stage == "space" and not _gave_unit:
		position.x = lerpf(position.x, 0.0, 0.03)
	if position.y < -(3.0 + DECK_LEN):
		queue_free()
		return

	var pulse := 0.5 + 0.5 * sin(_t * 0.12)
	_edge_mat.emission_energy_multiplier = 1.4 + pulse * 1.0
	_beacon_mat.emission_energy_multiplier = 3.0 if (_t % 60) < 12 else 0.8

	# Bean-grain nav lamps blink on offset phases for a lively running-light shimmer.
	if _nav_red != null:
		_nav_red.emission_energy_multiplier = 1.2 + 2.4 * (0.5 + 0.5 * sin(_t * 0.20))
		_nav_grn.emission_energy_multiplier = 1.2 + 2.4 * (0.5 + 0.5 * sin(_t * 0.20 + PI))
		_nav_amb.emission_energy_multiplier = 1.0 + 2.6 * (0.5 + 0.5 * sin(_t * 0.26 + 1.7))
		_nav_wht.emission_energy_multiplier = 4.5 if (_t % 26) < 4 else 0.6   # crisp strobe
		_conduit_mat.emission_energy_multiplier = 2.2 + 1.4 * sin(_t * 0.16)

	# Repair conveyor flows toward the bow; glows hard while the player rides.
	for m in _repair_marks:
		m.position.y += 0.014
		if m.position.y > DECK_LEN * 0.5 - 0.4:
			m.position.y = -DECK_LEN * 0.5 + 0.4
	var heal_pulse := 0.5 + 0.5 * sin(_t * 0.3)
	_repair_mat.emission_energy_multiplier = \
		(2.2 + heal_pulse * 1.8) if GameState.on_carrier else (0.9 + heal_pulse * 0.5)

	_update_zone()
	_update_player_on_deck()
	_update_offers()
	_update_launch()

# The flanking strips used to trigger planet entry/exit. Planet travel is now
# altitude-driven, so the carrier never starts atmosphere transitions.
func _update_launch() -> void:
	var lane_lit := GameState.on_carrier and not GameState.in_transition() \
		and not GameState.game_over \
		and absf(absf(GameState.px - global_position.x) - LAUNCH_X) < LAUNCH_W * 0.5
	_launch_t = 0
	if GameState.launch_count > 0.0 and not GameState.in_transition():
		GameState.launch_count = 0.0
	_launch_mat.emission_energy_multiplier = \
		(1.8 + 0.9 * sin(_t * 0.24)) if lane_lit else (0.9 + 0.4 * sin(_t * 0.1))

func _begin_boost(mode: String) -> void:
	_launch_t = 0
	GameState.launch_count = 0.0
	GameState.on_carrier = false
	_boost_mode = ""
	# Kept only as a harmless fallback for old callers; planet travel no longer
	# uses carrier boost.
	_rider_off = Vector2(GameState.px - global_position.x,
		GameState.py - global_position.y)
	GameState.boost_ship = null

# Arrival cinematic: the ship starts ON the carrier. Entering a planet the
# carrier fills the screen and shrinks down into place; back in space it
# rises from below the screen, growing as it climbs. The whole way the ship
# is bolted to the runway rear; on settling, deck riding takes over and the
# mouse warps onto the ship.
func _run_arrive() -> void:
	if not _arrive_init:
		_arrive_init = true
		_arrive_target = global_position
		if arrive_from == "planet":
			scale = Vector3.ONE * 3.2
			global_position.y = _arrive_target.y + 0.6
		else:
			scale = Vector3.ONE * 0.4
			global_position.y = _arrive_target.y - 5.0
	_arrive_t += 1
	var k := clampf(float(_arrive_t) / 130.0, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	if arrive_from == "planet":
		scale = Vector3.ONE * lerpf(3.2, 1.0, e)
		global_position.y = lerpf(_arrive_target.y + 0.6, _arrive_target.y, e)
	else:
		scale = Vector3.ONE * lerpf(0.4, 1.0, e)
		global_position.y = lerpf(_arrive_target.y - 5.0, _arrive_target.y, e)
	GameState.px = global_position.x + _rider_off.x * scale.x
	GameState.py = global_position.y + _rider_off.y * scale.x
	GameState.vx = 0.0
	GameState.vy = 0.0
	# Ease the player's altitude toward the deck-skim height across the WHOLE
	# cinematic, so the camera depth (player_z) glides into place. Snapping it
	# at the handover (orbit altitude → deck height in one frame) was the
	# boarding/leaving stutter.
	GameState.tAlt = lerpf(GameState.tAlt, ship_alt + SKIM_ALT, 0.05)
	GameState.alt = GameState.tAlt
	if k >= 1.0:
		arrive_from = ""
		_boost_mode = ""
		GameState.arrive_lock = false
		if GameState.boost_ship == self:
			GameState.boost_ship = null
		# Seamless handover: already riding the deck (altitude already eased
		# to the deck-skim height above), mouse warps onto the ship.
		GameState.on_carrier = true
		GameState.tAlt = ship_alt + SKIM_ALT
		GameState.deck_start = true

# The carrier IS the booster: on entry it dives ahead, shrinking into the
# atmosphere; on exit it lifts away above the screen. Once the transition
# finishes, the arrival-side carrier replaces it.
func _run_boost() -> void:
	if _boost_mode == "enter":
		# Zoom toward the (centred, swelling) star: shrink into the distance while
		# converging on screen-centre, so the carrier reads as flying INTO the
		# planet ahead rather than dropping out of frame.
		position.x = lerpf(position.x, 0.0, 0.04)
		position.y = lerpf(position.y, 0.1, 0.03)
		scale *= 0.978
		rotation_degrees.x = lerpf(rotation_degrees.x, -10.0, 0.05)  # nose toward it
		_spawn_cloud_sea()
	else:
		position.y += 0.022
		scale *= 1.004
		rotation_degrees.x = lerpf(rotation_degrees.x, 14.0, 0.05)   # nose lifts away
	# Carry the ship: it stays bolted to its deck spot (offset shrinks with
	# the hull) for the whole ride.
	GameState.px = global_position.x + _rider_off.x * scale.x
	GameState.py = global_position.y + _rider_off.y * scale.x
	GameState.vx = 0.0
	GameState.vy = 0.0
	var pulse := 0.5 + 0.5 * sin(_t * 0.5)
	_launch_mat.emission_energy_multiplier = 3.0 + pulse * 2.0
	if not GameState.in_transition():
		queue_free()

# The cloud sea the carrier slips through on the way down: a few soft 3D puffs
# per frame, spread across the view at depths straddling the carrier so it weaves
# BETWEEN them (some pass in front, some behind) as it dives, then they sweep
# past the lens. Real geometry, not a screen overlay.
func _spawn_cloud_sea() -> void:
	return
	# Hold the clouds until the star is almost full-screen (entry_glow ramps in
	# only over the last ~45% of the dive). Before that the carrier just rushes
	# at the growing star with a clear view; THEN the cloud sea billows up.
	if GameState.entry_glow < 0.2:
		return
	# Biased to the SIDES and lower band so the (centred) planet stays visible and
	# the clouds rush PAST it rather than blanketing it.
	var tint: Color = GameState.entry_tint.lerp(Color(1, 1, 1), 0.55)
	var side := 1.0 if randf() < 0.5 else -1.0
	var puff := CloudPuff.new()
	puff.tint = tint
	puff.scale = Vector3.ONE * randf_range(0.8, 1.8)
	puff.vel = Vector3(side * randf_range(0.004, 0.016),
		randf_range(-0.07, -0.04), randf_range(0.014, 0.03))
	get_tree().current_scene.add_child(puff)
	puff.global_position = Vector3(
		global_position.x + side * randf_range(0.8, 3.0),
		global_position.y + randf_range(-0.4, 2.2),
		global_position.z + randf_range(-1.7, 1.7))

# The deck is an AA-protected safe zone: enemies and their bullets entering
# the carrier's footprint (within its altitude band) are shot down.
func _update_zone() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Node3D
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var ea: Variant = e.get("alt")
		if ea != null and absf(float(ea) * GameState.ALT_MAX - ship_alt) > ZONE_ALT:
			continue
		if _contains(Vector2(e.global_position.x, e.global_position.y)):
			# Carrier AA kill: score only, no exp (no farming).
			GameState.score += 100
			var ex := Explosion.new()
			ex.color = Color(0.6, 1.0, 0.7)
			get_parent().add_child(ex)
			ex.global_position = e.global_position
			e.queue_free()
	for node in get_tree().get_nodes_in_group("enemy_bullets"):
		var eb := node as Node3D
		if eb == null or not is_instance_valid(eb) or eb.is_queued_for_deletion():
			continue
		if _contains(Vector2(eb.global_position.x, eb.global_position.y)):
			eb.queue_free()

# Stage C: the player pilots the carrier against the space boss. The carrier is
# mouse-steered but SLUGGISH (low follow lerp), shrinks and descends into the fight,
# and auto-fires a giant beam that drains the boss. Camera/units are handled in
# Unit1/Main (gated on GameState.carrier_battle). Runs at high process_priority so
# its px/py bolt wins over Unit1's mouse steering → the camera follows the carrier.
func _run_battle() -> void:
	if not _battle_init:
		_battle_init = true
		_battle_t = 0
		_battle_alt = GameState.alt
		# Decouple from the deck-ride flow: no zoom-in, no repair, normal space camera.
		GameState.on_carrier = false
		GameState.arrive_lock = false
		GameState.boost_ship = null
		process_priority = 100
		_build_beam()
	_battle_t += 1
	# Freeze altitude so the play plane (and camera depth) stays put.
	GameState.alt = _battle_alt
	GameState.tAlt = _battle_alt
	var play_z := GameState.alt_to_z(_battle_alt)
	# Shrink + descend into the fight over the intro.
	var k := clampf(float(_battle_t) / float(BATTLE_INTRO), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	scale = Vector3.ONE * lerpf(1.0, BATTLE_SCALE, e)
	# Sluggish mouse follow within the play plane.
	var camera := get_viewport().get_camera_3d()
	var target := Vector2(global_position.x, -1.8)
	if camera != null:
		var depth: float = camera.global_position.z - play_z
		var wp := camera.project_position(get_viewport().get_mouse_position(), depth)
		target = Vector2(clampf(wp.x, -2.6, 2.6), clampf(wp.y, -2.4, 0.8))
	global_position.x = lerpf(global_position.x, target.x, BATTLE_FOLLOW)
	global_position.y = lerpf(global_position.y, target.y, BATTLE_FOLLOW)
	global_position.z = play_z
	# Bolt the camera focus to the carrier, and tell Unit1 where to park itself on the
	# deck (visible, scaled to the carrier) so the hero ship rides along through to the end.
	GameState.px = global_position.x
	GameState.py = global_position.y
	GameState.vx = 0.0
	GameState.vy = 0.0
	GameState.carrier_dock_pos = global_position + Vector3(0.0, 0.18 * scale.y, 0.3 * scale.z)
	GameState.carrier_dock_scale = scale.x
	# Auto-fire the beam at the boss and drain it; after the kill, stay aboard (the
	# carrier keeps flying — stage D carries on to the homeworld/ending).
	var boss := get_tree().get_first_node_in_group("space_boss") as SpaceBoss
	if GameState.god_phase > 0:
		# True route: do NOT harm THE GENESIS. The beam is replaced by a stream of scattered
		# resources (Main._update_god_offering drains SCORE + sparkles). Hide the destructive beam.
		if _beam != null:
			_beam.visible = false
	elif boss != null and is_instance_valid(boss) and boss.alive:
		_aim_beam(boss.global_position)
		TsgAudio.carrier_beam()
		boss.take_carrier_damage(BATTLE_DPS)
		if not boss.alive:
			_kill_boss(boss)
	elif _beam != null:
		_beam.visible = false

# Stage D: after the kill the carrier lifts up and away (the hero ship has detached
# and now descends into the homeworld on its own — Main spawns the homeworld star and
# runs the auto-land + ending). The carrier just frames out and frees itself.
# Title → game intro. (1) Frame in from the bottom with the ship on the deck. (2) The
# carrier stops while the ship takes off to flight centre; control hands over (alt1000).
# (3) Like a normal carrier departure, the carrier frames out the bottom and despawns —
# the player is already flying by then.
func _run_intro() -> void:
	_intro_t += 1
	if _intro_t <= INTRO_RISE_FRAMES:
		# Phase 1: rise into view from below; ship rides the deck centre.
		GameState.alt = GameState.ALT_MAX
		GameState.tAlt = GameState.ALT_MAX
		global_position.z = GameState.alt_to_z(GameState.ALT_MAX)
		var k := float(_intro_t) / float(INTRO_RISE_FRAMES)
		var e := k * k * (3.0 - 2.0 * k)
		global_position.x = 0.0
		global_position.y = lerpf(-6.0, INTRO_REST_Y, e)
		GameState.px = 0.0
		GameState.py = global_position.y + 0.15
		GameState.vx = 0.0
		GameState.vy = 0.0
	elif _intro_t <= INTRO_RISE_FRAMES + INTRO_TAKEOFF_FRAMES:
		# Phase 2: carrier STOPPED; the ship lifts off the deck to flight centre.
		GameState.alt = GameState.ALT_MAX
		GameState.tAlt = GameState.ALT_MAX
		var k2 := clampf(float(_intro_t - INTRO_RISE_FRAMES) / float(INTRO_TAKEOFF_FRAMES), 0.0, 1.0)
		GameState.px = 0.0
		GameState.py = lerpf(INTRO_REST_Y + 0.15, 0.4, k2 * k2)
		GameState.vx = 0.0
		GameState.vy = 0.0
		if _intro_t >= INTRO_RISE_FRAMES + INTRO_TAKEOFF_FRAMES:
			GameState.intro_active = false   # hand control to the player at alt1000
			# Warp the cursor onto the ship's takeoff spot so control resumes there
			# (no position jump to wherever the mouse happens to be).
			GameState.deck_start = true
	else:
		# Phase 3: the carrier frames out the bottom (player already in control — don't
		# touch px/py/alt here).
		global_position.y -= 0.05
		if global_position.y < -7.0:
			queue_free()

func _run_depart() -> void:
	_depart_t += 1
	position.y += 0.06
	scale *= 1.012
	rotation_degrees.x = lerpf(rotation_degrees.x, 14.0, 0.04)
	if _depart_t > 120:
		queue_free()

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_beam.mesh = bm
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = Color(0.7, 0.95, 1.0)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(0.6, 0.95, 1.0)
	_beam_mat.emission_energy_multiplier = 6.0
	_beam.material_override = _beam_mat
	# World-space (parented to Main) so it isn't shrunk by the carrier's scale.
	get_parent().add_child(_beam)

# Stretch the beam box from the carrier nose to the boss; local -Z faces the target
# (look_at), so scaling Z spans the gap.
func _aim_beam(boss_pos: Vector3) -> void:
	if _beam == null:
		return
	_beam.visible = true
	var from := global_position
	var to := boss_pos
	var dir := to - from
	var len: float = dir.length()
	_beam.global_position = (from + to) * 0.5
	if len > 0.001:
		_beam.look_at(to, Vector3.UP)
	var w := 0.16 + 0.05 * sin(_t * 0.8)
	_beam.scale = Vector3(w, w, len)
	_beam_mat.emission_energy_multiplier = 5.0 + 2.0 * sin(_t * 0.9)

# Boss destroyed: huge blast, drop the beam, and DETACH the hero ship — carrier_battle
# ends so the player resumes normal flight. Main spawns the homeworld star; the player
# descends into it like any star (paced by them) → auto-land + ending. Carrier flies off.
func _kill_boss(boss: Node3D) -> void:
	GameState.final_phase = GameState.FINAL_ENDING
	GameState.carrier_battle = false
	GameState.on_carrier = false
	if _beam != null:
		_beam.queue_free()
		_beam = null
	var bp := boss.global_position
	TsgAudio.boss_destroy()
	# One big white-hot core + a ring of debris bursts (kept modest to avoid a spike).
	var big := Explosion.new()
	big.color = Color(1.0, 0.9, 0.7)
	big.count = 28
	big.strength = 3.6
	get_parent().add_child(big)
	big.global_position = bp
	for i in 8:
		var ex := Explosion.new()
		ex.color = Color(0.7, 1.0, 0.6) if (i % 2 == 0) else Color(1.0, 0.5, 0.3)
		ex.count = 16
		ex.strength = randf_range(1.6, 3.0)
		get_parent().add_child(ex)
		ex.global_position = bp + Vector3(
			randf_range(-2.4, 2.4), randf_range(-2.4, 2.4), randf_range(-1.6, 1.6))
	boss.queue_free()
	# The carrier lifts away; Main rolls the hands-off ending (descent + crawl).
	_departing = true
	_depart_t = 0
	get_parent().call("_start_ending_cinematic")

# Riding rules: on entry the player sinks to the deck-skim altitude (special
# carrier altitude, camera follows); altitude stays locked while aboard and
# life repairs. After taking a unit, the ship departs STRAIGHT — altitude is
# held steady at the deck-skim height (never descends into the hull) while the
# carrier boosts away beneath, then control hands back.
func _update_player_on_deck() -> void:
	if _releasing:
		GameState.alt = GameState.tAlt  # frozen: no climb/dive on departure
		_release_t += 1
		if _release_t > 60:
			_releasing = false
			GameState.on_carrier = false
		return

	var over := _contains(Vector2(GameState.px, GameState.py))
	if GameState.on_carrier:
		# Leaving the runway sideways is always allowed (repair-only visits).
		if not over or GameState.game_over:
			GameState.on_carrier = false
			return
		# Deck-skim just above the runway (high enough not to clip the deck).
		GameState.tAlt = lerpf(GameState.tAlt, ship_alt + SKIM_ALT, 0.15)
		GameState.alt = GameState.tAlt
		# During a takeover event the deck systems are offline: NO repair, NO upgrades
		# until the boarders are cleared (DeckWalkMode).
		if not GameState.carrier_takeover:
			# Repair is strongest on the runway centerline.
			var center_t := 1.0 - clampf(absf(GameState.px - global_position.x) / (DECK_W * 0.5), 0.0, 1.0)
			var rate := REPAIR_MIN + (REPAIR_MAX - REPAIR_MIN) * center_t
			for i in 5:
				if (i + 1) in GameState.collected_units:
					GameState.unit_life[i] = minf(GameState.life_cap(), GameState.unit_life[i] + rate)
			_process_upgrades()
	else:
		var da := GameState.alt - ship_alt
		if over and da >= -ENTRY_BELOW and da <= ENTRY_ABOVE and not GameState.game_over:
			GameState.on_carrier = true
			_entry_alt = GameState.alt
			# Landing during the final boss = take the helm — but ONLY for a carrier-strike
			# boss (has take_carrier_damage). The AngelBoss is killed by the ship's own fire,
			# so docking there is just a normal repair stop, not a battle. The true-route Genesis
			# offering (god_phase) also takes the helm — there the beam scatters resources, not damage.
			if GameState.final_phase == GameState.FINAL_BOSS or GameState.god_phase > 0:
				var sb := get_tree().get_first_node_in_group("space_boss")
				if sb != null and sb.has_method("take_carrier_damage"):
					GameState.carrier_battle = true

# The ship is parked on the dedicated "Lv lane" — the flanking side strips (±LAUNCH_X).
# DURABILITY is bought ONLY here, so on the runway centre / lanes 2-5 resources just
# accrue (free to bank with カナ or spend on mercs with ヒカリ) instead of auto-upgrading.
func _on_lv_lane() -> bool:
	return absf(absf(GameState.px - global_position.x) - LAUNCH_X) < LAUNCH_W * 0.55

# Docked at the carrier and standing on the Lv lane, the deck crew converts mined common
# resources into DURABILITY (every unit's max life). One step every ~0.4s so each purchase
# announces itself instead of all firing on the same frame.
func _process_upgrades() -> void:
	if _upgrade_cd > 0:
		_upgrade_cd -= 1
		return
	if not _on_lv_lane():
		return   # off the Lv lane → no durability spend; resources stay for bank / mercs
	if GameState.dura_level < GameState.DURA_MAX \
			and GameState.res_pool >= GameState.dura_cost():
		GameState.res_pool -= GameState.dura_cost()
		GameState.dura_level += 1
		# Top everyone off to the new, higher cap as a reward.
		for i in 5:
			if (i + 1) in GameState.collected_units:
				GameState.unit_life[i] = GameState.life_cap()
		_upgrade_cd = 24
		get_tree().call_group("star_hud", "show_message",
			"%s LV %d" % [Loc.t("DURABILITY"), GameState.dura_level],
			"%s %d  /  %s" % [
				Loc.t("MAX LIFE"),
				int(GameState.life_cap()),
				Loc.t("TERRAIN ATTACK WIDENED"),
			])
		return

# All not-owned units wait on the exit pads (bow). One pickup per pass;
# taking one starts the auto-climb and the carrier's departure boost.
func _update_offers() -> void:
	var fm := _fm()
	if fm == null:
		return
	# New units are locked while the carrier is under takeover (clear the boarders
	# first). HIDE any units already waiting on the pads — otherwise they freeze in
	# world space, get left behind by the scrolling deck, and stay collectable.
	if GameState.carrier_takeover:
		for uid in _offered:
			fm._available.erase(uid)
		return
	if _gave_unit:
		return
	for uid in [2, 3, 4, 5]:
		if uid in fm._collected:
			continue
		if uid not in _offered:
			_offered.append(uid)
		fm._available[uid] = _slot_pos(uid)
	for uid in _offered.duplicate():
		if uid in fm._collected:
			_gave_unit = true
			for o in _offered:
				if o != uid:
					fm._available.erase(o)
			_offered.clear()
			if GameState.on_carrier:
				_releasing = true
				_release_t = 0
			break

# Each unit waits at the bow end of its own express lane. Lane offsets are LOCAL, so
# they must follow the hull scale (e.g. the planet-arrival cinematic) or the pickups
# drift off their pads and overhang the deck.
func _slot_pos(uid: int) -> Vector3:
	return global_position + Vector3(
		float(LANE_X[uid]) * scale.x,
		(DECK_LEN * 0.5 - 0.3) * scale.y,
		0.06)

# Live deck-pad world position for a unit this carrier is currently offering, or null
# if it isn't (one already taken / under boarding / not on the pads). FormationManager
# reads this so a waiting pickup stays locked to the scrolling deck.
func offered_slot_pos(uid: int) -> Variant:
	if _gave_unit or GameState.carrier_takeover or uid not in _offered:
		return null
	return _slot_pos(uid)

# Remove THIS carrier's pending pickups from the shared pool (only its own _offered
# uids, so other sources — e.g. the boss arena — are untouched). Used whenever the
# carrier stops offering so no pickup is left frozen on screen and re-collectable.
func _clear_my_offers() -> void:
	if _offered.is_empty():
		return
	var fm := _fm()
	if fm != null:
		for uid in _offered:
			fm._available.erase(uid)
	_offered.clear()

func _fm() -> Node:
	return get_parent().get_node_or_null("FormationManager")

func _exit_tree() -> void:
	GameState.on_carrier = false
	GameState.launch_count = 0.0
	if GameState.boost_ship == self:
		GameState.boost_ship = null
		GameState.arrive_lock = false
	var fm := _fm()
	if fm != null:
		for uid in _offered:
			fm._available.erase(uid)
