extends Node3D

const HumanoidAssetScript := preload("res://scripts/HumanoidAsset.gd")

# Deck-walk hub mode (project-deck-hub-mode) — INTEGRATED into the live game.
#
# NOT a separate scene: while the player is riding the carrier deck (on_carrier),
# clicking lands the ship and disembarks the pea-sized pilots (one per owned unit)
# to walk the deck. The whole tree is PAUSED — a combat lull / 実質ポーズ — and the
# same top-down space camera just zooms in a little. Walk to a deck edge and the
# existing starfield shows beyond the rails. Click the parked ship (自機) to return.
#
# This node lives in Main with process_mode = ALWAYS, so it keeps running (camera,
# pilots, input) while everything else is paused. Pilots are its children, placed
# in world XY at the deck's depth plane and moved directly here.
#
# Controls while walking:
#   Mouse        — steer the lead pilot (the rest follow in a trail)
#   Combat       — automatic: standing in an enemy's attack circle, the pilots open fire
#   Left click   — lead on/near the ship: board & resume; near a crew member: talk / repair
#   Right / Esc  — board & resume
#
# Entering is gated to AFTER the ship has settled onto the carrier with the ride
# zoom (on_carrier held for SETTLE_FRAMES) — not just any time the carrier is visible.

const ZOOM_DIST := 1.2      # camera distance from the deck plane while walking — close
							 # enough to read a cockpit-sized pilot (user: "そこまで寄っていい")
const WALK_ZOOM_STEP := 0.12
const WALK_ZOOM_MIN := -0.45
const WALK_ZOOM_MAX := 1.20
const ENTER_LERP := 0.1      # camera zoom-in easing
const PILOT_SIZE := 0.028    # cockpit-exit sized, but readable from the deck camera
const PERSON_DECK_FOOT_Z := 0.090 # deck sits on the carrier mesh: enough clearance for full shadow
const PERSON_FOOT_Z := 0.026      # interior floors: lower so people read grounded
const MAX_SPEED := 0.012     # bounded top speed (analog-stick friendly — no pointer jumps)
const ACCEL := 0.16          # velocity smoothing toward the desired speed (lower = smoother)
const STOP_DEADZONE := 0.06  # cursor within this of the pilot (screen centre) → stop
const STOP_DECEL := 0.45     # harder braking lerp when stopping (vs ACCEL when moving)
const FOLLOW_SPACING := 0.058 # gap kept between pilots in the train (scaled with people)
const EDGE_MARGIN := 0.07    # how close to the rail a pilot may walk
const SHIP_EXIT_R := 0.35    # lead pilot within this of the parked ship → board & resume
const SETTLE_FRAMES := 30    # on_carrier must hold this long (ride zoom settled) before disembark
const BULLET_SPEED := 0.06   # deck-bullet travel per frame
const BULLET_LIFE := 70      # frames before a deck-bullet expires
const BULLET_HIT_R := 0.12   # deck-bullet → enemy hit radius
const FIRE_INTERVAL := 8     # frames between autofire shots while the button is held
const NAV_ARROW_SIZE := 0.02 # ship-locator arrow apex length (small)
const CREW_COUNT := 12       # ambient crew bustling about the deck
const CREW_SPEED := 0.003    # crew wander speed (slow — easy to walk up to & click)
const CREW_SIZE := 0.025     # crew cube edge
const BOARDER_SIZE := 0.040  # takeover-enemy cube edge (bigger than pilots/crew)
const BOARDER_SPEED := 0.005 # boarder advance speed
const BOARDER_HP := 7        # human-type enemies are tough too (固め)
# Attack circles: a pilot inside an enemy's circle auto-fires at it (no click).
const ATTACK_R_BOARDER := 0.3
const ATTACK_R_ZAKO := 0.5
# Real-time intruder (independent of the takeover event): rarely, ONE life-size enemy
# (an actual game character, ship-scale) flies in and lands on the runway. It's tough —
# the pea-sized pilots have to chip it down.
const RAID_MIN_CD := 1800    # frames of deck-walk before an intruder can land (rare)
const RAID_MAX_CD := 3600
const ZAKO_HP := 150         # VERY tough — a long pounding to crack
const ZAKO_SPEED := 0.02     # fly-in speed
const ZAKO_VISUAL_SCALE := 1.2  # ship-sized (自機サイズ感) — tune in editor
const ZAKO_TYPES := ["invader", "fighter", "saucer", "diver", "crab"]
const ZAKO_DEPLOY_DELAY := 50   # frames after landing before enemy pilots disembark
const RAID_PILOTS := 2          # enemy pilots a landed intruder drops
const RAIDER_HP := 60           # enemy pilots are very tough too
const SHIP_CLEAR := 0.5         # keep the intruder's landing at least this far from the ship
# Defeated deck enemies drop salvage the pilots collect (feeds carrier repair).
const RES_PER_ZAKO := 24
const RES_PER_RAIDER := 8
const DROP_PICKUP_R := 0.1      # lead pilot within this collects a salvage cube
const DROP_MAGNET_R := 0.4      # within this, the cube drifts toward the lead
# --- Hired-gun mercenaries (GameState.mercs) walking the deck ---
const MERC_SIZE := 0.038        # a size up from pilots/crew (一回り大きい) — burly guards
const MERC_SPEED := 0.006       # patrol/advance speed (a touch faster than the crew)
const MERC_ENGAGE_R := 0.7      # spots & charges any deck enemy within this
const MERC_FIRE_R := 0.42       # opens fire once this close to its target
const MERC_FIRE_CD := 14        # frames between a merc's shots
const MERC_STANDOFF := 0.2      # holds at this range so it doesn't walk into the enemy
const MERC_HURT_R := 0.12       # an enemy this close chips the merc's HP
const MERC_HURT_DPS := 0.5      # HP lost per frame while an enemy is adjacent
const TALK_R := 0.13         # lead pilot within this of a crew → can talk
const REPAIR_COST := 12      # resources spent per repair chunk
const REPAIR_AMOUNT := 12.0  # carrier hull restored per repair (a chunk — never a full heal)
const REPAIR_CD := 240       # frames before the same engineer can repair again
# --- Carrier interior (command room) — descend below deck via the stern elevator ---
const INTERIOR_DROP := 1.6   # world Z the interior floor sits below the deck plane
const INTERIOR_ZOOM := 1.5  # camera distance above the floor — pulled back a bit so a
							 # wider span of the maze reads at once (still discovery-paced)
const INTERIOR_HW := 3.0     # interior half-width
const INTERIOR_HL := 3.2     # interior half-length
const MAZE_CELL := 0.4       # (legacy) prop-sizing unit
const MAZE_WT := 0.05        # interior wall half-thickness
# --- Fixed below-deck layout (replaces the old random maze) — a central corridor from the
# stern lift lobby up to the bow command room, flanked by 3 rooms per side (6 区画). ---
const CORR_HW := 0.55        # corridor half-width (the central hall up the spine)
const ROOM_INNER := 0.55     # |x| of each room's corridor-facing (inner) wall
const ROOM_OUTER := 2.8      # |x| of each room's outer wall
const ROOM_BOT := -1.6       # bottom of the 3-row room band (local y)
const ROOM_TOP := 1.9        # top of the room band (meets the command room)
const ROOM_DOOR_HALF := 0.34 # half-width of a room's corridor doorway
const CMD_Y0 := 1.9          # command room: bottom (shared with the corridor mouth)
const CMD_Y1 := 2.95         # command room: top
const CMD_HW := 1.6          # command room half-width
const WALL_PAD := 0.03       # walls fattened by this for collision (pilot half-size) so
							 # the point can't clip corners / slip diagonal gaps
const LOBBY_R := 1.05        # radius of the open entrance lobby cleared around the lift
const TRANS_FRAMES := 80     # frames of the descend / ascend lift cinematic (~1.3s)
const HATCH_Y_OFF := 0.55    # elevator pad offset from the stern toward the bow
const HATCH_HALF := 0.3      # elevator pad / hatch door half-size
const ELEV_R := 0.32         # lead pilot within this of the pad → standing on the lift
const INTERIOR_STAFF := 24   # ambient crew milling about the interior (lively / bustling)

# --- Hot spring (温泉) — descend AGAIN from the bow of the command room ---
const ONSEN_DROP := 1.6      # onsen floor sits this far below the command-room floor
const ONSEN_ZOOM := 1.7      # camera pulled back a touch — the bath hall is large & moody
const ONSEN_HW := 3.4        # onsen hall half-width (bigger than the maze above)
const ONSEN_HL := 3.6        # onsen hall half-length
const ONSEN_ENTRY_R := 0.9   # radius cleared around the onsen stair in the maze above
const ONSEN_BATHERS := 10    # tiny bathers soaking in the tubs (ambient life)

var _carrier: Node3D = null
var _cam: Camera3D = null
var _pilots: Array[Node3D] = []
var _bullets: Array = []     # active deck-bullets: {mi: MeshInstance3D, vel: Vector3, life: int}
var _on_carrier_frames := 0  # how long on_carrier has held (ride-zoom settle gate)
var _left_ship := false      # lead has walked clear of the ship → boarding is armed
var _fire_cd := 0            # frames until the next autofire shot
var _deck_labels: Array[Node] = []  # deck Label3D (UNIT / lane numbers): depth-test re-enabled while walking
var _nav_arrow: MeshInstance3D = null    # gold arrow pointing back to the parked ship
var _enemy_arrow: MeshInstance3D = null  # red arrow pointing at the nearest deck enemy
var _crew: Array[Node3D] = []       # ambient NPC crew wandering the deck (decoration)
var _mercs: Array[Node3D] = []      # hired-gun NPCs (GameState.mercs): patrol, talk, FIGHT
var _boarders: Array[Node3D] = []   # ALL deck enemies (meta "kind": boarder/zako/raider)
var _drops: Array[Node3D] = []      # salvage cubes dropped by defeated enemies
var _raid_cd := 0                   # frames until the next real-time intruder raid
var _dialogue: Label = null         # crew speech bubble (Japanese)
var _dialogue_until := 0.0          # real-time seconds when the speech bubble hides
var _hull_label: Label = null       # carrier hull / resources readout while walking
var _merc_label: Label = null       # hired-gun roster (count + names), shown below deck
var _game_hud: CanvasLayer = null   # the flight HUD (AltGauge/StarTargets), hidden while walking
var _talking_to: Node3D = null      # crew the lead auto-stopped at to converse (null = walking)
var _deck_z := 0.0           # world z of the deck plane the pilots stand on
var _pilot_z := 0.0          # pilots sit slightly toward the camera so they read on top
var _walk_zoom_offset := 0.0 # mouse-wheel camera height shared by every carrier floor
var _hidden_space_nodes: Array[Dictionary] = [] # outside combat visuals hidden while aboard
var _hint: Label = null
# Carrier interior (command room) state.
var _floor := 0                      # 0 = deck, 1 = command room, 2 = hot spring
var _transition := ""                # "" / "descend" / "ascend" — lift cinematic running
var _trans_t := 0
var _trans_from_floor := 0           # floor the current lift cinematic departs
var _trans_to_floor := 0             # floor the current lift cinematic arrives at
var _active_pad := Vector3.ZERO      # world XY of the pad the current cinematic rides
var _trans_cam_from := Vector3.ZERO   # camera pose captured at the start of a lift
var _interior_z := 0.0
var _interior_pilot_z := 0.0
var _interior_root: Node3D = null
var _staff: Array[Node3D] = []        # ambient command-room crew (decoration)
var _interior_vips: Array[Node3D] = []  # interactive below-deck VIPs (ヒカリ商人 / カナ博士)
var _glass_stars: Array[Node3D] = []  # (unused) legacy glass-floor star specks
var _walls: Array[Rect2] = []         # interior partition walls (world XY) — solid to pilots
var _interior_lights: Array[Node3D] = []  # pulsing accent lights for the interior glow
var _interior_props: Array[Node3D] = []   # animated corridor props (spinning holo-glyphs)
# Hot-spring (onsen) floor — built lazily on first descent from the command room.
var _onsen_z := 0.0
var _onsen_pilot_z := 0.0
var _onsen_root: Node3D = null
var _onsen_walls: Array[Rect2] = []   # onsen partition + tub-rim collision (world XY)
var _onsen_lights: Array[Node3D] = [] # warm pulsing lanterns
var _steam: Array[Node3D] = []        # drifting steam puffs rising off the tubs
var _bathers: Array[Node3D] = []      # tiny bobbing bathers soaking in the tubs
var _tubs: Array = []                 # soakable tubs: {x,y,hx,hy,wz} in world space
var _ripples: Array[Node3D] = []      # expanding ripple rings around soaking pilots
var _on_onsen_pad := false            # lead is standing on the onsen stair
var _onsen_soak_done := false         # 慢心 already cleared this dip (re-arms when you leave)
var _resting := false                 # bath hall: lead is parked (click toggles) to soak still
const ONSEN_WATER_SHADER := preload("res://shaders/onsen_water.gdshader")
var _hatch_root: Node3D = null
var _hatch_doors: Array[Node3D] = []
var _hatch_open := 0.0                # 0 closed .. 1 fully open
var _on_pad := false                  # lead pilot is standing on the elevator pad

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hint()
	_build_nav_arrow()

# --- Enter / exit ---------------------------------------------------------

func _can_enter() -> bool:
	# Only once the ship has actually settled onto the deck with the ride zoom in
	# (on_carrier held for SETTLE_FRAMES) — not just whenever the carrier is on screen.
	if not (GameState.on_carrier and _on_carrier_frames >= SETTLE_FRAMES):
		return false
	if GameState.deck_walk or GameState.in_transition() or GameState.arrive_lock \
			or GameState.carrier_battle or GameState.game_over \
			or GameState.title_active or GameState.intro_active or GameState.reticle_hover:
		return false
	# The carrier must exist and NOT be mid-departure (taking a unit / releasing the ship),
	# or we'd disembark just as the ship flies off → pilots stuck on a leaving carrier.
	var c := get_tree().get_first_node_in_group("mothership")
	if c == null:
		return false
	if bool(c.get("_releasing")) or bool(c.get("_gave_unit")) or bool(c.get("_departing")):
		return false
	return true

func _enter() -> void:
	_carrier = get_tree().get_first_node_in_group("mothership") as Node3D
	_cam = get_viewport().get_camera_3d()
	if _carrier == null or _cam == null:
		return
	GameState.deck_walk = true
	_left_ship = false
	_talking_to = null
	# Hide the flight HUD (score / life bars / route map) so the deck guide and crew
	# tags don't collide with it; restored on exit.
	_game_hud = get_parent().get_node_or_null("HUD") as CanvasLayer
	if _game_hud != null:
		_game_hud.visible = false
	# The deck's signage (UNIT / lane numbers) draws with no_depth_test → always on top,
	# covering the tiny pilots. Re-enable depth testing while walking so the pilots
	# (closer to the camera, opaque) occlude the text where they overlap, but the text
	# stays visible everywhere else. Restored on exit.
	_deck_labels.clear()
	for c in _carrier.get_children():
		if c is Label3D:
			(c as Label3D).no_depth_test = false
			_deck_labels.append(c)
	var sz := get_viewport().get_visible_rect().size
	if _hint != null:
		_hint.visible = true
		_hint.text = Loc.pair(
			"敵の攻撃サークルに入ると自動攻撃   乗組員に近づいてクリックで会話/修理(再クリックで終了)   自機に戻ってクリック or ESC:発進",
			"Auto-fire inside enemy attack circles   Click crew to talk/repair   Click ship or ESC: launch")
		_hint.position = Vector2(sz.x * 0.5 - 360.0, sz.y - 70.0)
	if _hull_label != null:
		_hull_label.visible = true
	if _dialogue != null:
		_dialogue.position = Vector2(sz.x * 0.5 - 240.0, sz.y - 150.0)
		_dialogue.size = Vector2(480.0, 70.0)
		_dialogue.visible = false
	_deck_z = _carrier.global_position.z
	_pilot_z = _deck_z + PERSON_DECK_FOOT_Z
	_interior_z = _deck_z - INTERIOR_DROP
	_interior_pilot_z = _interior_z + PERSON_FOOT_Z * _person_floor_scale(1)
	_onsen_z = _interior_z - ONSEN_DROP
	_onsen_pilot_z = _onsen_z + PERSON_FOOT_Z * _person_floor_scale(2)
	_walk_zoom_offset = 0.0
	_floor = 0
	_on_onsen_pad = false
	_transition = ""
	_hatch_open = 0.0
	_on_pad = false
	_build_hatch()
	_raid_cd = randi_range(RAID_MIN_CD, RAID_MAX_CD)
	_spawn_pilots()
	_spawn_crew()
	_sync_deck_mercs()       # one hired-gun NPC per GameState.mercs entry
	TsgAudio.pickup(false)   # SE: disembark onto the deck
	if GameState.carrier_takeover:
		_spawn_boarders()
	_hide_space_combat_visuals()
	get_tree().paused = true   # combat lull: gameplay freezes...
	_set_background_paused(false)  # ...but the starfield keeps drifting under the deck

func _exit_mode() -> void:
	GameState.deck_walk = false
	_talking_to = null
	_resting = false
	# Require a fresh settle before re-entering: a click right after boarding (while the
	# carrier is leaving) must NOT instantly re-disembark.
	_on_carrier_frames = 0
	if _hull_label != null:
		_hull_label.visible = false
	if _merc_label != null:
		_merc_label.visible = false
	if _dialogue != null:
		_dialogue.visible = false
	if _game_hud != null and is_instance_valid(_game_hud):
		_game_hud.visible = true
	_restore_space_combat_visuals()
	_set_background_paused(true)
	get_tree().paused = false   # Unit1 resumes and eases the camera back out on its own
	for p in _pilots:
		p.queue_free()
	_pilots.clear()
	for c in _crew:
		c.queue_free()
	_crew.clear()
	for mc in _mercs:
		mc.queue_free()
	_mercs.clear()
	for bd in _boarders:
		bd.queue_free()
	_boarders.clear()
	for d in _drops:
		d.queue_free()
	_drops.clear()
	for b: Dictionary in _bullets:
		(b["mi"] as Node).queue_free()
	_bullets.clear()
	for lbl in _deck_labels:
		if is_instance_valid(lbl):
			(lbl as Label3D).no_depth_test = true
	_deck_labels.clear()
	if _nav_arrow != null:
		_nav_arrow.visible = false
	if _enemy_arrow != null:
		_enemy_arrow.visible = false
	# Restore the deck and tear down the interior / elevator (in case we left from below).
	if _carrier != null and is_instance_valid(_carrier):
		_carrier.visible = true
	_floor = 0
	_transition = ""
	_teardown_interior()
	_teardown_onsen()
	_teardown_hatch()
	_carrier = null

# Keep the space background scrolling while the rest of the tree is paused (paused=false
# arg → run always; true → back to inheriting the tree pause).
func _set_background_paused(p: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if p else Node.PROCESS_MODE_ALWAYS
	for bg in get_tree().get_nodes_in_group("space_background"):
		(bg as Node).process_mode = mode

func _hide_space_combat_visuals() -> void:
	_restore_space_combat_visuals()
	for grp in ["enemies", "enemy_bullets", "bullets", "player_projectiles", "space_boss"]:
		for node in get_tree().get_nodes_in_group(grp):
			if node is Node3D and is_instance_valid(node):
				var n := node as Node3D
				_hidden_space_nodes.append({"node": n, "visible": n.visible})
				n.visible = false

func _restore_space_combat_visuals() -> void:
	for rec: Dictionary in _hidden_space_nodes:
		var node := rec.get("node", null) as Node3D
		if node != null and is_instance_valid(node):
			node.visible = bool(rec.get("visible", true))
	_hidden_space_nodes.clear()

# --- Pilots ---------------------------------------------------------------

func _spawn_pilots() -> void:
	var units: Array = GameState.collected_units
	var n: int = maxi(units.size(), 1)
	var origin := Vector3(GameState.px, GameState.py, _pilot_z)     # disembark from the ship
	for i in n:
		# Each pilot wears its unit's color (Unit1 ≈ white); color is the only per-unit cue.
		var uid: int = units[i] if i < units.size() else ((i % 5) + 1)
		var pilot := _make_pilot(PowerOrb.UNIT_COLORS.get(uid, Color.WHITE))
		add_child(pilot)
		pilot.global_position = origin + Vector3(0.0, -float(i) * FOLLOW_SPACING, 0.0)
		pilot.set_meta("vel", Vector3.ZERO)
		pilot.set_meta("dir", Vector3(0, 1, 0))   # last travel direction (for firing)
		pilot.set_meta("col", PowerOrb.UNIT_COLORS.get(uid, Color.WHITE))
		_pilots.append(pilot)

func _make_pilot(tint: Color) -> Node3D:
	return HumanoidAssetScript.make_figure(tint, PILOT_SIZE * 1.45, "pilot")

# A really small triangular nose/beak poking just past the body so you can read which way a
# figure is heading (oriented each frame by _orient_nose). Used by EVERY person — pilots,
# deck crew, command-room staff. `r` is the body's ball radius.
func _add_nose(root: Node3D, r: float, tint: Color) -> void:
	var nose := MeshInstance3D.new()
	var nm := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(r * 1.38, 0.0, 0.0),       # tip just barely out front (tiny)
		Vector3(r * 0.55, r * 0.4, 0.0),  # base corners
		Vector3(r * 0.55, -r * 0.34, 0.0)])
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	nose.mesh = nm
	var nmat := StandardMaterial3D.new()
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	nmat.albedo_color = tint.lerp(Color.WHITE, 0.5)
	nmat.emission_enabled = true
	nmat.emission = tint.lerp(Color.WHITE, 0.4)
	nmat.emission_energy_multiplier = 1.2
	nose.material_override = nmat
	nose.position = Vector3(0, 0, 0.004)   # nudge toward the lens so it reads on top
	root.add_child(nose)
	root.set_meta("nose", nose)

# Point a figure's little nose along its current travel direction (keeps the last facing
# while idle). Works for pilots ("dir") and ambient staff/crew ("vel").
func _orient_nose(node: Node3D) -> void:
	var nose := node.get_meta("nose", null) as Node3D
	if nose == null:
		return
	var vel: Vector3 = node.get_meta("vel", Vector3.ZERO)
	var face: Vector3 = vel
	if face.length() < 0.001:
		face = node.get_meta("dir", Vector3.ZERO)
	if face.length() > 0.001:
		# HumanoidAsset's front is local +Y (visor/chest face that way), so rotate +Y
		# onto the travel vector. The old +X assumption made people walk sideways.
		nose.rotation.z = atan2(face.y, face.x) - PI * 0.5
	var speed_t := clampf(vel.length() / MAX_SPEED, 0.0, 1.8)
	HumanoidAssetScript.pose_walk(node, speed_t > 0.04, speed_t)

# Shared little sphere for the human figures (pilots & crew).
func _ball_mesh(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s

# --- Loop -----------------------------------------------------------------

func _process(_delta: float) -> void:
	# Watch for the enter trigger while flying the deck (this node runs always).
	if not GameState.deck_walk:
		# Track how long the ship has been settled on the carrier (ride-zoom gate).
		if GameState.on_carrier and not GameState.in_transition() \
				and not GameState.arrive_lock and not GameState.carrier_battle:
			_on_carrier_frames += 1
		else:
			_on_carrier_frames = 0
		_update_hint()
		return
	if _carrier == null or _cam == null or not is_instance_valid(_carrier):
		_exit_mode()
		return

	# Floor-change cinematic (hatch → elevator dive → interior reveal) runs to completion
	# with input locked.
	if _transition != "":
		_run_floor_transition()
		return

	# Camera: top-down, follow the lead, framed to the current floor.
	_update_floor_camera()
	_show_only_floor(_floor)   # steady state: hide the floors we're not on

	if _pilots.is_empty():
		return
	var lead := _pilots[0]

	# Lead pilot: plain follow-the-cursor (absolute → multi-monitor safe, no sticky
	# centre deadzone). Walking is never interrupted by crew — talking starts only on a
	# deliberate click near one (see _input), and a second click ends it and resumes.
	var target := _mouse_on_deck(lead.global_position)
	if _talking_to != null and is_instance_valid(_talking_to):
		# Hold the conversation until a click ends it (see _input) — no auto-cancel on
		# cursor movement. Do not push the lead away from the person: the click already
		# happened at talk range, and forced separation made the player visibly jump.
		lead.set_meta("vel", Vector3.ZERO)
		lead.global_position.z = _cur_pilot_z()
	elif _talking_to != null:
		_talking_to = null   # crew vanished — drop the lock
	# In the bath hall a click toggles "rest" — the pilot stops following the cursor and
	# stays put so you can soak in peace (click again to get up). Elsewhere, plain follow.
	var resting: bool = (_floor == 2 and _resting)
	if _talking_to == null and not resting:
		var to := Vector3(target.x - lead.global_position.x, target.y - lead.global_position.y, 0.0)
		var vel: Vector3 = lead.get_meta("vel")
		vel = vel.lerp(to.limit_length(MAX_SPEED), ACCEL)
		if vel.length() < 0.0006:
			vel = Vector3.ZERO
		lead.global_position += Vector3(vel.x, vel.y, 0.0)
		lead.global_position.z = _cur_pilot_z()
		_clamp_to_deck(lead)
		lead.set_meta("vel", vel)
		if vel.length() > 0.0008:
			lead.set_meta("dir", vel.normalized())
	elif resting:
		lead.set_meta("vel", Vector3.ZERO)   # parked in the bath; _update_onsen sinks it in

	# The rest follow: each eases toward a slot kept FOLLOW_SPACING behind the one
	# ahead — continuous (no on/off gate), so the whole train glides.
	for i in range(1, _pilots.size()):
		var p := _pilots[i]
		var ahead := _pilots[i - 1].global_position
		var back := p.global_position - ahead
		back.z = 0.0
		var d := back.length()
		var slot := (ahead + back / d * FOLLOW_SPACING) if d > 0.0001 else ahead
		_step_toward(p, Vector3(slot.x, slot.y, _cur_pilot_z()))

	for p in _pilots:
		p.scale = Vector3.ONE * _person_floor_scale()
		_orient_nose(p)   # point each little nose along its heading

	if _floor == 2:
		# Deepest deck: the moody hot-spring hall. The bow stair rides back up.
		_update_onsen(lead)
		_update_onsen_pad(lead)
		return

	if _floor == 1:
		# Below deck: the ship interior is a quiet hub — rooms partitioned by walls and a
		# corridor, ambient staff, no combat. The stern pad rides up to the deck; a second
		# stair at the bow descends further into the hot spring.
		_update_interior()
		_update_interior_vips(lead)
		_update_elevator(lead)
		_update_onsen_pad(lead)
		_update_deck_hud()   # keep the hull/resource/fund readout live below deck too
		return

	# Arm boarding once the lead has walked clear of the ship (so the first clicks
	# after disembarking fire instead of instantly re-boarding).
	if not _left_ship:
		var lp := lead.global_position
		if Vector2(lp.x, lp.y).distance_to(Vector2(GameState.px, GameState.py)) > SHIP_EXIT_R * 1.3:
			_left_ship = true

	_update_nav_arrow(lead)
	_update_enemy_arrow(lead)
	_update_crew()
	_update_mercs(lead)
	_update_boarders()
	_update_drops()
	_maybe_spawn_raid()
	_update_elevator(lead)
	_update_deck_hud()

	# Auto-attack: if the lead is inside an enemy's attack circle, the pilots open fire.
	var atk_target := _enemy_in_attack_range(lead)
	if atk_target != null:
		_fire_cd -= 1
		if _fire_cd <= 0:
			_auto_fire(atk_target)
			_fire_cd = FIRE_INTERVAL
	else:
		_fire_cd = 0

	_update_bullets()

# Move a pilot toward a target on the deck plane with smoothed, bounded velocity.
# Remembers the last real travel direction so firing shoots the way it's heading.
func _step_toward(p: Node3D, target: Vector3) -> void:
	var vel: Vector3 = p.get_meta("vel")
	var desired := target - p.global_position
	desired.z = 0.0
	var dist := desired.length()
	# Deadzone + harder braking when the target is reached (mouse held still) so the
	# pilot settles quickly instead of coasting.
	var desired_v := Vector3.ZERO if dist < STOP_DEADZONE else desired.limit_length(MAX_SPEED)
	var k: float = ACCEL if desired_v.length() > 0.0001 else STOP_DECEL
	vel = vel.lerp(desired_v, k)
	if vel.length() < 0.0008:
		vel = Vector3.ZERO
	p.global_position += Vector3(vel.x, vel.y, 0.0)
	p.set_meta("vel", vel)
	if vel.length() > 0.002:
		p.set_meta("dir", vel.normalized())
	_clamp_to_deck(p)

# --- Deck combat: auto-fire when a pilot stands in an enemy's attack circle ---

# Nearest deck enemy whose attack circle the lead pilot is standing in (or null).
func _enemy_in_attack_range(lead: Node3D) -> Node3D:
	var lead2 := Vector2(lead.global_position.x, lead.global_position.y)
	var best: Node3D = null
	var bd := INF
	for e in _boarders:
		if not is_instance_valid(e):
			continue
		var r := float(e.get_meta("atk_r", ATTACK_R_BOARDER))
		var d := lead2.distance_to(Vector2(e.global_position.x, e.global_position.y))
		if d <= r and d < bd:
			bd = d
			best = e
	return best

# Every pilot fires one bullet aimed at the target enemy.
func _auto_fire(target: Node3D) -> void:
	TsgAudio.player_shot()   # SE: volley (TsgAudio is process_mode ALWAYS → plays while paused)
	var tp := target.global_position
	for p in _pilots:
		var dir := Vector3(tp.x - p.global_position.x, tp.y - p.global_position.y, 0.0)
		if dir.length() < 0.001:
			dir = Vector3(0, 1, 0)
		dir = dir.normalized()
		var col: Color = p.get_meta("col")
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(PILOT_SIZE * 0.7, PILOT_SIZE * 0.7, PILOT_SIZE * 0.7)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.0
		mi.material_override = mat
		add_child(mi)
		mi.global_position = p.global_position + dir * (PILOT_SIZE * 0.8)
		_bullets.append({"mi": mi, "vel": dir * BULLET_SPEED, "life": BULLET_LIFE})

func _update_bullets() -> void:
	for b: Dictionary in _bullets.duplicate():
		var mi := b["mi"] as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			_bullets.erase(b)
			continue
		mi.global_position += b["vel"] as Vector3
		b["life"] = int(b["life"]) - 1
		var dead: bool = int(b["life"]) <= 0
		# Hit test: boarders only (never the carrier, ship, crew, or other pilots).
		if not dead:
			var bp := mi.global_position
			for bd in _boarders:
				if not is_instance_valid(bd):
					continue
				if Vector2(bd.global_position.x, bd.global_position.y).distance_to(
						Vector2(bp.x, bp.y)) <= BULLET_HIT_R:
					_damage_boarder(bd)
					dead = true
					break
		if dead:
			mi.queue_free()
			_bullets.erase(b)

func _mouse_on_deck(fallback: Vector3) -> Vector3:
	var mpos := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mpos)
	var dir := _cam.project_ray_normal(mpos)
	var hit: Variant = Plane(Vector3(0, 0, 1), _cur_pilot_z()).intersects_ray(from, dir)
	if hit == null:
		return fallback
	return hit as Vector3

# Walkable region follows the deck SILHOUETTE, not a plain rectangle: the central
# runway is long, the flanking lane decks are wider but shorter — so the corners
# (which have no deck) are excluded and pilots can't walk off into space.
func _clamp_xy(gx: float, gy: float) -> Vector2:
	var cx: float = _carrier.global_position.x
	var cy: float = _carrier.global_position.y
	# Below deck the walkable region is the (wider) command-room rectangle.
	if _floor == 1:
		return _clamp_interior(gx, gy)
	if _floor == 2:
		return _clamp_onsen(gx, gy)
	var x := gx - cx
	var y := gy - cy
	x = clampf(x, -(Mothership.FULL_HALF_W - EDGE_MARGIN), Mothership.FULL_HALF_W - EDGE_MARGIN)
	# Past the runway width we're on the (shorter) side decks → tighter length limit.
	var on_runway: bool = absf(x) <= Mothership.DECK_W * 0.5
	var hl: float = (Mothership.DECK_LEN * 0.5) if on_runway else (Mothership.DECK_LEN * 0.5 * 0.92)
	hl -= EDGE_MARGIN
	y = clampf(y, -hl, hl)
	return Vector2(cx + x, cy + y)

func _clamp_to_deck(p: Node3D) -> void:
	var c := _clamp_xy(p.global_position.x, p.global_position.y)
	p.global_position.x = c.x
	p.global_position.y = c.y

# --- Ship-locator arrow ---------------------------------------------------

# Flat triangles (point +X) hovering by the lead pilot: gold aims at the parked ship,
# red aims at the nearest deck enemy. Drawn on top (no_depth_test) so you never lose
# the ship or an intruder on the wide deck.
func _build_nav_arrow() -> void:
	_nav_arrow = _make_arrow(Color(1.0, 0.9, 0.3), Color(1.0, 0.85, 0.2))
	_enemy_arrow = _make_arrow(Color(1.0, 0.3, 0.25), Color(1.0, 0.15, 0.1))

func _make_arrow(albedo: Color, emis: Color) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var s := NAV_ARROW_SIZE
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(s, 0.0, 0.0), Vector3(-s * 0.55, s * 0.6, 0.0), Vector3(-s * 0.55, -s * 0.6, 0.0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emis
	mat.emission_energy_multiplier = 2.5
	node.material_override = mat
	node.visible = false
	add_child(node)
	return node

func _update_nav_arrow(lead: Node3D) -> void:
	if _nav_arrow == null:
		return
	var lead2 := Vector2(lead.global_position.x, lead.global_position.y)
	var ship2 := Vector2(GameState.px, GameState.py)
	var to := ship2 - lead2
	var dist := to.length()
	# Hide it once the ship is right here (you've arrived / about to board).
	if dist < SHIP_EXIT_R * 1.2:
		_nav_arrow.visible = false
		return
	_nav_arrow.visible = true
	var dir := to / dist
	_nav_arrow.global_position = Vector3(lead2.x + dir.x * 0.07, lead2.y + dir.y * 0.07, _pilot_z + 0.06)
	_nav_arrow.rotation = Vector3(0.0, 0.0, atan2(dir.y, dir.x))

# Red arrow → nearest deck enemy (boarder / intruder). Hidden when none, or when one
# is already close enough to see.
func _update_enemy_arrow(lead: Node3D) -> void:
	if _enemy_arrow == null:
		return
	var lead2 := Vector2(lead.global_position.x, lead.global_position.y)
	var best := Vector2.ZERO
	var bdist := INF
	for bd in _boarders:
		if not is_instance_valid(bd):
			continue
		var d := lead2.distance_to(Vector2(bd.global_position.x, bd.global_position.y))
		if d < bdist:
			bdist = d
			best = Vector2(bd.global_position.x, bd.global_position.y)
	if bdist == INF or bdist < 0.35:
		_enemy_arrow.visible = false
		return
	_enemy_arrow.visible = true
	var dir := (best - lead2) / bdist
	_enemy_arrow.global_position = Vector3(lead2.x + dir.x * 0.1, lead2.y + dir.y * 0.1, _pilot_z + 0.06)
	_enemy_arrow.rotation = Vector3(0.0, 0.0, atan2(dir.y, dir.x))

# --- Ambient crew ---------------------------------------------------------

# NPC crew scattered over the deck, wandering between spots and pausing to "work" —
# pure decoration to make the carrier feel lively/busy when you land. (A future
# periodic event will turn some of these into boarding enemies to fight.)
const CREW_PALETTE := [
	Color(0.95, 0.55, 0.15), Color(0.2, 0.7, 0.8),
	Color(0.7, 0.72, 0.78), Color(0.9, 0.8, 0.2)]

const CREW_NAMES := ["ヒカル", "ミナ", "ケン", "ソラ", "リク", "アヤ", "ジン", "ノア",
	"ユウ", "レイ", "カイ", "マオ", "ナギ", "ホシ", "ツバサ", "シオン"]
const CREW_JOBS := ["整備士", "技師", "操舵手", "通信士", "砲手", "医療班", "補給係", "料理長"]
const REPAIR_JOBS := ["整備士", "技師"]
# Named VIP crew (distinct color, bigger, stationed). NONE on deck now — タクト艦長 moved to
# the bow command room, ヒカリ商人 & カナ博士 to their below-deck rooms. Kept as a hook for
# any future deck-stationed VIP.
const VIPS: Array = []

func _spawn_crew() -> void:
	var names := CREW_NAMES.duplicate()
	names.shuffle()
	var ship := Vector3(GameState.px, GameState.py, _pilot_z)
	# Roster: a guaranteed engineer, the 3 named VIPs, then random crew to fill.
	var roster: Array = []
	roster.append({"name": names[0], "job": "整備士", "col": CREW_PALETTE[0], "vip": false})
	for v in VIPS:
		roster.append({"name": v["name"], "job": v["job"], "col": v["col"], "vip": true})
	var ni := 1
	while roster.size() < CREW_COUNT:
		roster.append({"name": names[ni % names.size()],
			"job": CREW_JOBS[randi() % CREW_JOBS.size()],
			"col": CREW_PALETTE[randi() % CREW_PALETTE.size()], "vip": false})
		ni += 1
	for i in roster.size():
		var job: String = roster[i]["job"]
		var nm: String = roster[i]["name"]
		var vip: bool = roster[i]["vip"]
		var crew := _make_crew(roster[i]["col"], nm, job, vip)
		var is_eng: bool = job in REPAIR_JOBS
		add_child(crew)
		# Mode mix: engineers cluster around the ship "working"; VIPs stay stationed so
		# you can find them; the rest split between stationed workers and roamers.
		var mode := "work" if (is_eng or vip or randf() < 0.45) else "wander"
		var home := _random_deck_point()
		if is_eng:
			# Ring the hull (机体周り) pretending to do repairs, but stay OUTSIDE the
			# boarding pad (SHIP_EXIT_R) so they never block the player re-boarding.
			var ang := randf() * TAU
			var rad := randf_range(SHIP_EXIT_R + 0.2, SHIP_EXIT_R + 0.6)
			home = Vector3(ship.x + cos(ang) * rad, ship.y + sin(ang) * rad, _pilot_z)
			var c := _clamp_xy(home.x, home.y)
			home = Vector3(c.x, c.y, _pilot_z)
		crew.global_position = home if mode == "work" else _random_deck_point()
		crew.set_meta("vel", Vector3.ZERO)
		crew.set_meta("mode", mode)
		crew.set_meta("home", home)
		crew.set_meta("target", home if mode == "work" else _random_deck_point())
		crew.set_meta("phase", randf() * TAU)
		crew.set_meta("pause", 0)
		crew.set_meta("name", nm)
		crew.set_meta("job", job)
		crew.set_meta("vip", vip)
		crew.set_meta("repair", is_eng)
		crew.set_meta("repair_cd", 0)
		_crew.append(crew)

func _make_crew(tint: Color, nm: String, job: String, vip: bool = false) -> Node3D:
	var root: Node3D = HumanoidAssetScript.make_figure(tint, CREW_SIZE * (1.7 if vip else 1.25), "vip" if vip else "crew")
	# Name tag floating above (shown only when the lead pilot is close). VIP names already
	# carry their title (e.g. "タクト艦長"), so don't append the job again.
	var tag := Label3D.new()
	tag.text = nm if vip else ("%s / %s" % [nm, _job_label(job)])
	tag.font_size = 64
	tag.pixel_size = 0.0003 if vip else 0.00022  # tiny: scaled to the deck, not the flight HUD
	tag.outline_size = 6
	tag.modulate = tint.lerp(Color.WHITE, 0.6)
	tag.no_depth_test = true
	tag.position = Vector3(0, 0.045 if vip else 0.035, 0.07)
	tag.visible = false
	root.add_child(tag)
	root.set_meta("tag", tag)

	# Talk-range ring: a flat circle showing this crew is clickable; shown when the
	# lead pilot is near, brightened when actually in range.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = TALK_R * 0.82
	torus.outer_radius = TALK_R
	torus.rings = 48          # smooth circle (NOT a triangle — rings = segments around the ring)
	torus.ring_segments = 6
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)   # lie flat in the deck plane (face camera)
	ring.position = Vector3(0, 0, -0.02)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.4, 0.9, 1.0, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(0.4, 0.9, 1.0)
	rmat.no_depth_test = true
	ring.material_override = rmat
	ring.visible = false
	root.add_child(ring)
	root.set_meta("ring", ring)

	# Attention marker for crew that matter (engineers): a pulsing "！" so the player
	# spots who to talk to for repairs.
	if job in REPAIR_JOBS:
		var attn := Label3D.new()
		attn.text = Loc.pair("！修理", "! REPAIR")
		attn.font_size = 64
		attn.pixel_size = 0.00028
		attn.outline_size = 8
		attn.modulate = Color(1.0, 0.85, 0.2)
		attn.no_depth_test = true
		attn.position = Vector3(0, 0.07, 0.05)
		attn.visible = false
		root.add_child(attn)
		root.set_meta("attn", attn)
	return root

func _random_deck_point() -> Vector3:
	var cx: float = _carrier.global_position.x
	var cy: float = _carrier.global_position.y
	var hw: float = Mothership.FULL_HALF_W - EDGE_MARGIN
	var hl: float = Mothership.DECK_LEN * 0.5 - EDGE_MARGIN
	var c := _clamp_xy(cx + randf_range(-hw, hw), cy + randf_range(-hl, hl))
	return Vector3(c.x, c.y, _pilot_z)

func _update_crew() -> void:
	var t := Time.get_ticks_msec() / 1000.0  # real time → keeps ticking while paused
	var lead_xy := Vector2.ZERO
	if not _pilots.is_empty():
		lead_xy = Vector2(_pilots[0].global_position.x, _pilots[0].global_position.y)
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	for c in _crew:
		var cd := int(c.get_meta("repair_cd"))
		if cd > 0:
			c.set_meta("repair_cd", cd - 1)
		var dist := lead_xy.distance_to(Vector2(c.global_position.x, c.global_position.y))
		var tag := c.get_meta("tag") as Label3D
		if tag != null:
			tag.visible = dist < TALK_R * 2.5
		# Talk-range ring: appears as the lead approaches, brightens when in range.
		var ring := c.get_meta("ring") as MeshInstance3D
		if ring != null:
			ring.visible = dist < TALK_R * 2.5
			if ring.visible:
				var in_range := dist <= TALK_R
				var rm := ring.material_override as StandardMaterial3D
				rm.albedo_color = Color(0.4, 1.0, 0.5, 0.85) if in_range else Color(0.4, 0.9, 1.0, 0.4)
				rm.emission = Color(0.4, 1.0, 0.5) if in_range else Color(0.4, 0.9, 1.0)
				rm.emission_energy_multiplier = (1.5 + pulse) if in_range else 0.8
		# Attention marker (engineers): pulses while the hull needs repair.
		if c.has_meta("attn"):
			var attn := c.get_meta("attn") as Label3D
			var need := GameState.carrier_hull < GameState.CARRIER_HULL_MAX
			attn.visible = need
			if need:
				attn.modulate.a = 0.4 + 0.6 * pulse
		var mode: String = c.get_meta("mode")
		var pause := int(c.get_meta("pause"))
		if pause > 0:
			c.set_meta("pause", pause - 1)
		else:
			var target: Vector3 = c.get_meta("target")
			var to := Vector3(target.x - c.global_position.x, target.y - c.global_position.y, 0.0)
			if to.length() < 0.04:
				if mode == "work":
					# Stay near home, fidget around the work spot, pause often (整備の体).
					var home: Vector3 = c.get_meta("home")
					c.set_meta("target", Vector3(home.x + randf_range(-0.06, 0.06),
						home.y + randf_range(-0.06, 0.06), _pilot_z))
					c.set_meta("pause", randi_range(60, 180))
				else:
					c.set_meta("target", _random_deck_point())
					if randf() < 0.5:
						c.set_meta("pause", randi_range(30, 120))
			else:
				var vel: Vector3 = c.get_meta("vel")
				vel = vel.lerp(to.limit_length(CREW_SPEED), 0.1)
				c.global_position += Vector3(vel.x, vel.y, 0.0)
				c.set_meta("vel", vel)
				_clamp_to_deck(c)
		# Busy little bob (workers bob faster — heads-down maintenance).
		var phase: float = c.get_meta("phase")
		var bob_rate := 6.0 if mode == "work" else 4.0
		c.global_position.z = _pilot_z + absf(sin(t * bob_rate + phase)) * 0.012
		_orient_nose(c)   # deck crew face their walk direction too

# --- Hired-gun mercenaries (GameState.mercs) ------------------------------
# These are the guards hired from ヒカリ商人 below deck. On the deck they walk as burly
# NPCs (一回り大きい), can be talked to, and actually FIGHT: they hunt deck enemies, open
# fire, take chip damage when an enemy closes, and fall when their HP runs out.

# Reconcile the deck NPCs with GameState.mercs — which changes as you hire below deck or a
# guard falls. Spawn one for every hired gun without an NPC; free any whose merc is gone.
# Matched by unique name so HP shifts and deaths line up.
func _sync_deck_mercs() -> void:
	if _carrier == null:
		return
	for mc in _mercs.duplicate():
		if not is_instance_valid(mc) or GameState.merc_find(String(mc.get_meta("name"))) < 0:
			if is_instance_valid(mc):
				mc.queue_free()
			_mercs.erase(mc)
	var have := {}
	for mc in _mercs:
		have[String(mc.get_meta("name"))] = true
	for i in GameState.mercs.size():
		var nm := GameState.merc_name(i)
		if have.has(nm):
			continue
		var m := _make_merc(nm)
		add_child(m)
		m.global_position = _random_deck_point()
		m.set_meta("vel", Vector3.ZERO)
		m.set_meta("target", _random_deck_point())
		m.set_meta("phase", randf() * TAU)
		m.set_meta("pause", 0)
		m.set_meta("fire_cd", 0)
		_mercs.append(m)

func _make_merc(nm: String) -> Node3D:
	var tint := Color(0.85, 0.45, 0.18)   # rust-orange armor — reads apart from the crew
	var root: Node3D = HumanoidAssetScript.make_figure(tint, MERC_SIZE * 1.25, "merc")
	# Name + HP tag (HP refreshed each frame while the lead is near).
	var tag := Label3D.new()
	tag.text = nm
	tag.font_size = 64
	tag.pixel_size = 0.00032
	tag.outline_size = 6
	tag.modulate = Color(1.0, 0.85, 0.6)
	tag.no_depth_test = true
	tag.position = Vector3(0, MERC_SIZE + 0.03, 0.07)
	tag.visible = false
	root.add_child(tag)
	root.set_meta("tag", tag)
	# Talk ring — gold, so guards read as clickable like the crew.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = TALK_R * 0.82
	torus.outer_radius = TALK_R
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, 0, -0.02)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.8, 0.3, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.8, 0.3)
	rmat.no_depth_test = true
	ring.material_override = rmat
	ring.visible = false
	root.add_child(ring)
	root.set_meta("ring", ring)
	root.set_meta("name", nm)
	root.set_meta("job", "傭兵")
	root.set_meta("vip", false)
	root.set_meta("role", "merc")
	return root

func _update_mercs(lead: Node3D) -> void:
	_sync_deck_mercs()
	if _mercs.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var lead_xy := Vector2(lead.global_position.x, lead.global_position.y)
	for mc: Node3D in _mercs.duplicate():
		if not is_instance_valid(mc):
			_mercs.erase(mc)
			continue
		var nm := String(mc.get_meta("name"))
		var mi := GameState.merc_find(nm)
		if mi < 0:
			mc.queue_free()
			_mercs.erase(mc)
			continue
		var pos := mc.global_position
		var mc2 := Vector2(pos.x, pos.y)
		# Tag + talk ring by distance to the lead; tag shows live HP.
		var dist_lead := lead_xy.distance_to(mc2)
		var tag := mc.get_meta("tag") as Label3D
		if tag != null:
			tag.visible = dist_lead < TALK_R * 3.0
			if tag.visible:
				tag.text = "%s  HP%d" % [nm, int(ceil(GameState.merc_hp(mi)))]
		var ring := mc.get_meta("ring") as MeshInstance3D
		if ring != null:
			ring.visible = dist_lead < TALK_R * 2.5
			if ring.visible:
				var in_range := dist_lead <= TALK_R
				var rm := ring.material_override as StandardMaterial3D
				rm.emission_energy_multiplier = (1.5 + pulse) if in_range else 0.8
				rm.albedo_color.a = 0.85 if in_range else 0.4
		var fire_cd := int(mc.get_meta("fire_cd"))
		if fire_cd > 0:
			mc.set_meta("fire_cd", fire_cd - 1)
		var target := _nearest_enemy(mc2, MERC_ENGAGE_R)
		if target != null:
			# COMBAT: close to standoff range, fire, and bleed HP if an enemy is on top of it.
			var ep := target.global_position
			var to := Vector3(ep.x - pos.x, ep.y - pos.y, 0.0)
			var d := to.length()
			var vel: Vector3 = mc.get_meta("vel")
			var desired := Vector3.ZERO if d < MERC_STANDOFF else to.limit_length(MERC_SPEED)
			vel = vel.lerp(desired, 0.12)
			mc.global_position += Vector3(vel.x, vel.y, 0.0)
			mc.set_meta("vel", vel)
			_clamp_to_deck(mc)
			if d > 0.001:
				mc.set_meta("dir", to.normalized())
			if d <= MERC_FIRE_R and fire_cd <= 0:
				_merc_fire(mc, target)
				mc.set_meta("fire_cd", MERC_FIRE_CD)
			if d <= MERC_HURT_R and GameState.damage_merc(nm, MERC_HURT_DPS):
				_merc_fall(mc)
				continue
		else:
			# PATROL: wander deck points, pausing now and then.
			var pause := int(mc.get_meta("pause"))
			if pause > 0:
				mc.set_meta("pause", pause - 1)
			else:
				var tgt: Vector3 = mc.get_meta("target")
				var to := Vector3(tgt.x - pos.x, tgt.y - pos.y, 0.0)
				if to.length() < 0.05:
					mc.set_meta("target", _random_deck_point())
					if randf() < 0.5:
						mc.set_meta("pause", randi_range(40, 120))
				else:
					var vel: Vector3 = mc.get_meta("vel")
					vel = vel.lerp(to.limit_length(MERC_SPEED * 0.7), 0.1)
					mc.global_position += Vector3(vel.x, vel.y, 0.0)
					mc.set_meta("vel", vel)
					_clamp_to_deck(mc)
		var phase: float = mc.get_meta("phase")
		mc.global_position.z = _pilot_z + absf(sin(t * 5.0 + phase)) * 0.012
		_orient_nose(mc)

# Nearest live deck enemy to a point within radius (skips the still-descending transport).
func _nearest_enemy(from2: Vector2, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for e in _boarders:
		if not is_instance_valid(e):
			continue
		if String(e.get_meta("kind")) == "zako" and not bool(e.get_meta("landed", false)):
			continue
		var d := from2.distance_to(Vector2(e.global_position.x, e.global_position.y))
		if d < bd:
			bd = d
			best = e
	return best

# A merc fires one bolt at its target (reuses the deck-bullet pool, so it damages enemies
# through the same hit test as the pilots' fire).
func _merc_fire(mc: Node3D, target: Node3D) -> void:
	TsgAudio.player_shot()
	var p := mc.global_position
	var tp := target.global_position
	var dir := Vector3(tp.x - p.x, tp.y - p.y, 0.0)
	if dir.length() < 0.001:
		dir = Vector3(0, 1, 0)
	dir = dir.normalized()
	var col := Color(1.0, 0.7, 0.25)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(MERC_SIZE * 0.5, MERC_SIZE * 0.5, MERC_SIZE * 0.5)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	add_child(mi)
	mi.global_position = p + dir * (MERC_SIZE * 0.9)
	_bullets.append({"mi": mi, "vel": dir * BULLET_SPEED, "life": BULLET_LIFE})

func _merc_fall(mc: Node3D) -> void:
	TsgAudio.enemy_hit()
	if _hint != null:
		_hint.text = Loc.pair("傭兵 %s が倒れた...！", "Mercenary %s is down!") % String(mc.get_meta("name"))
	mc.queue_free()
	_mercs.erase(mc)

# The hired-gun NPC nearest the lead within talk range, or null (floor 0).
func _merc_near_lead() -> Node3D:
	if _pilots.is_empty():
		return null
	var lead2 := Vector2(_pilots[0].global_position.x, _pilots[0].global_position.y)
	var best: Node3D = null
	var bd := TALK_R
	for mc in _mercs:
		if not is_instance_valid(mc):
			continue
		var d := lead2.distance_to(Vector2(mc.global_position.x, mc.global_position.y))
		if d < bd:
			bd = d
			best = mc
	return best

# --- Takeover boarders ----------------------------------------------------

# Spawn the remaining boarders (GameState.takeover_boarders) at deck edges. They
# advance on the pilots; the player repels them with fire. Cleared → event lifts.
func _spawn_boarders() -> void:
	var cx: float = _carrier.global_position.x
	var cy: float = _carrier.global_position.y
	var hw: float = Mothership.FULL_HALF_W - EDGE_MARGIN
	var hl: float = Mothership.DECK_LEN * 0.5 - EDGE_MARGIN
	for i in GameState.takeover_boarders:
		var bd := _make_enemy(BOARDER_SIZE, Color(1.0, 0.2, 0.2))
		add_child(bd)
		# Enter from a random edge of the deck.
		var pos := _random_deck_point()
		match randi() % 4:
			0: pos.x = cx - hw
			1: pos.x = cx + hw
			2: pos.y = cy - hl
			3: pos.y = cy + hl
		var c := _clamp_xy(pos.x, pos.y)
		bd.global_position = Vector3(c.x, c.y, _pilot_z)
		bd.set_meta("kind", "boarder")
		bd.set_meta("hp", BOARDER_HP)
		bd.set_meta("vel", Vector3.ZERO)
		bd.set_meta("phase", randf() * TAU)
		bd.set_meta("atk_r", ATTACK_R_BOARDER)
		_add_attack_ring(bd, ATTACK_R_BOARDER)
		_boarders.append(bd)

# A menacing amoeba: a lumpy, slimy blob with oozing pseudopods that squirm (animated in
# _wriggle). Used for boarders AND the raiders deployed from a zako.
func _make_enemy(size: float, col: Color) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col * 0.55          # dark, sinister body
	mat.emission_enabled = true
	mat.emission = col                      # glows in its own malevolent hue
	mat.emission_energy_multiplier = 1.9
	mat.roughness = 0.18                    # wet, slimy sheen
	mat.metallic = 0.1
	# Lumpy central blob (low-poly sphere reads organic, not a tidy box).
	var blob := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = size
	sph.height = size * 2.0
	sph.radial_segments = 8
	sph.rings = 5
	blob.mesh = sph
	blob.material_override = mat
	root.add_child(blob)
	root.set_meta("blob", blob)
	# Oozing pseudopods that extend & retract — the amoeba squirm.
	var pods := []
	var n := 4
	for i in n:
		var a := float(i) / float(n) * TAU + randf() * 0.6
		var pod := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = size * 0.5
		ps.height = size
		ps.radial_segments = 6
		ps.rings = 4
		pod.mesh = ps
		pod.material_override = mat
		var dir := Vector3(cos(a), sin(a), 0.0)
		pod.position = dir * size
		root.add_child(pod)
		pods.append({"node": pod, "base": dir * size, "phase": randf() * TAU})
	root.set_meta("pods", pods)
	return root

# Squirm a boarder/raider amoeba: pulse the body unevenly and ooze the pseudopods in/out.
func _wriggle(bd: Node3D, t: float) -> void:
	var phase: float = bd.get_meta("phase", 0.0)
	var blob := bd.get_meta("blob", null) as MeshInstance3D
	if blob != null:
		blob.scale = Vector3(
			1.0 + 0.28 * sin(t * 5.0 + phase),
			1.0 + 0.28 * sin(t * 5.0 + phase + 2.1),
			1.0 + 0.22 * sin(t * 4.0 + phase + 4.2))
	var pods: Array = bd.get_meta("pods", [])
	for pd: Dictionary in pods:
		var node := pd["node"] as MeshInstance3D
		if is_instance_valid(node):
			var ext: float = 0.7 + 0.55 * (0.5 + 0.5 * sin(t * 3.2 + float(pd["phase"])))
			node.position = (pd["base"] as Vector3) * ext

# A red flat ring marking an enemy's attack circle — step inside it and the pilots fire.
func _add_attack_ring(node: Node3D, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.9
	torus.outer_radius = radius
	torus.rings = 48          # segments AROUND the circle — high = a smooth ring, not a triangle
	torus.ring_segments = 6   # tube cross-section (thin, few needed)
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)   # flat on the deck plane
	ring.position = Vector3(0, 0, -0.18)         # just under the enemy
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.25, 0.2, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.2, 0.15)
	rmat.no_depth_test = true
	ring.material_override = rmat
	node.add_child(ring)
	node.set_meta("atk_ring", ring)

# Real-time intruder: rarely, ONE life-size enemy (a real game character at ship scale)
# flies in along the runway and lands. It's tough — the pilots chip it down.
const ENEMY_SCENE := preload("res://scenes/units/Enemy.tscn")

func _maybe_spawn_raid() -> void:
	if GameState.carrier_takeover:
		return   # the big takeover event owns the deck; no piling on
	_raid_cd -= 1
	if _raid_cd > 0:
		return
	_raid_cd = randi_range(RAID_MIN_CD, RAID_MAX_CD)
	for bd in _boarders:
		if String(bd.get_meta("kind")) == "zako":
			return   # one intruder at a time
	var cx: float = _carrier.global_position.x
	var cy: float = _carrier.global_position.y
	var hl: float = Mothership.DECK_LEN * 0.5
	var zako := _make_zako()
	add_child(zako)
	_fix_zako_visual(zako)   # AFTER tree-entry: undo Enemy._ready's flight z & scale
	# Fly in from beyond the bow, descending to land NEAR the lead pilot so it's in view
	# (the camera is zoomed in tight; a far landing would be off-screen).
	zako.global_position = Vector3(cx + randf_range(-0.4, 0.4), cy + hl + 0.6, _pilot_z + 0.5)
	var land := Vector3(cx + randf_range(-0.3, 0.3), cy, _pilot_z)
	if not _pilots.is_empty():
		var lp := _pilots[0].global_position
		var ang := randf() * TAU
		var c := _clamp_xy(lp.x + cos(ang) * 0.45, lp.y + sin(ang) * 0.45)
		land = Vector3(c.x, c.y, _pilot_z)
	# Keep the landing clear of the parked ship so the intruder never overlaps 自機.
	var ship2 := Vector2(GameState.px, GameState.py)
	var off := Vector2(land.x, land.y) - ship2
	if off.length() < SHIP_CLEAR:
		if off.length() < 0.001:
			off = Vector2(0, 1)
		var pushed := ship2 + off.normalized() * SHIP_CLEAR
		var cc := _clamp_xy(pushed.x, pushed.y)
		land = Vector3(cc.x, cc.y, _pilot_z)
	zako.set_meta("kind", "zako")
	zako.set_meta("hp", ZAKO_HP)
	zako.set_meta("maxhp", ZAKO_HP)
	zako.set_meta("vel", Vector3.ZERO)
	zako.set_meta("land", land)
	zako.set_meta("landed", false)
	zako.set_meta("deployed", false)
	zako.set_meta("deploy_t", 0)
	zako.set_meta("atk_r", ATTACK_R_ZAKO)
	_add_attack_ring(zako, ATTACK_R_ZAKO)
	_boarders.append(zako)
	if _hint != null:
		_hint.text = Loc.pair(
			"敵機 着艦！ - 攻撃サークルに入って撃破しろ（硬い）",
			"Enemy craft landed! Step into the attack circle and bring it down.")

# A life-size enemy: a real game Enemy node (visual only — its own behavior disabled),
# wrapped so DeckWalkMode drives its position/HP like any other deck enemy.
func _make_zako() -> Node3D:
	var root := Node3D.new()
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.enemy_type = ZAKO_TYPES[randi() % ZAKO_TYPES.size()]
	e.hp = ZAKO_HP
	e.max_hp = ZAKO_HP
	root.add_child(e)
	# PAUSABLE so it FREEZES while the deck is paused (no flight drift/attacks) but still
	# RENDERS (DISABLED can hide it). process_mode persists across tree-entry.
	e.process_mode = Node.PROCESS_MODE_PAUSABLE
	# NOTE: position/scale are fixed in _fix_zako_visual() AFTER the wrapper is in the
	# tree — Enemy._ready() (which runs on tree-entry) sets its own flight z & ZAKO_SCALE,
	# so overriding them here (before tree-entry) would be clobbered.
	return root

# Snap the Enemy visual onto the deck plane and to ship size. Must run AFTER the wrapper
# is added to the tree (so Enemy._ready has already set — and we now override — its
# flight position.z and built-in scale).
func _fix_zako_visual(zako: Node3D) -> void:
	if zako.get_child_count() == 0:
		return
	var e := zako.get_child(0) as Node3D
	e.position = Vector3.ZERO
	e.scale = Vector3.ONE * ZAKO_VISUAL_SCALE

# Enemy pilots disembark from a landed intruder and advance on the player's pilots.
func _deploy_raiders(zako: Node3D) -> void:
	for i in RAID_PILOTS:
		var r := _make_enemy(BOARDER_SIZE * 0.85, Color(1.0, 0.5, 0.15))
		add_child(r)
		var ang := randf() * TAU
		var c := _clamp_xy(zako.global_position.x + cos(ang) * 0.12,
			zako.global_position.y + sin(ang) * 0.12)
		r.global_position = Vector3(c.x, c.y, _pilot_z)
		r.set_meta("kind", "raider")
		r.set_meta("hp", RAIDER_HP)
		r.set_meta("vel", Vector3.ZERO)
		r.set_meta("phase", randf() * TAU)
		r.set_meta("atk_r", ATTACK_R_BOARDER)
		_add_attack_ring(r, ATTACK_R_BOARDER)
		_boarders.append(r)
	TsgAudio.enemy_hit()
	if _hint != null:
		_hint.text = Loc.pair("敵パイロットが降りてきた！ - 攻撃サークルで迎撃", "Enemy pilots deployed! Intercept in the attack circle.")

func _update_boarders() -> void:
	if _pilots.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	# Iterate a copy: deploying raiders appends to _boarders mid-loop.
	for bd: Node3D in _boarders.duplicate():
		if not is_instance_valid(bd):
			continue
		var kind := String(bd.get_meta("kind"))
		if kind == "zako":
			if not bool(bd.get_meta("landed")):
				# Fly/descend to the landing spot, then STOP there.
				var land: Vector3 = bd.get_meta("land")
				var to := land - bd.global_position
				if Vector2(to.x, to.y).length() < 0.05 and absf(to.z) < 0.05:
					bd.global_position = land
					bd.set_meta("landed", true)
					bd.set_meta("vel", Vector3.ZERO)
					TsgAudio.dive_smash()   # SE: intruder touches down
				else:
					var v: Vector3 = bd.get_meta("vel")
					v = v.lerp(to.limit_length(ZAKO_SPEED), 0.1)
					bd.global_position += v
					bd.set_meta("vel", v)
			else:
				# Landed: sit still (no creep, never chases the ship). After a beat,
				# disembark enemy pilots once.
				var dt := int(bd.get_meta("deploy_t")) + 1
				bd.set_meta("deploy_t", dt)
				if not bool(bd.get_meta("deployed")) and dt >= ZAKO_DEPLOY_DELAY:
					bd.set_meta("deployed", true)
					_deploy_raiders(bd)
			continue
		# Move toward the nearest pilot.
		var nearest := _pilots[0].global_position
		var nd := INF
		for p in _pilots:
			var dd: float = p.global_position.distance_squared_to(bd.global_position)
			if dd < nd:
				nd = dd
				nearest = p.global_position
		var to_lead := Vector3(nearest.x - bd.global_position.x, nearest.y - bd.global_position.y, 0.0)
		var phase: float = bd.get_meta("phase")
		var vel: Vector3 = bd.get_meta("vel")
		if kind == "raider":
			# Enemy pilot: approaches to a polite distance then bounces in place, trying
			# to APPEAL to the player (ぴょんぴょん). Never attacks.
			var desired := Vector3.ZERO if to_lead.length() < 0.22 else to_lead.limit_length(BOARDER_SPEED * 0.7)
			vel = vel.lerp(desired, 0.08)
			bd.global_position += Vector3(vel.x, vel.y, 0.0)
			bd.set_meta("vel", vel)
			_clamp_to_deck(bd)
			bd.global_position.z = _pilot_z + absf(sin(t * 9.0 + phase)) * 0.06  # big hop
		else:
			vel = vel.lerp(to_lead.limit_length(BOARDER_SPEED), 0.08)
			bd.global_position += Vector3(vel.x, vel.y, 0.0)
			bd.set_meta("vel", vel)
			_clamp_to_deck(bd)
			bd.global_position.z = _pilot_z + absf(sin(t * 6.0 + phase)) * 0.01
			bd.rotation.z += 0.03   # slow writhe of the whole blob (pseudopods swirl with it)
		# Amoeba squirm for every boarder/raider (the zako transport already 'continue'd).
		_wriggle(bd, t)

func _damage_boarder(bd: Node3D) -> void:
	var hp := int(bd.get_meta("hp")) - 1
	if hp > 0:
		bd.set_meta("hp", hp)
		TsgAudio.enemy_hit()       # SE: chip
		return
	var kind := String(bd.get_meta("kind"))
	var pos := bd.global_position
	_boarders.erase(bd)
	bd.queue_free()
	TsgAudio.enemy_destroy()       # SE: kill
	# Drop salvage the pilots collect.
	if kind == "zako":
		_spawn_drops(pos, RES_PER_ZAKO, 5)
	elif kind == "raider":
		_spawn_drops(pos, RES_PER_RAIDER, 2)
	else:
		_spawn_drops(pos, RES_PER_RAIDER, 2)
	if kind == "boarder":
		GameState.takeover_boarders = maxi(0, GameState.takeover_boarders - 1)
		if GameState.takeover_boarders <= 0:
			_clear_takeover()
	elif kind == "zako" and _hint != null:
		_hint.text = Loc.pair("敵機を撃破した！ 資源を回収しろ", "Enemy craft destroyed! Collect the salvage.")

func _clear_takeover() -> void:
	GameState.carrier_takeover = false
	if _hint != null:
		_hint.text = Loc.pair("母艦確保 - 修理 / 新規機体 復旧", "CARRIER SECURED - repairs / new units restored")

# --- Salvage drops --------------------------------------------------------

func _spawn_drops(pos: Vector3, total: int, count: int) -> void:
	var per: int = maxi(1, int(round(float(total) / float(count))))
	for i in count:
		var d := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(PILOT_SIZE * 0.9, PILOT_SIZE * 0.9, PILOT_SIZE * 0.9)
		d.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.2)
		mat.emission_energy_multiplier = 1.4
		d.material_override = mat
		add_child(d)
		var c := _clamp_xy(pos.x + randf_range(-0.1, 0.1), pos.y + randf_range(-0.1, 0.1))
		d.global_position = Vector3(c.x, c.y, _pilot_z)
		d.set_meta("val", per)
		_drops.append(d)

func _update_drops() -> void:
	if _drops.is_empty() or _pilots.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var lead := _pilots[0].global_position
	for d: Node3D in _drops.duplicate():
		if not is_instance_valid(d):
			_drops.erase(d)
			continue
		var to := Vector2(lead.x - d.global_position.x, lead.y - d.global_position.y)
		var dist := to.length()
		if dist <= DROP_PICKUP_R:
			GameState.add_resource("SALVAGE", int(d.get_meta("val")))
			TsgAudio.pickup(false)
			_drops.erase(d)
			d.queue_free()
			continue
		if dist <= DROP_MAGNET_R:   # drift toward the lead pilot
			var step := to / maxf(dist, 0.001) * 0.02
			d.global_position += Vector3(step.x, step.y, 0.0)
		d.global_position.z = _pilot_z + 0.02 + absf(sin(t * 5.0)) * 0.01  # gentle hover/spin
		d.rotation.y += 0.12

# --- Input ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not GameState.deck_walk:
		# Not walking yet: a click while parked on the deck disembarks the pilots.
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT and _can_enter():
			_enter()
			get_viewport().set_input_as_handled()
		return
	# A lift cinematic is playing: swallow input until it finishes.
	if _transition != "":
		return
	# Walking: combat is automatic (attack circles) and conversation is on click (crew
	# circles). Clicks/keys are for the elevator and for boarding back into the ship.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_walk_zoom_offset = maxf(WALK_ZOOM_MIN, _walk_zoom_offset - WALK_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_walk_zoom_offset = minf(WALK_ZOOM_MAX, _walk_zoom_offset + WALK_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_exit_mode()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _talking_to != null:
				# Talking: a second click ends it and resumes walking (leaving by moving
				# the cursor was fiddly while the pilot is held in place).
				_talking_to = null
				if _dialogue != null:
					_dialogue.visible = false
				get_viewport().set_input_as_handled()
			else:
				# On the deck, boarding your own ship and talking to crew take PRIORITY over
				# the stern hatch — so a ship parked on (or a crew member standing on) the
				# lift never turns a take-off / talk click into an accidental descent.
				var crew := _crew_near_lead()
				var merc := _merc_near_lead() if _floor == 0 else null
				var vip := _vip_near_lead() if _floor == 1 else null
				if _floor == 0 and _lead_at_ship():
					_exit_mode()
					get_viewport().set_input_as_handled()
				elif _floor == 0 and crew != null:
					_talking_to = crew
					_talk(crew)
					get_viewport().set_input_as_handled()
				elif _floor == 0 and merc != null:
					# Talk to a hired gun patrolling the deck.
					_talking_to = merc
					_talk(merc)
					get_viewport().set_input_as_handled()
				elif _floor == 1 and vip != null:
					# Below deck: talk to ヒカリ商人 / カナ博士 (priority over the lift pad).
					_talking_to = vip
					_talk(vip)
					get_viewport().set_input_as_handled()
				elif _on_pad:
					# On the stern elevator pad: ride down to the command room (or back up).
					_begin_floor_change(0 if _floor == 1 else 1)
					get_viewport().set_input_as_handled()
				elif _on_onsen_pad and _floor >= 1:
					# On the bow stair: ride down to the hot spring (or back up to floor 1).
					_begin_floor_change(1 if _floor == 2 else 2)
					get_viewport().set_input_as_handled()
				elif _floor == 2:
					# In the bath hall: toggle resting so you can park in a tub and soak
					# (click again to get up and move).
					_resting = not _resting
					get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
			_exit_mode()
			get_viewport().set_input_as_handled()

func _lead_at_ship() -> bool:
	if _pilots.is_empty() or not _left_ship:
		return false
	var lp := _pilots[0].global_position
	return Vector2(lp.x, lp.y).distance_to(Vector2(GameState.px, GameState.py)) < SHIP_EXIT_R

# --- Conversation & repair ------------------------------------------------

# The crew member nearest the lead pilot within talk range (or null).
func _crew_near_lead() -> Node3D:
	if _pilots.is_empty():
		return null
	var lead2 := Vector2(_pilots[0].global_position.x, _pilots[0].global_position.y)
	var best: Node3D = null
	var bd := TALK_R
	for c in _crew:
		var d := lead2.distance_to(Vector2(c.global_position.x, c.global_position.y))
		if d < bd:
			bd = d
			best = c
	return best

# Talk to a crew member. Engineers (整備士/技師) spend resources to repair a CHUNK of the
# carrier hull — never a full heal, with a per-crew cooldown so you can't get it all from
# one person. Everyone else gives a flavor line. All Japanese.
const CHATTER := {
	"操舵手": [["「進路は任せとけ。」", "\"Leave the course to me.\""], ["「いい星系を見つけたぞ。」", "\"Found us a good star system.\""]],
	"通信士": [["「妙な信号を拾った...気をつけろ。」", "\"Strange signal on comms. Stay sharp.\""], ["「本部とは連絡が取れてる。」", "\"Command link is still alive.\""]],
	"砲手": [["「弾はいくらでも込めてやる。」", "\"I can load shells all day.\""], ["「次の戦闘が楽しみだ。」", "\"Looking forward to the next fight.\""]],
	"医療班": [["「無茶はするなよ、パイロット。」", "\"Do not overdo it, pilot.\""], ["「みんな無事か？」", "\"Everyone still in one piece?\""]],
	"補給係": [["「資源、もっと採ってきてくれ。」", "\"Bring back more resources.\""], ["「補給は万全だ。」", "\"Supplies are ready.\""]],
	"料理長": [["「飯はちゃんと食えよ。」", "\"Eat properly out there.\""], ["「今夜は特製スープだ。」", "\"Special soup tonight.\""]],
	"艦長": [["「よく戻った。この母艦は君の家だ。」", "\"Welcome back. This carrier is your home.\""], ["「無理はするな、艦のことは任せておけ。」", "\"Do not force it. Leave the ship to us.\""]],
	"商人": [["「資源があればいい取引ができるぞ。」", "\"Resources make good deals possible.\""], ["「掘ってきた物は高く買おう。」", "\"I pay well for what you mine.\""]],
	"博士": [["「興味深いデータが取れたわ。」", "\"The data is fascinating.\""], ["「その機体、まだ伸びしろがあるわね。」", "\"That craft still has room to grow.\""]],
}

func _talk(crew: Node3D) -> void:
	# Stop the crew member so they stand and talk (not walk off mid-conversation).
	crew.set_meta("pause", 210)
	crew.set_meta("vel", Vector3.ZERO)
	var nm: String = crew.get_meta("name")
	var job: String = crew.get_meta("job")
	var role: String = crew.get_meta("role", "")
	var line := ""
	if role == "hikari":
		# Hire a mercenary: spend resources, up to 5. They defend during takeovers.
		if GameState.merc_count() >= GameState.MERC_MAX:
			line = Loc.pair("「もう%d人雇ってある。これ以上は無理だ。」", "\"You already hired %d. That is the limit.\"") % GameState.MERC_MAX
		elif GameState.res_pool < GameState.MERC_HIRE_COST:
			line = Loc.pair("「資源が足りんな。傭兵一人に %d 要る。掘ってこい。」", "\"Not enough resources. One guard costs %d. Go mine.\"") % GameState.MERC_HIRE_COST
		elif GameState.hire_merc():
			var newnm := GameState.merc_name(GameState.merc_count() - 1)
			line = Loc.pair("「毎度！『%s』を雇った。(資源-%d)　甲板を巡回して侵入者と戦う。今 %d/%d 人だ。」",
				"\"Done. Hired %s. (RES-%d) They will patrol the deck. Guards: %d/%d.\"") \
				% [newnm, GameState.MERC_HIRE_COST, GameState.merc_count(), GameState.MERC_MAX]
			TsgAudio.pickup(true)
	elif role == "kana":
		# A BANK: deposit resources; the balance auto-repairs the hull (lab burns it).
		if GameState.stockpile >= GameState.STOCKPILE_MAX:
			line = Loc.pair("「修復ファンドは満タンよ（%d）。これ以上は預かれないわ。」", "\"The repair fund is full (%d). I cannot store more.\"") % GameState.STOCKPILE_MAX
		elif GameState.res_pool <= 0:
			line = Loc.pair("「預ける資源がないわ。採ってきて。預けたぶんだけ母艦を自動修復するから。」", "\"You have no resources to deposit. Bring some back and I will fuel auto-repair.\"")
		else:
			var moved := GameState.deposit_repair_bank()
			line = Loc.pair("「資源%dを修復ファンドに預かったわ。これを燃料に母艦を自動修復する。残高 %d/%d。」",
				"\"Deposited %d resources. Carrier auto-repair will burn this fund. Balance %d/%d.\"") \
				% [moved, GameState.stockpile, GameState.STOCKPILE_MAX]
			TsgAudio.pickup(true)
	elif role == "mess":
		# 食堂のコック: a meal restores every guard's HP for a flat resource cost.
		if GameState.merc_count() == 0:
			line = Loc.pair("「まだ衛兵がいないな。ヒカリさんの所で雇ってきな。」", "\"No guards yet. Hire some from Hikari first.\"")
		elif not GameState.mercs_need_heal():
			line = Loc.pair("「みんなピンピンしてるよ。腹が減ったらまたおいで。」", "\"Everyone is healthy. Come back when they are hungry.\"")
		elif GameState.res_pool < GameState.MESS_HEAL_COST:
			line = Loc.pair("「材料が足りん。資源を %d 持ってきてくれ。」", "\"Need ingredients. Bring %d resources.\"") % GameState.MESS_HEAL_COST
		else:
			GameState.res_pool -= GameState.MESS_HEAL_COST
			GameState.heal_all_mercs()
			line = Loc.pair("「さあ食え！衛兵全員、体力全快だ。(資源-%d)」", "\"Eat up! All guards fully healed. (RES-%d)\"") % GameState.MESS_HEAL_COST
			TsgAudio.pickup(true)
	elif role == "merc":
		# A hired gun: flavor + a status read on what it's doing.
		var fighting := _nearest_enemy(Vector2(crew.global_position.x, crew.global_position.y),
			MERC_ENGAGE_R) != null
		var ml: Array
		if fighting:
			ml = [[ "「下がってろ、ここは任せな！」", "\"Stay back. I have this.\"" ],
				[ "「侵入者は一匹残らず片付ける。」", "\"I will clear every boarder.\"" ]]
		else:
			ml = [[ "「金の分はきっちり働くぜ。」", "\"I earn my pay.\"" ],
				[ "「侵入者が来たら俺が出る。安心しな。」", "\"If boarders come, I move first.\"" ],
				[ "「母艦は守ってやる。掘りはあんたの仕事だ。」", "\"I guard the carrier. You mine.\"" ],
				[ "「次の戦いが待ち遠しいぜ。」", "\"Can hardly wait for the next fight.\"" ]]
		var mpair: Array = ml[randi() % ml.size()]
		line = Loc.pair(String(mpair[0]), String(mpair[1]))
	elif bool(crew.get_meta("repair")):
		if GameState.carrier_hull >= GameState.CARRIER_HULL_MAX:
			line = Loc.pair("「母艦は万全だ。気にするな。」", "\"Carrier is in perfect shape. Do not worry.\"")
		elif int(crew.get_meta("repair_cd")) > 0:
			line = Loc.pair("「さっき直したばかりだ。少し待ってくれ。」", "\"I just repaired it. Give me a moment.\"")
		elif GameState.res_pool < REPAIR_COST:
			line = Loc.pair("「資源が足りない。採ってきてくれ。」", "\"Not enough resources. Bring some back.\"")
		else:
			GameState.res_pool -= REPAIR_COST
			GameState.carrier_hull = minf(GameState.CARRIER_HULL_MAX,
				GameState.carrier_hull + REPAIR_AMOUNT)
			crew.set_meta("repair_cd", REPAIR_CD)
			line = Loc.pair("「資源%dで外壁を直した。(耐久+%d)」", "\"Repaired the outer hull for %d resources. (Hull +%d)\"") % [REPAIR_COST, int(REPAIR_AMOUNT)]
			TsgAudio.pickup(true)   # SE: repair done (positive chime)
	else:
		var lines: Array = CHATTER.get(job, [["「ご苦労さん。」", "\"Good work out there.\""]])
		var pair_line: Array = lines[randi() % lines.size()]
		line = Loc.pair(String(pair_line[0]), String(pair_line[1]))
	TsgAudio.block_chip()       # SE: conversation blip
	# VIP names already include their title; don't double it up.
	var who: String = nm if bool(crew.get_meta("vip", false)) else "%s (%s)" % [nm, _job_label(job)]
	_show_dialogue(who, line)

func _job_label(job: String) -> String:
	match job:
		"操舵手": return Loc.pair("操舵手", "Helm")
		"通信士": return Loc.pair("通信士", "Comms")
		"砲手": return Loc.pair("砲手", "Gunner")
		"医療班": return Loc.pair("医療班", "Medic")
		"補給係": return Loc.pair("補給係", "Supply")
		"料理長": return Loc.pair("料理長", "Chef")
		"艦長": return Loc.pair("艦長", "Captain")
		"商人": return Loc.pair("商人", "Merchant")
		"博士": return Loc.pair("博士", "Doctor")
		_: return job

func _show_dialogue(who: String, line: String) -> void:
	if _dialogue == null:
		return
	_dialogue.text = "%s\n%s" % [who, line]
	_dialogue.visible = true
	_dialogue_until = Time.get_ticks_msec() / 1000.0 + 3.5

func _update_deck_hud() -> void:
	if _hull_label != null:
		_hull_label.text = Loc.pair(
			"母艦耐久 %d/%d    資源 %d    修復ファンド %d/%d",
			"Carrier hull %d/%d    RES %d    Repair fund %d/%d") % [
			int(GameState.carrier_hull), int(GameState.CARRIER_HULL_MAX), GameState.res_pool,
			GameState.stockpile, GameState.STOCKPILE_MAX]
	# Below deck (where ヒカリ商人 hires them), list the hired guns: count + names + HP.
	if _merc_label != null:
		_merc_label.visible = (_floor == 1)
		if _floor == 1:
			var names := []
			for i in GameState.mercs.size():
				names.append("%s(HP%d)" % [GameState.merc_name(i), int(ceil(GameState.merc_hp(i)))])
			var roster: String = Loc.pair("（まだ雇っていない）", "(none hired)") if names.is_empty() else ", ".join(names)
			_merc_label.text = Loc.pair("傭兵 %d/%d   %s", "Mercenaries %d/%d   %s") % [
				GameState.merc_count(), GameState.MERC_MAX, roster]
	if _dialogue != null and _dialogue.visible \
			and Time.get_ticks_msec() / 1000.0 > _dialogue_until:
		_dialogue.visible = false
	if _hint != null and GameState.carrier_takeover:
		_hint.text = Loc.pair("侵入者 残り%d体 - ホールドで撃って排除しろ", "Boarders left: %d - hold position and fire") % GameState.takeover_boarders

# --- Hint -----------------------------------------------------------------

func _build_hint() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(0, 0)
	_hint.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85))
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.visible = false
	layer.add_child(_hint)
	# Carrier hull / resources readout (top-left), shown only while walking.
	_hull_label = Label.new()
	_hull_label.position = Vector2(24, 56)
	_hull_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_hull_label.add_theme_font_size_override("font_size", 22)
	_hull_label.visible = false
	layer.add_child(_hull_label)
	# Hired-gun roster (count + names) — shown below deck, where they're hired.
	_merc_label = Label.new()
	_merc_label.position = Vector2(24, 92)
	_merc_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	_merc_label.add_theme_font_size_override("font_size", 20)
	_merc_label.visible = false
	layer.add_child(_merc_label)
	# Crew speech bubble (lower-center).
	_dialogue = Label.new()
	_dialogue.add_theme_color_override("font_color", Color(1.0, 1.0, 0.85))
	_dialogue.add_theme_font_size_override("font_size", 24)
	_dialogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue.visible = false
	layer.add_child(_dialogue)

func _update_hint() -> void:
	if _hint == null:
		return
	var show: bool = _can_enter()
	_hint.visible = show
	if show:
		_hint.text = Loc.t("CLICK TO DISEMBARK - walk the deck")
		var sz := get_viewport().get_visible_rect().size
		_hint.position = Vector2(sz.x * 0.5 - 170.0, sz.y - 70.0)

# --- Carrier interior (command room) --------------------------------------
# Below deck is the ship interior — a ferry-like layout of rooms partitioned by solid
# walls and a central corridor, staffed by milling crew — reached by a stern elevator
# with a seamless dive cinematic. Pure ambient easter-egg for now (no activities yet).

func _cur_pilot_z() -> float:
	return _floor_pilot_z(_floor)

# Per-floor pilot stand height and camera distance — keeps the lift cinematic and the
# steady camera in sync as floors are added.
func _floor_pilot_z(f: int) -> float:
	match f:
		2: return _onsen_pilot_z
		1: return _interior_pilot_z
		_: return _pilot_z

func _person_floor_scale(f: int = _floor) -> float:
	match f:
		2: return 1.5
		1: return 1.4
		_: return 1.0

func _floor_cam_z(f: int) -> float:
	match f:
		2: return _onsen_z + ONSEN_ZOOM + _walk_zoom_offset
		1: return _interior_z + INTERIOR_ZOOM + _walk_zoom_offset
		_: return _deck_z + ZOOM_DIST + _walk_zoom_offset

func _floor_z(f: int) -> float:
	match f:
		2: return _onsen_z
		1: return _interior_z
		_: return _deck_z

# Stern elevator pad in world space (the carrier is frozen during deck-walk).
func _pad_world() -> Vector3:
	var c := _carrier.global_position
	return Vector3(c.x, c.y - Mothership.DECK_LEN * 0.5 + HATCH_Y_OFF, 0.0)

# Hot-spring entrance in world space — now the centre of the 温泉入口 room (one of the 6 区画).
func _onsen_pad_world() -> Vector3:
	var c := _carrier.global_position
	for rm: Dictionary in _room_layout():
		if rm["role"] == "onsen":
			return Vector3(c.x + rm["cx"], c.y + rm["cy"], 0.0)
	return Vector3(c.x, c.y + 1.0, 0.0)

# Top-down camera, framed to the current floor (deck or interior), following the lead.
func _update_floor_camera() -> void:
	var focus := _carrier.global_position
	if not _pilots.is_empty():
		focus = _pilots[0].global_position
	var c := _carrier.global_position
	var hw: float
	var hl: float
	var cam_z: float
	if _floor == 2:
		hw = ONSEN_HW - 0.2
		hl = ONSEN_HL - 0.2
		cam_z = _floor_cam_z(_floor)
	elif _floor == 1:
		# Follow the lead closely (small clamp) so the maze unfolds as you explore.
		hw = INTERIOR_HW - 0.2
		hl = INTERIOR_HL - 0.2
		cam_z = _floor_cam_z(_floor)
	else:
		hw = Mothership.FULL_HALF_W + 0.4
		hl = Mothership.DECK_LEN * 0.5 + 0.4
		cam_z = _floor_cam_z(_floor)
	var cam_target := Vector3(
		clampf(focus.x, c.x - hw, c.x + hw),
		clampf(focus.y, c.y - hl, c.y + hl),
		cam_z)
	_cam.global_position = _cam.global_position.lerp(cam_target, ENTER_LERP)
	_cam.rotation = _cam.rotation.lerp(Vector3.ZERO, ENTER_LERP)

func _add_local_box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = pos
	parent.add_child(m)

# An interior wall: a visible box (local to the room) AND a solid collision rect (world
# XY) that pilots/staff are pushed out of. hx/hy are half-sizes; c is the carrier pos.
func _add_wall(c: Vector3, lx: float, ly: float, hx: float, hy: float, mat: StandardMaterial3D) -> void:
	var wh := 0.26
	_add_local_box(_interior_root, Vector3(hx * 2.0, hy * 2.0, wh), Vector3(lx, ly, wh * 0.5), mat)
	_walls.append(Rect2(c.x + lx - hx, c.y + ly - hy, hx * 2.0, hy * 2.0))

# Push a point out of any wall it lands in, along the axis of least penetration (slides
# along walls). Pilots move far less than wall thickness per frame, so no tunnelling.
# Clamp to the interior rectangle + resolve maze walls. Floor-independent so it works
# during the descent build (when _floor is still 0).
func _clamp_interior(gx: float, gy: float) -> Vector2:
	var cx: float = _carrier.global_position.x
	var cy: float = _carrier.global_position.y
	var ix := clampf(gx - cx, -(INTERIOR_HW - EDGE_MARGIN), INTERIOR_HW - EDGE_MARGIN)
	var iy := clampf(gy - cy, -(INTERIOR_HL - EDGE_MARGIN), INTERIOR_HL - EDGE_MARGIN)
	return _resolve_walls(Vector2(cx + ix, cy + iy), _walls)

# Clamp to the onsen rectangle + resolve its partition / tub-rim walls.
func _clamp_onsen(gx: float, gy: float) -> Vector2:
	var cx: float = _carrier.global_position.x
	var cy: float = _carrier.global_position.y
	var ix := clampf(gx - cx, -(ONSEN_HW - EDGE_MARGIN), ONSEN_HW - EDGE_MARGIN)
	var iy := clampf(gy - cy, -(ONSEN_HL - EDGE_MARGIN), ONSEN_HL - EDGE_MARGIN)
	return _resolve_walls(Vector2(cx + ix, cy + iy), _onsen_walls)

func _resolve_walls(pt: Vector2, walls: Array[Rect2]) -> Vector2:
	# Iterate a few times so a point pushed out of one wall into another settles, and
	# test against walls fattened by WALL_PAD so corners / diagonal gaps can't be clipped.
	for _pass in 4:
		var hit := false
		for raw: Rect2 in walls:
			var r := raw.grow(WALL_PAD)
			if r.has_point(pt):
				hit = true
				var left := pt.x - r.position.x
				var right := r.position.x + r.size.x - pt.x
				var down := pt.y - r.position.y
				var up := r.position.y + r.size.y - pt.y
				var m := minf(minf(left, right), minf(down, up))
				if m == left:
					pt.x = r.position.x - 0.001
				elif m == right:
					pt.x = r.position.x + r.size.x + 0.001
				elif m == down:
					pt.y = r.position.y - 0.001
				else:
					pt.y = r.position.y + r.size.y + 0.001
		if not hit:
			break
	return pt

# --- Stern elevator / hatch -----------------------------------------------

func _build_hatch() -> void:
	if _hatch_root != null:
		return
	_hatch_root = Node3D.new()
	add_child(_hatch_root)
	var pad := _pad_world()
	_hatch_root.global_position = Vector3(pad.x, pad.y, _deck_z)
	# Glowing pad ring so the lift reads as interactive.
	var pad_mat := StandardMaterial3D.new()
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.albedo_color = Color(0.3, 0.9, 1.0)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.3, 0.85, 1.0)
	pad_mat.emission_energy_multiplier = 1.4
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = HATCH_HALF * 0.92
	torus.outer_radius = HATCH_HALF * 1.05
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.material_override = pad_mat
	ring.position = Vector3(0, 0, 0.05)
	_hatch_root.add_child(ring)
	_hatch_root.set_meta("ring", ring)
	# Two sliding doors covering the pad; they part in X to open.
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.4, 0.44, 0.52)
	door_mat.metallic = 0.6
	door_mat.roughness = 0.4
	_hatch_doors.clear()
	for sgn: float in [-1.0, 1.0]:
		var d := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(HATCH_HALF, HATCH_HALF * 2.0, 0.05)
		d.mesh = box
		d.material_override = door_mat
		d.position = Vector3(sgn * HATCH_HALF * 0.5, 0, 0.06)
		d.set_meta("sgn", sgn)
		_hatch_root.add_child(d)
		_hatch_doors.append(d)

func _teardown_hatch() -> void:
	_hatch_doors.clear()
	if _hatch_root != null and is_instance_valid(_hatch_root):
		_hatch_root.queue_free()
	_hatch_root = null
	_hatch_open = 0.0

# Track the lead on the pad, animate the doors, and show the ride prompt.
func _update_elevator(lead: Node3D) -> void:
	var pad := _pad_world()
	var lead2 := Vector2(lead.global_position.x, lead.global_position.y)
	_on_pad = lead2.distance_to(Vector2(pad.x, pad.y)) < ELEV_R
	if _floor == 0:
		_on_onsen_pad = false   # the bow stair only exists below deck
	if _hatch_root != null:
		var want := 1.0 if (_on_pad and _floor == 0) else 0.0
		_hatch_open = lerpf(_hatch_open, want, 0.2)
		for d in _hatch_doors:
			var sgn: float = d.get_meta("sgn")
			d.position.x = sgn * (HATCH_HALF * 0.5 + _hatch_open * HATCH_HALF * 0.95)
		var ring := _hatch_root.get_meta("ring") as MeshInstance3D
		if ring != null:
			var rm := ring.material_override as StandardMaterial3D
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
			rm.emission_energy_multiplier = (2.2 + pulse) if _on_pad else (1.0 + pulse * 0.4)
	_update_floor_hint()

# Walking prompt for the current floor / pad — shared by the deck, command room and onsen.
func _update_floor_hint() -> void:
	if _hint == null or GameState.carrier_takeover:
		return
	if _on_pad:
		_hint.text = Loc.pair("クリックで甲板へ戻る", "Click to return to deck") if _floor == 1 else Loc.pair("クリックで艦内（司令室）へ降りる", "Click to descend to command room")
	elif _on_onsen_pad:
		_hint.text = Loc.pair("クリックで司令室へ戻る", "Click to return to command room") if _floor == 2 else Loc.pair("クリックで温泉へ降りる", "Click to descend to the hot spring")
	elif _floor == 2:
		_hint.text = (Loc.pair("湯船でクリック＝立ち上がって移動再開", "Click in the bath to stand and move again") if _resting
			else Loc.pair("温泉 - 湯船でクリックすると浸かって休む   光る階段で司令室へ   ESC:発進", "Hot spring - click a bath to rest   Glowing stair: command room   ESC: launch"))
	elif _floor == 1:
		_hint.text = Loc.pair("船内（迷路）- 艦尾パッドで甲板／艦首の階段で温泉へ   ESC:発進", "Interior maze - stern pad: deck / bow stair: hot spring   ESC: launch")
	else:
		_hint.text = Loc.pair(
			"攻撃サークルで自動攻撃   乗組員に近づいてクリックで会話/修理(再クリックで終了)   艦尾パッドで艦内へ   自機に戻ってクリック or ESC:発進",
			"Auto-fire in attack circles   Click crew to talk/repair   Stern pad: interior   Click ship or ESC: launch")

# Track the lead on the bow stair (the onsen entrance), pulse its marker and set _on_onsen_pad.
func _update_onsen_pad(lead: Node3D) -> void:
	var pad := _onsen_pad_world()
	var lead2 := Vector2(lead.global_position.x, lead.global_position.y)
	_on_onsen_pad = lead2.distance_to(Vector2(pad.x, pad.y)) < ELEV_R
	# Pulse whichever marker exists on this floor (entrance ring above / return ring below).
	var ring: MeshInstance3D = null
	if _floor == 1 and _interior_root != null:
		ring = _interior_root.get_meta("onsen_ring", null) as MeshInstance3D
	elif _floor == 2 and _onsen_root != null:
		ring = _onsen_root.get_meta("return_ring", null) as MeshInstance3D
	if ring != null:
		var rm := ring.material_override as StandardMaterial3D
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
		rm.emission_energy_multiplier = (2.2 + pulse) if _on_onsen_pad else (1.0 + pulse * 0.4)

# Which world pad links two adjacent floors: stern lift for deck↔command, bow stair below.
func _pad_for_floors(a: int, b: int) -> Vector3:
	return _pad_world() if mini(a, b) == 0 else _onsen_pad_world()

func _begin_floor_change(target_floor: int) -> void:
	if _transition != "" or _pilots.is_empty():
		return
	var descend := target_floor > _floor
	if descend and GameState.carrier_takeover:
		return   # don't wander below while the deck is being boarded
	# Build the destination floor lazily (cost hidden under the dive cinematic).
	if target_floor == 1 and _interior_root == null:
		_build_interior()
	elif target_floor == 2 and _onsen_root == null:
		_build_onsen()
	_resting = false   # standing up to ride the lift
	_trans_from_floor = _floor
	_trans_to_floor = target_floor
	_active_pad = _pad_for_floors(_floor, target_floor)
	_transition = "descend" if descend else "ascend"
	_trans_t = 0
	_trans_cam_from = _cam.global_position
	_talking_to = null
	# The stern hatch doors snap open for a deck↔command ride.
	if mini(_trans_from_floor, _trans_to_floor) == 0:
		_hatch_open = 1.0
		for d in _hatch_doors:
			var sgn: float = d.get_meta("sgn")
			d.position.x = sgn * (HATCH_HALF * 0.5 + HATCH_HALF * 0.95)
	for p in _pilots:
		p.set_meta("ride_from", p.global_position)
		p.set_meta("vel", Vector3.ZERO)
	TsgAudio.pickup(false)   # SE: lift engages

# The dive: pilots ride the lift, the camera follows down through the pad and each floor
# slab is revealed/hidden as the lens crosses its plane (deck signage fades for the cue).
func _run_floor_transition() -> void:
	_trans_t += 1
	var k := clampf(float(_trans_t) / float(TRANS_FRAMES), 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var descend := _trans_to_floor > _trans_from_floor
	var pad := _active_pad
	var z0 := _floor_pilot_z(_trans_from_floor)
	var z1 := _floor_pilot_z(_trans_to_floor)
	for i in _pilots.size():
		var p := _pilots[i]
		var from: Vector3 = p.get_meta("ride_from", p.global_position)
		var slot := Vector2(pad.x, pad.y) + Vector2(0, -float(i) * FOLLOW_SPACING)
		p.global_position = Vector3(lerpf(from.x, slot.x, e), lerpf(from.y, slot.y, e), lerpf(z0, z1, e))
	var cam_z0 := _floor_cam_z(_trans_from_floor)
	var cam_z1 := _floor_cam_z(_trans_to_floor)
	var cam_xy := Vector2(_trans_cam_from.x, _trans_cam_from.y).lerp(Vector2(pad.x, pad.y), e)
	_cam.global_position = Vector3(cam_xy.x, cam_xy.y, lerpf(cam_z0, cam_z1, e))
	_cam.rotation = Vector3.ZERO
	# Hide each floor slab once the lens drops below it (it would only occlude from above).
	_update_floor_visibility()
	# Fade the deck signage only on rides that touch the deck (the cue for surfacing/diving).
	if _trans_from_floor == 0 or _trans_to_floor == 0:
		var sig := clampf((1.0 - e) if descend else e, 0.0, 1.0)
		for lbl in _deck_labels:
			if is_instance_valid(lbl):
				(lbl as Label3D).modulate.a = sig
	if k >= 1.0:
		_floor = _trans_to_floor
		if _floor == 0:
			for lbl in _deck_labels:
				if is_instance_valid(lbl):
					(lbl as Label3D).modulate.a = 1.0
			_left_ship = true
		_transition = ""

# Show only the floors at/above the camera; the slab a floor sits on occludes anything
# below it from the top-down lens, so floors deeper than the lens are simply hidden.
func _update_floor_visibility() -> void:
	# Never show a floor slab ABOVE the one we're on/heading to — otherwise a pulled-back
	# camera (sitting above that slab) renders it as a bogus CEILING over the floor below.
	# `top` = shallowest floor in play (0 = deck). 0=deck,1=command room,2=onsen.
	var top := mini(_trans_from_floor, _trans_to_floor) if _transition != "" else _floor
	_sync_floor_actor_visibility(top)
	if _carrier != null and is_instance_valid(_carrier):
		_carrier.visible = _cam.global_position.z >= _deck_z and top <= 0
	if _interior_root != null and is_instance_valid(_interior_root):
		_interior_root.visible = _cam.global_position.z >= _interior_z and top <= 1
	if _onsen_root != null and is_instance_valid(_onsen_root):
		_onsen_root.visible = _cam.global_position.z >= _onsen_z and top <= 2

# Steady-state: show ONLY the floor we're standing on (deeper floors would peek out past
# the slab above them, which is wider than the carrier deck).
func _show_only_floor(f: int) -> void:
	_sync_floor_actor_visibility(f)
	if _carrier != null and is_instance_valid(_carrier):
		_carrier.visible = f == 0
	if _interior_root != null and is_instance_valid(_interior_root):
		_interior_root.visible = f == 1
	if _onsen_root != null and is_instance_valid(_onsen_root):
		_onsen_root.visible = f == 2

func _set_node_visible(node: Node3D, show: bool) -> void:
	if node != null and is_instance_valid(node):
		node.visible = show

func _set_nodes_visible(nodes: Array, show: bool) -> void:
	for node in nodes:
		if node is Node3D and is_instance_valid(node):
			(node as Node3D).visible = show

func _sync_floor_actor_visibility(f: int) -> void:
	var deck_show := f == 0
	var interior_show := f == 1
	_set_nodes_visible(_crew, deck_show)
	_set_nodes_visible(_mercs, deck_show)
	_set_nodes_visible(_boarders, deck_show)
	_set_nodes_visible(_drops, deck_show)
	_set_node_visible(_hatch_root, deck_show)
	_set_node_visible(_enemy_arrow, deck_show)
	_set_nodes_visible(_staff, interior_show)
	_set_nodes_visible(_interior_vips, interior_show)

# --- Command-room geometry & staff ----------------------------------------

# The fixed below-deck floor plan, in LOCAL coords (+y = bow). A central corridor runs from
# the stern lift lobby up to the bow command room, with 3 rooms (区画) per side. Each room is
# {role, side(-1/+1), x0,x1,y0,y1, cx,cy}. Roles: bank(カナ)/guard(ヒカリ)/mess(食堂)/
# onsen(温泉入口)/empty(空室×2). Used by the builder AND by _onsen_pad_world / VIP spawn so
# the structure stays consistent.
func _room_layout() -> Array:
	var rooms := []
	var rh := (ROOM_TOP - ROOM_BOT) / 3.0
	var left_roles := ["bank", "onsen", "empty"]    # bottom → top
	var right_roles := ["guard", "mess", "empty"]
	for row in 3:
		var y0 := ROOM_BOT + float(row) * rh
		var y1 := y0 + rh
		var cy := (y0 + y1) * 0.5
		rooms.append({"role": right_roles[row], "side": 1.0,
			"x0": ROOM_INNER, "x1": ROOM_OUTER, "y0": y0, "y1": y1,
			"cx": (ROOM_INNER + ROOM_OUTER) * 0.5, "cy": cy})
		rooms.append({"role": left_roles[row], "side": -1.0,
			"x0": -ROOM_OUTER, "x1": -ROOM_INNER, "y0": y0, "y1": y1,
			"cx": -(ROOM_INNER + ROOM_OUTER) * 0.5, "cy": cy})
	return rooms

func _build_interior() -> void:
	if _interior_root != null:
		return
	_interior_root = Node3D.new()
	add_child(_interior_root)
	var c := _carrier.global_position
	_interior_root.global_position = Vector3(c.x, c.y, _interior_z)
	_walls.clear()
	var pad := _pad_world()
	var lobby := Vector2(pad.x - c.x, pad.y - c.y)
	# Solid floor under it all — a touch emissive for a warm, cozy base glow.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.26, 0.30, 0.40)
	floor_mat.metallic = 0.3
	floor_mat.roughness = 0.6
	floor_mat.emission_enabled = true
	floor_mat.emission = Color(0.14, 0.17, 0.28)
	floor_mat.emission_energy_multiplier = 0.25
	_add_local_box(_interior_root, Vector3(INTERIOR_HW * 2.0, INTERIOR_HL * 2.0, 0.04),
		Vector3(0, 0, -0.02), floor_mat)
	_build_lobby(c, lobby)
	# Walls (visible + solid): perimeter, then each room's box (with a corridor doorway),
	# then the bow command room. Faintly self-lit so the halls read as glowing ship interior.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.46, 0.52, 0.62)
	wall_mat.metallic = 0.5
	wall_mat.roughness = 0.45
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.16, 0.22, 0.34)
	wall_mat.emission_energy_multiplier = 0.35
	_add_wall(c, 0.0, INTERIOR_HL, INTERIOR_HW, MAZE_WT, wall_mat)
	_add_wall(c, 0.0, -INTERIOR_HL, INTERIOR_HW, MAZE_WT, wall_mat)
	_add_wall(c, INTERIOR_HW, 0.0, MAZE_WT, INTERIOR_HL, wall_mat)
	_add_wall(c, -INTERIOR_HW, 0.0, MAZE_WT, INTERIOR_HL, wall_mat)
	for rm: Dictionary in _room_layout():
		_build_room_walls(c, rm, wall_mat)
		_furnish_room(c, rm)
	_build_command_walls(c, wall_mat)
	_spawn_interior_lights(c)
	_scatter_interior_props(c)
	# Stern lift pad marker (same world x/y as the deck hatch) in the lobby.
	var pad_mat := StandardMaterial3D.new()
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.albedo_color = Color(0.3, 0.9, 1.0)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.3, 0.85, 1.0)
	pad_mat.emission_energy_multiplier = 1.6
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = HATCH_HALF * 0.92
	torus.outer_radius = HATCH_HALF * 1.05
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.material_override = pad_mat
	ring.position = Vector3(pad.x - c.x, pad.y - c.y, 0.06)
	_interior_root.add_child(ring)
	_spawn_interior_staff()
	_spawn_interior_vips()

# A room enclosure: top/bottom/outer walls plus an inner (corridor-side) wall split into
# two segments to leave a doorway centred on the room.
func _build_room_walls(c: Vector3, rm: Dictionary, mat: StandardMaterial3D) -> void:
	var x0: float = rm["x0"]
	var x1: float = rm["x1"]
	var y0: float = rm["y0"]
	var y1: float = rm["y1"]
	var midx := (x0 + x1) * 0.5
	var hw := (x1 - x0) * 0.5
	var hh := (y1 - y0) * 0.5
	var cy := (y0 + y1) * 0.5
	_add_wall(c, midx, y1, hw, MAZE_WT, mat)            # top
	_add_wall(c, midx, y0, hw, MAZE_WT, mat)            # bottom
	# Outer (perimeter-facing) full-height wall; inner (corridor) wall has the doorway.
	var outer_x: float = x1 if rm["side"] > 0.0 else x0
	var inner_x: float = x0 if rm["side"] > 0.0 else x1
	_add_wall(c, outer_x, cy, MAZE_WT, hh, mat)
	var seg_bot := (cy - ROOM_DOOR_HALF - y0) * 0.5
	if seg_bot > 0.01:
		_add_wall(c, inner_x, y0 + seg_bot, MAZE_WT, seg_bot, mat)
	var seg_top := (y1 - (cy + ROOM_DOOR_HALF)) * 0.5
	if seg_top > 0.01:
		_add_wall(c, inner_x, y1 - seg_top, MAZE_WT, seg_top, mat)

# The bow command room: top + two sides + a bottom wall with a central corridor doorway.
func _build_command_walls(c: Vector3, mat: StandardMaterial3D) -> void:
	var cy := (CMD_Y0 + CMD_Y1) * 0.5
	var hh := (CMD_Y1 - CMD_Y0) * 0.5
	_add_wall(c, 0.0, CMD_Y1, CMD_HW, MAZE_WT, mat)      # top
	_add_wall(c, -CMD_HW, cy, MAZE_WT, hh, mat)          # left
	_add_wall(c, CMD_HW, cy, MAZE_WT, hh, mat)           # right
	var seg := (CMD_HW - CORR_HW) * 0.5                  # bottom split by the corridor mouth
	_add_wall(c, -(CORR_HW + CMD_HW) * 0.5, CMD_Y0, seg, MAZE_WT, mat)
	_add_wall(c, (CORR_HW + CMD_HW) * 0.5, CMD_Y0, seg, MAZE_WT, mat)

# Per-room signage + fixed fittings (the interactive NPCs are placed in _spawn_interior_vips).
func _furnish_room(c: Vector3, rm: Dictionary) -> void:
	var lx: float = rm["cx"]
	var ly: float = rm["cy"]
	match rm["role"]:
		"bank":
			_room_sign(Loc.pair("カナ博士 銀行", "DR. KANA BANK"), Color(0.55, 0.9, 1.0), lx, rm["y1"] - 0.22)
		"guard":
			_room_sign(Loc.pair("ヒカリ商人 衛兵ルーム", "HIKARI GUARD ROOM"), Color(1.0, 0.82, 0.35), lx, rm["y1"] - 0.22)
		"mess":
			_room_sign(Loc.pair("食堂", "MESS HALL"), Color(1.0, 0.7, 0.45), lx, rm["y1"] - 0.22)
		"onsen":
			_build_onsen_entrance(c, Vector2(lx, ly))
		"empty":
			_room_sign(Loc.pair("空室（準備中）", "EMPTY ROOM"), Color(0.6, 0.66, 0.74), lx, rm["y1"] - 0.22)

# A flat room-name sign hovering at the top of a room (camera-facing, always on top).
func _room_sign(text: String, color: Color, lx: float, ly: float) -> void:
	var s := Label3D.new()
	s.text = text
	s.font_size = 72
	s.pixel_size = 0.0011
	s.modulate = color
	s.outline_size = 10
	s.outline_modulate = Color(0, 0, 0, 0.85)
	s.no_depth_test = true
	s.position = Vector3(lx, ly, 0.42)
	_interior_root.add_child(s)

func _teardown_interior() -> void:
	for s in _staff:
		if is_instance_valid(s):
			s.queue_free()
	_staff.clear()
	for v in _interior_vips:
		if is_instance_valid(v):
			v.queue_free()
	_interior_vips.clear()
	_glass_stars.clear()
	_interior_props.clear()    # nodes are children of _interior_root (freed below)
	_interior_lights.clear()   # nodes are children of _interior_root (freed below)
	_walls.clear()
	if _interior_root != null and is_instance_valid(_interior_root):
		_interior_root.queue_free()
	_interior_root = null

# --- Hot spring (温泉) ------------------------------------------------------
# A second descent from the BOW of the command room: a moody, dimly-lit bath hall —
# entrance landing → central corridor → 男女別の更衣室 → それぞれの湯船. Built lazily on
# first descent, kept until takeoff. Only one floor is ever shown at a time.

# The glowing stair-down marker placed in the command-room maze (child of _interior_root).
func _build_onsen_entrance(c: Vector3, ent: Vector2) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.5, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.25)
	m.emission_energy_multiplier = 1.6
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = HATCH_HALF * 0.92
	tor.outer_radius = HATCH_HALF * 1.05
	tor.rings = 48
	tor.ring_segments = 6
	ring.mesh = tor
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.material_override = m
	ring.position = Vector3(ent.x, ent.y, 0.06)
	_interior_root.add_child(ring)
	_interior_root.set_meta("onsen_ring", ring)
	var ent_sign := Label3D.new()
	ent_sign.text = Loc.pair("♨ 温泉", "HOT SPRING")
	ent_sign.font_size = 80
	ent_sign.pixel_size = 0.0014
	ent_sign.modulate = Color(1.0, 0.6, 0.4)
	ent_sign.outline_size = 10
	ent_sign.outline_modulate = Color(0, 0, 0, 0.85)
	ent_sign.no_depth_test = true
	ent_sign.position = Vector3(ent.x, ent.y + 0.22, 0.4)
	_interior_root.add_child(ent_sign)

func _build_onsen() -> void:
	if _onsen_root != null:
		return
	_onsen_root = Node3D.new()
	add_child(_onsen_root)
	var c := _carrier.global_position
	_onsen_root.global_position = Vector3(c.x, c.y, _onsen_z)
	_onsen_walls.clear()
	# --- Materials (dark, warm, wet — the dim hot-spring mood) ---
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.10, 0.11, 0.13)
	floor_mat.metallic = 0.2
	floor_mat.roughness = 0.5
	floor_mat.emission_enabled = true
	floor_mat.emission = Color(0.06, 0.07, 0.09)
	floor_mat.emission_energy_multiplier = 0.2
	var wall_mat := StandardMaterial3D.new()      # warm timber walls
	wall_mat.albedo_color = Color(0.26, 0.17, 0.11)
	wall_mat.metallic = 0.0
	wall_mat.roughness = 0.8
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.12, 0.07, 0.04)
	wall_mat.emission_energy_multiplier = 0.3
	var rim_mat := StandardMaterial3D.new()       # pale stone tub rim
	rim_mat.albedo_color = Color(0.42, 0.43, 0.46)
	rim_mat.metallic = 0.1
	rim_mat.roughness = 0.7
	var water_mat := ShaderMaterial.new()          # the real hot-spring water (shader)
	water_mat.shader = ONSEN_WATER_SHADER
	water_mat.set_shader_parameter("deep_color", Color(0.04, 0.26, 0.30))
	water_mat.set_shader_parameter("shallow_color", Color(0.42, 0.74, 0.72))
	water_mat.set_shader_parameter("sheen_color", Color(0.90, 1.0, 0.98))
	water_mat.set_shader_parameter("water_alpha", 0.86)
	water_mat.set_shader_parameter("glow", 0.5)
	water_mat.set_shader_parameter("ripple_speed", 1.0)
	water_mat.set_shader_parameter("ripple_scale", 9.0)
	water_mat.render_priority = 1   # draw over the glass star-window beneath it
	var locker_mat := StandardMaterial3D.new()    # changing-room lockers
	locker_mat.albedo_color = Color(0.30, 0.24, 0.18)
	locker_mat.metallic = 0.3
	locker_mat.roughness = 0.5
	locker_mat.emission_enabled = true
	locker_mat.emission = Color(0.10, 0.08, 0.05)
	locker_mat.emission_energy_multiplier = 0.3
	# --- Floor slab + perimeter ---
	var W := ONSEN_HW
	var H := ONSEN_HL
	_add_local_box(_onsen_root, Vector3(W * 2.0, H * 2.0, 0.04), Vector3(0, 0, -0.02), floor_mat)
	_add_onsen_wall(c, 0.0, H, W, MAZE_WT, wall_mat)
	_add_onsen_wall(c, 0.0, -H, W, MAZE_WT, wall_mat)
	_add_onsen_wall(c, W, 0.0, MAZE_WT, H, wall_mat)
	_add_onsen_wall(c, -W, 0.0, MAZE_WT, H, wall_mat)
	# --- Fixed bathhouse flow: 受付(reception, AT the landing) → 男湯(north)/女湯(south) に分岐
	# → 更衣室 → 洗い場 → 大浴場(複数の湯船). A central reception band splits the two wings,
	# joined by central doorways you walk through. ---
	var rp := _onsen_pad_world()
	var rl := Vector2(rp.x - c.x, rp.y - c.y)
	var land := rl                       # arrival point = the reception
	var rec_y0 := land.y - 0.5           # reception band (spans the landing)
	var rec_y1 := land.y + 0.5
	# Reception ↔ each wing (full-width wall, central door).
	_build_partition_with_gap(c, -W, W, rec_y1, 0.0, 0.85, wall_mat)
	_build_partition_with_gap(c, -W, W, rec_y0, 0.0, 0.85, wall_mat)
	# Reception desk beside the landing (clear of the return ring) + signage.
	_add_local_box(_onsen_root, Vector3(1.1, 0.16, 0.18), Vector3(land.x + 1.0, land.y, 0.09), locker_mat)
	_onsen_sign(Loc.pair("♨ 受付", "RECEPTION"), Color(1.0, 0.72, 0.45), land.x, land.y + 0.3)
	_onsen_sign(Loc.pair("〜 つかの間の極楽 〜", "- brief paradise -"), Color(0.8, 0.85, 0.7), land.x, land.y - 0.28, 50)
	_onsen_sign(Loc.pair("男湯 ↑", "MEN ↑"), Color(0.5, 0.74, 1.0), 0.0, rec_y1 + 0.2)
	_onsen_sign(Loc.pair("女湯 ↓", "WOMEN ↓"), Color(1.0, 0.55, 0.65), 0.0, rec_y0 - 0.2)
	# Each wing flows 更衣室 → 洗い場 → 大浴場. North = 男湯 (blue), south = 女湯 (red).
	_build_bath_wing(c, rec_y1, 1.0, Color(0.5, 0.74, 1.0), wall_mat, locker_mat, rim_mat, water_mat)
	_build_bath_wing(c, rec_y0, -1.0, Color(1.0, 0.55, 0.65), wall_mat, locker_mat, rim_mat, water_mat)
	# Bathside trappings (buckets, towels, garden rocks) + a reception lantern.
	_scatter_onsen_decor(c, W, H, rim_mat)
	_onsen_lantern(land.x - 0.9, land.y, Color(1.0, 0.7, 0.45))
	# Return stair ring at the landing (same world XY as the onsen entrance above).
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.5, 0.3)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.45, 0.25)
	ring_mat.emission_energy_multiplier = 1.6
	var ring := MeshInstance3D.new()
	var rtor := TorusMesh.new()
	rtor.inner_radius = HATCH_HALF * 0.92
	rtor.outer_radius = HATCH_HALF * 1.05
	rtor.rings = 48
	rtor.ring_segments = 6
	ring.mesh = rtor
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.material_override = ring_mat
	ring.position = Vector3(rl.x, rl.y, 0.06)
	_onsen_root.add_child(ring)
	_onsen_root.set_meta("return_ring", ring)
	# A tall glowing light-beam over the stair so the exit is visible from anywhere in the
	# hall (it blooms via the world glow), plus a vermilion 鳥居 framing it.
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(1.0, 0.55, 0.32, 0.5)
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(1.0, 0.5, 0.28)
	beam_mat.emission_energy_multiplier = 2.4
	var beam := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.05
	bcyl.bottom_radius = 0.11
	bcyl.height = 1.3
	bcyl.radial_segments = 12
	beam.mesh = bcyl
	beam.material_override = beam_mat
	beam.rotation_degrees = Vector3(90, 0, 0)   # stand it upright (+Z)
	beam.position = Vector3(rl.x, rl.y, 0.65)
	_onsen_root.add_child(beam)
	_onsen_root.set_meta("exit_beam", beam)
	_build_torii(rl, Color(0.85, 0.18, 0.12))

# A simple vermilion torii gate marking the exit landing.
func _build_torii(at: Vector2, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = col * 0.5
	m.emission_energy_multiplier = 0.6
	var span := 0.34
	_add_local_box(_onsen_root, Vector3(0.07, 0.07, 0.66), Vector3(at.x - span, at.y, 0.33), m)
	_add_local_box(_onsen_root, Vector3(0.07, 0.07, 0.66), Vector3(at.x + span, at.y, 0.33), m)
	_add_local_box(_onsen_root, Vector3(span * 2.4, 0.08, 0.08), Vector3(at.x, at.y - 0.03, 0.68), m)  # 笠木
	_add_local_box(_onsen_root, Vector3(span * 2.0, 0.06, 0.06), Vector3(at.x, at.y, 0.56), m)         # 貫

# A glass-floor panel showing the cosmos below — soak and watch the stars drift.
func _build_star_window(lx: float, ly: float, hx: float, hy: float) -> void:
	# Dark void backing.
	var void_mat := StandardMaterial3D.new()
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_mat.albedo_color = Color(0.02, 0.03, 0.06)
	void_mat.emission_enabled = true
	void_mat.emission = Color(0.05, 0.07, 0.16)
	void_mat.emission_energy_multiplier = 0.5
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(hx * 2.0, hy * 2.0, 0.02)
	panel.mesh = pm
	panel.material_override = void_mat
	panel.position = Vector3(lx, ly, 0.012)   # just above the floor, beneath the clear water
	_onsen_root.add_child(panel)
	# Scattered stars (tiny emissive specks).
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(1.0, 1.0, 0.95)
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.8, 0.9, 1.0)
	star_mat.emission_energy_multiplier = 2.2
	for _i in 26:
		var s := MeshInstance3D.new()
		s.mesh = _ball_mesh(randf_range(0.006, 0.014))
		s.material_override = star_mat
		s.position = Vector3(lx + randf_range(-hx, hx) * 0.95, ly + randf_range(-hy, hy) * 0.95, 0.026)
		_onsen_root.add_child(s)

# One bath wing off the reception: 更衣室(lockers) → 洗い場(wash stations) → 大浴場(a big
# central bath flanked by two smaller tubs). `edge` is the reception-side y; `dir` is +1
# (north / 男湯) or -1 (south / 女湯); `accent` tints its signs & lanterns.
func _build_bath_wing(c: Vector3, edge: float, dir: float, accent: Color, wall_mat: StandardMaterial3D, locker_mat: StandardMaterial3D, rim_mat: StandardMaterial3D, water_mat: ShaderMaterial) -> void:
	var W := ONSEN_HW
	var H := ONSEN_HL
	var far := dir * H                 # this wing's outer wall
	var d1 := edge + dir * 0.75        # 更衣室 | 洗い場 divider
	var d2 := edge + dir * 1.5         # 洗い場 | 大浴場 divider
	_build_partition_with_gap(c, -W, W, d1, 0.0, 0.85, wall_mat)
	_build_partition_with_gap(c, -W, W, d2, 0.0, 0.85, wall_mat)
	# 更衣室: lockers along both side walls.
	var ch_y := (edge + d1) * 0.5
	_build_lockers(c, -W * 0.5, ch_y, W * 0.4, locker_mat)
	_build_lockers(c, W * 0.5, ch_y, W * 0.4, locker_mat)
	# 洗い場: a row of wash stations (体を洗うエリア) before the baths.
	var wash_y := (d1 + d2) * 0.5
	_build_wash_area(c, wash_y, dir, accent, locker_mat)
	# 大浴場: a big central bath (glass star-window beneath) flanked by two smaller tubs.
	var bath_y := (d2 + far) * 0.5
	_build_star_window(0.0, bath_y, 1.4, 0.78)
	_add_tub(c, 0.0, bath_y, 1.0, 0.62, rim_mat, water_mat)
	_add_tub(c, -W * 0.6, bath_y, 0.55, 0.5, rim_mat, water_mat)
	_add_tub(c, W * 0.6, bath_y, 0.5, 0.46, rim_mat, water_mat)
	_onsen_sign(Loc.pair("洗い場", "WASH AREA"), accent.lerp(Color.WHITE, 0.35), W * 0.62, wash_y, 50)
	_onsen_sign(Loc.pair("大浴場", "MAIN BATH"), accent, 0.0, far - dir * 0.28)
	_onsen_lantern(-W + 0.35, bath_y, accent)
	_onsen_lantern(W - 0.35, bath_y, accent)

# A row of wash stations across the wash room: each a low faucet/mirror panel with a stool
# and (on some) a wooden bucket. Pure decoration (no collision) — the 体を洗うエリア.
func _build_wash_area(c: Vector3, cy: float, dir: float, accent: Color, wood_mat: StandardMaterial3D) -> void:
	var W := ONSEN_HW
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.55, 0.58, 0.62)
	panel_mat.metallic = 0.5
	panel_mat.roughness = 0.4
	panel_mat.emission_enabled = true
	panel_mat.emission = accent
	panel_mat.emission_energy_multiplier = 0.35
	var n := 5
	for i in n:
		var x := -W * 0.72 + (float(i) + 0.5) / float(n) * W * 1.44
		_add_local_box(_onsen_root, Vector3(0.22, 0.04, 0.26), Vector3(x, cy - dir * 0.18, 0.13), panel_mat)
		var stool := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.06
		sc.bottom_radius = 0.06
		sc.height = 0.05
		stool.mesh = sc
		stool.material_override = wood_mat
		stool.position = Vector3(x, cy + dir * 0.06, 0.03)
		_onsen_root.add_child(stool)
		if i % 2 == 0:
			var bucket := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = 0.045
			bc.bottom_radius = 0.038
			bc.height = 0.05
			bucket.mesh = bc
			bucket.material_override = wood_mat
			bucket.position = Vector3(x + 0.07, cy + dir * 0.06, 0.06)
			_onsen_root.add_child(bucket)

# A horizontal partition from x0..x1 at height y, with a doorway gap centered on gap_cx.
func _build_partition_with_gap(c: Vector3, x0: float, x1: float, y: float, gap_cx: float, gap_w: float, mat: StandardMaterial3D) -> void:
	var a_r := gap_cx - gap_w * 0.5
	if a_r > x0:
		_add_onsen_wall(c, (x0 + a_r) * 0.5, y, (a_r - x0) * 0.5, MAZE_WT, mat)
	var b_l := gap_cx + gap_w * 0.5
	if x1 > b_l:
		_add_onsen_wall(c, (b_l + x1) * 0.5, y, (x1 - b_l) * 0.5, MAZE_WT, mat)

# A row of lockers (decorative boxes) centered on (cx, cy), spanning ±half_span in x.
func _build_lockers(c: Vector3, cx: float, cy: float, half_span: float, mat: StandardMaterial3D) -> void:
	var n := 6
	var cw := half_span * 2.0 / float(n) * 0.82
	for i in n:
		var lx := cx - half_span + (float(i) + 0.5) / float(n) * half_span * 2.0
		_add_local_box(_onsen_root, Vector3(cw, 0.12, 0.32), Vector3(lx, cy, 0.16), mat)

# A sunken tub you can WADE INTO: a low stone rim, a shimmering shader water surface,
# drifting steam and a couple of soaking bathers. Registered in _tubs so pilots sink in.
func _add_tub(c: Vector3, lx: float, ly: float, hx: float, hy: float, rim_mat: StandardMaterial3D, water_mat: ShaderMaterial) -> void:
	var rh := 0.12
	_add_local_box(_onsen_root, Vector3(hx * 2.0, 0.07, rh), Vector3(lx, ly + hy, rh * 0.5), rim_mat)
	_add_local_box(_onsen_root, Vector3(hx * 2.0, 0.07, rh), Vector3(lx, ly - hy, rh * 0.5), rim_mat)
	_add_local_box(_onsen_root, Vector3(0.07, hy * 2.0, rh), Vector3(lx - hx, ly, rh * 0.5), rim_mat)
	_add_local_box(_onsen_root, Vector3(0.07, hy * 2.0, rh), Vector3(lx + hx, ly, rh * 0.5), rim_mat)
	# Soakable: no wall collision — instead remember the footprint so pilots sink when over it.
	_tubs.append({"x": c.x + lx, "y": c.y + ly, "hx": hx, "hy": hy, "wz": _onsen_z + 0.075})
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hx * 1.9, hy * 1.9)
	pm.subdivide_width = 20   # let the shader's gentle swell actually undulate the surface
	pm.subdivide_depth = 20
	water.mesh = pm
	water.material_override = water_mat
	water.rotation_degrees = Vector3(-90, 0, 0)   # lie flat, facing up toward the lens
	water.position = Vector3(lx, ly, 0.085)
	_onsen_root.add_child(water)
	# Steam curling up off the water.
	for _s in 3:
		var bx := lx + randf_range(-hx * 0.7, hx * 0.7)
		var by := ly + randf_range(-hy * 0.7, hy * 0.7)
		var puff := MeshInstance3D.new()
		puff.mesh = _ball_mesh(randf_range(0.045, 0.075))
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.92, 0.96, 1.0, 0.22)
		puff.material_override = sm
		puff.position = Vector3(bx, by, 0.12)
		puff.set_meta("base", Vector3(bx, by, 0.12))
		puff.set_meta("spd", randf_range(0.15, 0.3))
		puff.set_meta("ofs", randf())
		_onsen_root.add_child(puff)
		_steam.append(puff)
	# A couple of bathers soaking, just their heads above the water.
	for _b in 2:
		var bx := lx + randf_range(-hx * 0.6, hx * 0.6)
		var by := ly + randf_range(-hy * 0.6, hy * 0.6)
		var head := MeshInstance3D.new()
		head.mesh = _ball_mesh(0.05)
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.95, 0.78, 0.66)
		hm.roughness = 0.6
		head.material_override = hm
		head.position = Vector3(bx, by, 0.1)
		head.set_meta("base", Vector3(bx, by, 0.1))
		head.set_meta("phase", randf() * TAU)
		_onsen_root.add_child(head)
		_bathers.append(head)

func _add_onsen_wall(c: Vector3, lx: float, ly: float, hx: float, hy: float, mat: StandardMaterial3D) -> void:
	var wh := 0.34
	_add_local_box(_onsen_root, Vector3(hx * 2.0, hy * 2.0, wh), Vector3(lx, ly, wh * 0.5), mat)
	_onsen_walls.append(Rect2(c.x + lx - hx, c.y + ly - hy, hx * 2.0, hy * 2.0))

func _onsen_sign(text: String, color: Color, lx: float, ly: float, font_size: int = 84) -> void:
	var s := Label3D.new()
	s.text = text
	s.font_size = font_size
	s.pixel_size = 0.0016
	s.modulate = color
	s.outline_size = 12
	s.outline_modulate = Color(0, 0, 0, 0.85)
	s.no_depth_test = true
	s.position = Vector3(lx, ly, 0.45)
	_onsen_root.add_child(s)

func _onsen_lantern(lx: float, ly: float, col: Color) -> void:
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = col
	lm.emission_enabled = true
	lm.emission = col
	lm.emission_energy_multiplier = 2.0
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.16)
	box.mesh = bm
	box.material_override = lm
	box.position = Vector3(lx, ly, 0.3)
	_onsen_root.add_child(box)
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = 2.0
	light.light_energy = 1.0   # deliberately dim — moody half-light
	light.shadow_enabled = false
	light.position = Vector3(lx, ly, 0.55)
	light.set_meta("base", 1.0)
	light.set_meta("phase", randf() * TAU)
	_onsen_root.add_child(light)
	_onsen_lights.append(light)

# Bathside trappings dotted along the back walls of the two bath halls: wooden buckets,
# folded-towel stacks and a few garden rocks — the trappings of an unhurried, elegant soak.
func _scatter_onsen_decor(c: Vector3, W: float, H: float, rim_mat: StandardMaterial3D) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.34, 0.18)
	wood.roughness = 0.7
	var towel := StandardMaterial3D.new()
	towel.albedo_color = Color(0.92, 0.93, 0.95)
	towel.roughness = 0.9
	towel.emission_enabled = true
	towel.emission = Color(0.2, 0.22, 0.26)
	towel.emission_energy_multiplier = 0.2
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.2, 0.21, 0.23)
	rock.roughness = 0.95
	# Mirror a handful of props on each side, hugging the perimeter so they never block a tub.
	for sx: float in [-1.0, 1.0]:
		# Wooden bucket (a little cylinder).
		var bucket := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.07
		bc.bottom_radius = 0.06
		bc.height = 0.1
		bucket.mesh = bc
		bucket.material_override = wood
		bucket.position = Vector3(sx * (W - 0.28), -H * 0.32, 0.05)
		_onsen_root.add_child(bucket)
		# Folded towel stack.
		_add_local_box(_onsen_root, Vector3(0.16, 0.1, 0.04), Vector3(sx * (W - 0.26), -H * 0.5, 0.02), towel)
		_add_local_box(_onsen_root, Vector3(0.15, 0.09, 0.04), Vector3(sx * (W - 0.26), -H * 0.5, 0.06), towel)
		# Garden rocks beside the big tub (flattened spheres).
		for _r in 3:
			var stone := MeshInstance3D.new()
			stone.mesh = _ball_mesh(randf_range(0.06, 0.11))
			stone.material_override = rock
			stone.scale = Vector3(1.0, 1.0, 0.5)
			stone.position = Vector3(sx * (W - 0.22) + randf_range(-0.1, 0.1), -H * 0.78 + randf_range(-0.15, 0.15), 0.03)
			_onsen_root.add_child(stone)

func _teardown_onsen() -> void:
	_steam.clear()        # children of _onsen_root (freed below)
	_bathers.clear()
	_ripples.clear()
	_tubs.clear()
	_onsen_lights.clear()
	_onsen_walls.clear()
	_on_onsen_pad = false
	if _onsen_root != null and is_instance_valid(_onsen_root):
		_onsen_root.queue_free()
	_onsen_root = null

# The tub the point (gx, gy) is inside (empty dict if none) — used to sink pilots in.
func _tub_at(gx: float, gy: float) -> Dictionary:
	for tb: Dictionary in _tubs:
		if absf(gx - tb["x"]) <= tb["hx"] and absf(gy - tb["y"]) <= tb["hy"]:
			return tb
	return {}

func _update_onsen(lead: Node3D) -> void:
	_on_pad = false   # the stern lift doesn't exist down here
	if _enemy_arrow != null:
		_enemy_arrow.visible = false
	# Breadcrumb back to the bow stair so you never lose the way out (always on when not on it).
	if _nav_arrow != null:
		var lead2 := Vector2(lead.global_position.x, lead.global_position.y)
		var pad := _onsen_pad_world()
		var to := Vector2(pad.x, pad.y) - lead2
		var dist := to.length()
		if dist < ELEV_R * 1.3:
			_nav_arrow.visible = false
		else:
			_nav_arrow.visible = true
			var dir := to / dist
			_nav_arrow.global_position = Vector3(lead2.x + dir.x * 0.07, lead2.y + dir.y * 0.07, _onsen_pilot_z + 0.07)
			_nav_arrow.rotation = Vector3(0.0, 0.0, atan2(dir.y, dir.x))
	var t := Time.get_ticks_msec() / 1000.0
	# Pilots sink into the water when they wade into a tub (smooth, and rise on the way out).
	for p in _pilots:
		var tub := _tub_at(p.global_position.x, p.global_position.y)
		var s := float(p.get_meta("soak", 0.0))
		s = clampf(s + (0.07 if not tub.is_empty() else -0.12), 0.0, 1.0)
		p.set_meta("soak", s)
		if not tub.is_empty():
			p.set_meta("soak_z", float(tub["wz"]))
		var sz := float(p.get_meta("soak_z", _onsen_pilot_z))
		p.global_position.z = lerpf(_onsen_pilot_z, sz, smoothstep(0.0, 1.0, s))
		# A soaking pilot sends out slow ripple rings.
		if s > 0.6:
			var cd := int(p.get_meta("ripple_cd", 0)) - 1
			if cd <= 0 and _ripples.size() < 18:
				_spawn_ripple(p.global_position.x, p.global_position.y)
				cd = randi_range(40, 70)
			p.set_meta("ripple_cd", cd)
	_update_ripples()
	for lt in _onsen_lights:
		if is_instance_valid(lt):
			var base: float = lt.get_meta("base", 1.0)
			var ph: float = lt.get_meta("phase", 0.0)
			(lt as OmniLight3D).light_energy = base * (0.7 + 0.3 * sin(t * 1.2 + ph))
	var beam := _onsen_root.get_meta("exit_beam", null) as MeshInstance3D
	if beam != null:
		beam.scale = Vector3(1.0, 0.9 + 0.1 * sin(t * 2.0), 1.0)   # cylinder axis is local Y
	for s in _steam:
		if is_instance_valid(s):
			var b: Vector3 = s.get_meta("base")
			var rise: float = fmod(t * float(s.get_meta("spd")) + float(s.get_meta("ofs")), 1.0)
			s.position = Vector3(b.x + sin(t * 0.7 + float(s.get_meta("ofs")) * 6.0) * 0.05, b.y, b.z + rise * 0.5)
			var sm := s.material_override as StandardMaterial3D
			if sm != null:
				sm.albedo_color.a = 0.26 * (1.0 - rise)
	for bh in _bathers:
		if is_instance_valid(bh):
			var bb: Vector3 = bh.get_meta("base")
			bh.position.z = bb.z + sin(t * 1.4 + float(bh.get_meta("phase"))) * 0.012
	# Soaking humbles you: a full dip clears the 慢心 gauge and shows a proverb (once per dip;
	# re-arms when you climb out of the water).
	var lead_soak := float(lead.get_meta("soak", 0.0))
	if lead_soak < 0.05:
		_onsen_soak_done = false
	elif lead_soak > 0.8 and not _onsen_soak_done:
		_onsen_soak_done = true
		if GameState.reset_hubris():
			var pr: Dictionary = GameState.HUBRIS_PROVERBS[randi() % GameState.HUBRIS_PROVERBS.size()]
			_show_dialogue(Loc.pair("♨ 慢心を解いた", "Hubris dissolved"), String(pr[Loc.language]))
			_dialogue_until = Time.get_ticks_msec() / 1000.0 + 6.5
			TsgAudio.pickup(true)
	# Auto-hide the speech bubble down here too (the floor-1/0 HUD updater doesn't run on 2).
	if _dialogue != null and _dialogue.visible \
			and Time.get_ticks_msec() / 1000.0 > _dialogue_until:
		_dialogue.visible = false
	_update_floor_hint()

# A flat expanding ring on the water surface, faded out as it grows, then recycled.
func _spawn_ripple(gx: float, gy: float) -> void:
	var c := _carrier.global_position
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.97, 1.0, 0.5)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.85, 0.95)
	m.emission_energy_multiplier = 1.2
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.035
	tor.outer_radius = 0.05
	tor.rings = 24
	tor.ring_segments = 5
	ring.mesh = tor
	ring.material_override = m
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(gx - c.x, gy - c.y, 0.095)
	ring.set_meta("age", 0.0)
	_onsen_root.add_child(ring)
	_ripples.append(ring)

func _update_ripples() -> void:
	for i in range(_ripples.size() - 1, -1, -1):
		var r := _ripples[i]
		if not is_instance_valid(r):
			_ripples.remove_at(i)
			continue
		var age := float(r.get_meta("age")) + 0.02
		r.set_meta("age", age)
		var grow := 1.0 + age * 9.0
		r.scale = Vector3(grow, grow, 1.0)
		var mm := r.material_override as StandardMaterial3D
		if mm != null:
			mm.albedo_color.a = clampf(0.5 * (1.0 - age / 1.2), 0.0, 0.5)
		if age >= 1.2:
			r.queue_free()
			_ripples.remove_at(i)

func _spawn_interior_staff() -> void:
	for i in INTERIOR_STAFF:
		# Varied hues so the crowd reads as a bustling, diverse crew.
		var col := Color.from_hsv(randf(), randf_range(0.35, 0.7), randf_range(0.85, 1.0))
		var st := _make_pilot(col)   # reuse the little sphere body
		st.scale = Vector3.ONE * _person_floor_scale(1)
		add_child(st)
		var sp := _random_interior_point()
		var cc := _clamp_interior(sp.x, sp.y)   # keep spawns out of walls (floor-independent)
		st.global_position = Vector3(cc.x, cc.y, _interior_pilot_z)
		st.set_meta("vel", Vector3.ZERO)
		st.set_meta("home", Vector3(cc.x, cc.y, _interior_pilot_z))
		st.set_meta("target", Vector3(cc.x, cc.y, _interior_pilot_z))
		st.set_meta("phase", randf() * TAU)
		st.set_meta("pause", randi_range(0, 120))
		st.set_meta("rt", randi_range(120, 320))
		_staff.append(st)

func _random_interior_point() -> Vector3:
	var c := _carrier.global_position
	var hw := INTERIOR_HW - EDGE_MARGIN - 0.2
	var hl := INTERIOR_HL - EDGE_MARGIN - 0.2
	return Vector3(c.x + randf_range(-hw, hw), c.y + randf_range(-hl, hl), _interior_pilot_z)

# Interactive NPCs, each stationed in their own room: カナ博士 (bank), ヒカリ商人 (guard room,
# hires mercs), コック (food, heals the mercs), and タクト艦長 in the bow command room.
func _spawn_interior_vips() -> void:
	var c := _carrier.global_position
	var z := _interior_pilot_z
	for rm: Dictionary in _room_layout():
		var rx: float = c.x + rm["cx"]
		var ry: float = c.y + float(rm["cy"]) - 0.1
		match rm["role"]:
			"bank":
				var kana := _make_vip(Color(0.5, 0.85, 1.0), "カナ博士", "博士", "kana")
				kana.global_position = Vector3(rx, ry, z)
				_interior_vips.append(kana)
				_build_vip_station(kana.global_position, Color(0.4, 0.8, 1.0))
			"guard":
				var hik := _make_vip(Color(1.0, 0.78, 0.25), "ヒカリ商人", "商人", "hikari")
				hik.global_position = Vector3(rx, ry, z)
				_interior_vips.append(hik)
				_build_vip_station(hik.global_position, Color(1.0, 0.7, 0.2))
			"mess":
				var cook := _make_vip(Color(1.0, 0.6, 0.4), "コック", "料理長", "mess")
				cook.global_position = Vector3(rx, ry, z)
				_interior_vips.append(cook)
				_build_vip_station(cook.global_position, Color(1.0, 0.55, 0.3))
	# タクト艦長 in the bow command room (moved here from the deck).
	var cap := _make_vip(Color(1.0, 0.82, 0.2), "タクト艦長", "艦長", "captain")
	cap.global_position = Vector3(c.x, c.y + (CMD_Y0 + CMD_Y1) * 0.5 - 0.15, z)
	_interior_vips.append(cap)
	_build_vip_station(cap.global_position, Color(1.0, 0.8, 0.3))

func _make_vip(tint: Color, nm: String, job: String, role: String) -> Node3D:
	var v := _make_crew(tint, nm, job, true)
	v.scale = Vector3.ONE * _person_floor_scale(1)
	add_child(v)
	v.set_meta("name", nm)
	v.set_meta("job", job)
	v.set_meta("vip", true)
	v.set_meta("role", role)
	v.set_meta("repair", false)
	v.set_meta("repair_cd", 0)
	v.set_meta("phase", randf() * TAU)
	v.set_meta("vel", Vector3.ZERO)
	return v

# A small lit station (counter + holo sign) behind a VIP so it reads as their room/booth.
func _build_vip_station(gpos: Vector3, glow: Color) -> void:
	if _interior_root == null:
		return
	var c := _carrier.global_position
	var lx := gpos.x - c.x
	var ly := gpos.y - c.y
	var counter := StandardMaterial3D.new()
	counter.albedo_color = Color(0.22, 0.20, 0.26)
	counter.metallic = 0.6
	counter.roughness = 0.4
	_add_local_box(_interior_root, Vector3(0.34, 0.12, 0.10), Vector3(lx, ly + 0.13, 0.05), counter)
	var sign := StandardMaterial3D.new()
	sign.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sign.albedo_color = glow
	sign.emission_enabled = true
	sign.emission = glow
	sign.emission_energy_multiplier = 2.4
	_add_local_box(_interior_root, Vector3(0.30, 0.03, 0.02), Vector3(lx, ly + 0.20, 0.16), sign)
	for sx in [-1.0, 1.0]:
		_add_local_box(_interior_root, Vector3(0.03, 0.03, 0.16),
			Vector3(lx + sx * 0.15, ly + 0.13, 0.08), sign)

# Show/hide VIP tags + talk-rings by distance to the lead (mirrors _update_crew), and a
# gentle idle bob. Runs on floor 1.
func _update_interior_vips(lead: Node3D) -> void:
	if lead == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var lead_xy := Vector2(lead.global_position.x, lead.global_position.y)
	for v in _interior_vips:
		if not is_instance_valid(v):
			continue
		var dist := lead_xy.distance_to(Vector2(v.global_position.x, v.global_position.y))
		var tag := v.get_meta("tag") as Label3D
		if tag != null:
			tag.visible = dist < TALK_R * 3.0
		var ring := v.get_meta("ring") as MeshInstance3D
		if ring != null:
			ring.visible = dist < TALK_R * 3.0
			if ring.visible:
				var in_range := dist <= TALK_R
				var rm := ring.material_override as StandardMaterial3D
				rm.albedo_color = Color(0.4, 1.0, 0.5, 0.85) if in_range else Color(0.4, 0.9, 1.0, 0.4)
				rm.emission = Color(0.4, 1.0, 0.5) if in_range else Color(0.4, 0.9, 1.0)
				rm.emission_energy_multiplier = (1.5 + pulse) if in_range else 0.8
		var phase: float = v.get_meta("phase")
		v.global_position.z = _interior_pilot_z + absf(sin(t * 3.0 + phase)) * 0.010

# The VIP nearest the lead within talk range, or null (used on floor 1).
func _vip_near_lead() -> Node3D:
	if _pilots.is_empty():
		return null
	var lead2 := Vector2(_pilots[0].global_position.x, _pilots[0].global_position.y)
	var best: Node3D = null
	var bd := TALK_R
	for v in _interior_vips:
		if not is_instance_valid(v):
			continue
		var d := lead2.distance_to(Vector2(v.global_position.x, v.global_position.y))
		if d < bd:
			bd = d
			best = v
	return best

# Fantastical accent lighting: glowing lamp posts dotted through the maze, the first few
# also casting a real pulsing pool of colored light (cozy, dreamy interior).
func _spawn_interior_lights(c: Vector3) -> void:
	var pal := [Color(0.3, 0.9, 1.0), Color(0.7, 0.45, 1.0), Color(1.0, 0.45, 0.8),
		Color(0.4, 1.0, 0.8), Color(1.0, 0.7, 0.35), Color(0.55, 0.8, 1.0)]
	for i in 9:
		var col: Color = pal[i % pal.size()]
		var p := _random_interior_point()
		var cc := _clamp_interior(p.x, p.y)
		var lx := cc.x - c.x
		var ly := cc.y - c.y
		# Always-visible glowing lamp box.
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = col
		lm.emission_enabled = true
		lm.emission = col
		lm.emission_energy_multiplier = 2.4
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 0.2)
		box.mesh = bm
		box.material_override = lm
		box.position = Vector3(lx, ly, 0.12)
		_interior_root.add_child(box)
		# The first several also cast a real (pulsing) light.
		if i < 6:
			var light := OmniLight3D.new()
			light.light_color = col
			light.omni_range = 1.7
			light.light_energy = 1.4
			light.shadow_enabled = false
			light.position = Vector3(lx, ly, 0.4)
			light.set_meta("base", 1.4)
			light.set_meta("phase", randf() * TAU)
			_interior_root.add_child(light)
			_interior_lights.append(light)

# A corridor point clear of walls and the lobby, in LOCAL coords (relative to c). Returns
# Vector2.INF if no clear spot turned up — callers just skip that prop.
func _free_interior_local(c: Vector3, lobby: Vector2) -> Vector2:
	for _try in 12:
		var p := _random_interior_point()
		var cc := _clamp_interior(p.x, p.y)
		var l := Vector2(cc.x - c.x, cc.y - c.y)
		if l.distance_to(lobby) < LOBBY_R + 0.15:
			continue   # keep the grand foyer uncluttered
		return l
	return Vector2.INF

# Props strewn through the maze so the corridors never read as bare halls: glowing floor
# panels, slowly-spinning holo-terminals, supply crates and warm braziers. All kept low so
# the top-down camera sees them without anything occluding the floor.
func _scatter_interior_props(c: Vector3) -> void:
	var pad := _pad_world()
	var lobby := Vector2(pad.x - c.x, pad.y - c.y)
	var pal := [Color(0.3, 0.9, 1.0), Color(0.7, 0.45, 1.0), Color(1.0, 0.45, 0.8),
		Color(0.4, 1.0, 0.8), Color(1.0, 0.7, 0.35), Color(0.55, 0.8, 1.0)]
	# Glowing floor inlay panels — flush with the floor, pure decoration.
	for i in 12:
		var lp := _free_interior_local(c, lobby)
		if lp == Vector2.INF:
			continue
		var col: Color = pal[randi() % pal.size()]
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = col
		pm.emission_enabled = true
		pm.emission = col
		pm.emission_energy_multiplier = 1.2
		var tile := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(MAZE_CELL * 0.5, MAZE_CELL * 0.5, 0.012)
		tile.mesh = tm
		tile.material_override = pm
		tile.position = Vector3(lp.x, lp.y, 0.008)
		_interior_root.add_child(tile)
	# Holo-terminals: a dark console with a hovering, slowly-spinning glyph bar above it.
	for i in 6:
		var lp := _free_interior_local(c, lobby)
		if lp == Vector2.INF:
			continue
		var col: Color = pal[randi() % pal.size()]
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.2, 0.23, 0.3)
		base_mat.metallic = 0.6
		base_mat.roughness = 0.4
		_add_local_box(_interior_root, Vector3(0.12, 0.08, 0.1), Vector3(lp.x, lp.y, 0.05), base_mat)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color = Color(col.r, col.g, col.b, 0.7)
		gm.emission_enabled = true
		gm.emission = col
		gm.emission_energy_multiplier = 2.0
		var glyph := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = Vector3(0.14, 0.03, 0.015)
		glyph.mesh = gb
		glyph.material_override = gm
		glyph.position = Vector3(lp.x, lp.y, 0.2)
		glyph.set_meta("spin", randf_range(0.6, 1.4))
		_interior_root.add_child(glyph)
		_interior_props.append(glyph)
	# Supply crates: little clusters of dim metallic boxes with a faint edge glow.
	for i in 4:
		var lp := _free_interior_local(c, lobby)
		if lp == Vector2.INF:
			continue
		var edge: Color = pal[randi() % pal.size()]
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.32, 0.3, 0.26)
		cm.metallic = 0.3
		cm.roughness = 0.6
		cm.emission_enabled = true
		cm.emission = edge * 0.4
		cm.emission_energy_multiplier = 0.5
		for k in randi_range(2, 3):
			var s := randf_range(0.1, 0.14)
			_add_local_box(_interior_root, Vector3(s, s, s),
				Vector3(lp.x + randf_range(-0.05, 0.05), lp.y + randf_range(-0.05, 0.05), s * 0.5), cm)
	# Braziers: a small cup with a glowing orb; the first couple cast a real pulsing light.
	for i in 4:
		var lp := _free_interior_local(c, lobby)
		if lp == Vector2.INF:
			continue
		var col: Color = pal[randi() % pal.size()]
		var cupm := StandardMaterial3D.new()
		cupm.albedo_color = Color(0.4, 0.36, 0.3)
		cupm.metallic = 0.5
		cupm.roughness = 0.4
		_add_local_box(_interior_root, Vector3(0.07, 0.07, 0.14), Vector3(lp.x, lp.y, 0.07), cupm)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = col
		fm.emission_enabled = true
		fm.emission = col
		fm.emission_energy_multiplier = 2.6
		var fo := MeshInstance3D.new()
		fo.mesh = _ball_mesh(0.05)
		fo.material_override = fm
		fo.position = Vector3(lp.x, lp.y, 0.17)
		_interior_root.add_child(fo)
		if i < 2:
			var bl := OmniLight3D.new()
			bl.light_color = col
			bl.omni_range = 1.2
			bl.light_energy = 1.0
			bl.shadow_enabled = false
			bl.position = Vector3(lp.x, lp.y, 0.25)
			bl.set_meta("base", 1.0)
			bl.set_meta("phase", randf() * TAU)
			_interior_root.add_child(bl)
			_interior_lights.append(bl)

# The grand entrance lobby around the lift: a round gold/marble inlay, a ring of glowing
# columns, and a warm chandelier — a luxurious foyer the maze fans out from.
func _build_lobby(c: Vector3, lobby: Vector2) -> void:
	# Round marble/gold floor inlay.
	var inlay := StandardMaterial3D.new()
	inlay.albedo_color = Color(0.5, 0.44, 0.3)
	inlay.metallic = 0.6
	inlay.roughness = 0.25
	inlay.emission_enabled = true
	inlay.emission = Color(0.6, 0.5, 0.3)
	inlay.emission_energy_multiplier = 0.4
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = LOBBY_R * 0.95
	cyl.bottom_radius = LOBBY_R * 0.95
	cyl.height = 0.03
	cyl.radial_segments = 40
	disc.mesh = cyl
	disc.material_override = inlay
	disc.rotation_degrees = Vector3(90, 0, 0)
	disc.position = Vector3(lobby.x, lobby.y, -0.005)
	_interior_root.add_child(disc)
	# Glowing ring trim inlaid in the floor.
	var trim_mat := StandardMaterial3D.new()
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trim_mat.albedo_color = Color(1.0, 0.85, 0.4)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(1.0, 0.8, 0.35)
	trim_mat.emission_energy_multiplier = 1.8
	var trim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = LOBBY_R * 0.78
	tor.outer_radius = LOBBY_R * 0.84
	tor.rings = 48
	tor.ring_segments = 8
	trim.mesh = tor
	trim.material_override = trim_mat
	trim.rotation_degrees = Vector3(90, 0, 0)
	trim.position = Vector3(lobby.x, lobby.y, 0.015)
	_interior_root.add_child(trim)
	# Ring of solid columns with glowing caps — the grand foyer.
	var pillar := StandardMaterial3D.new()
	pillar.albedo_color = Color(0.7, 0.66, 0.56)
	pillar.metallic = 0.4
	pillar.roughness = 0.4
	var cap := StandardMaterial3D.new()
	cap.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cap.albedo_color = Color(1.0, 0.85, 0.45)
	cap.emission_enabled = true
	cap.emission = Color(1.0, 0.8, 0.4)
	cap.emission_energy_multiplier = 2.0
	# Radial gold inlay spokes fanning out under the columns — an ornate sunburst foyer floor.
	var spoke_mat := StandardMaterial3D.new()
	spoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spoke_mat.albedo_color = Color(0.9, 0.72, 0.35)
	spoke_mat.emission_enabled = true
	spoke_mat.emission = Color(0.85, 0.65, 0.3)
	spoke_mat.emission_energy_multiplier = 1.0
	for k in 12:
		var sa := float(k) / 12.0 * TAU
		var spoke := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(LOBBY_R * 0.7, 0.02, 0.006)
		spoke.mesh = sb
		spoke.material_override = spoke_mat
		spoke.position = Vector3(lobby.x + cos(sa) * LOBBY_R * 0.42, lobby.y + sin(sa) * LOBBY_R * 0.42, 0.004)
		spoke.rotation_degrees = Vector3(0, 0, rad_to_deg(sa))
		_interior_root.add_child(spoke)
	var pr := LOBBY_R * 0.82
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var px := lobby.x + cos(a) * pr
		var py := lobby.y + sin(a) * pr
		_add_local_box(_interior_root, Vector3(0.16, 0.16, 0.06), Vector3(px, py, 0.03), pillar)  # base
		_add_local_box(_interior_root, Vector3(0.1, 0.1, 0.45), Vector3(px, py, 0.22), pillar)    # shaft
		_add_local_box(_interior_root, Vector3(0.14, 0.14, 0.05), Vector3(px, py, 0.45), cap)     # cap
		_walls.append(Rect2(c.x + px - 0.07, c.y + py - 0.07, 0.14, 0.14))
	# Warm chandelier: a real pulsing light + a glowing orb up high (clears the landing).
	var chand := OmniLight3D.new()
	chand.light_color = Color(1.0, 0.85, 0.55)
	chand.omni_range = LOBBY_R * 2.4
	chand.light_energy = 2.6
	chand.shadow_enabled = false
	chand.position = Vector3(lobby.x, lobby.y, 0.55)
	chand.set_meta("base", 2.6)
	chand.set_meta("phase", randf() * TAU)
	_interior_root.add_child(chand)
	_interior_lights.append(chand)
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(1.0, 0.9, 0.6)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.85, 0.5)
	orb_mat.emission_energy_multiplier = 2.4
	var orb := MeshInstance3D.new()
	orb.mesh = _ball_mesh(0.08)
	orb.material_override = orb_mat
	orb.position = Vector3(lobby.x, lobby.y, 0.6)
	_interior_root.add_child(orb)

func _update_interior() -> void:
	if _enemy_arrow != null:
		_enemy_arrow.visible = false
	# A breadcrumb back to the lift, so exploring the maze never means getting stuck.
	if _nav_arrow != null and not _pilots.is_empty():
		var lead2 := Vector2(_pilots[0].global_position.x, _pilots[0].global_position.y)
		var pad := _pad_world()
		var to := Vector2(pad.x, pad.y) - lead2
		var dist := to.length()
		if dist < ELEV_R * 1.3:
			_nav_arrow.visible = false
		else:
			_nav_arrow.visible = true
			var dir := to / dist
			_nav_arrow.global_position = Vector3(lead2.x + dir.x * 0.07, lead2.y + dir.y * 0.07, _interior_pilot_z + 0.06)
			_nav_arrow.rotation = Vector3(0.0, 0.0, atan2(dir.y, dir.x))
	var t := Time.get_ticks_msec() / 1000.0
	# Gently breathe the accent lights for a dreamy interior.
	for lt in _interior_lights:
		if is_instance_valid(lt):
			var base: float = lt.get_meta("base", 1.4)
			var ph: float = lt.get_meta("phase", 0.0)
			(lt as OmniLight3D).light_energy = base * (0.65 + 0.35 * sin(t * 1.6 + ph))
	# Slowly spin the holo-terminal glyphs.
	for pr in _interior_props:
		if is_instance_valid(pr):
			pr.rotation.z = t * float(pr.get_meta("spin", 1.0))
	_update_staff(t)

func _update_staff(t: float) -> void:
	for s in _staff:
		if not is_instance_valid(s):
			continue
		var pause := int(s.get_meta("pause"))
		var rt := int(s.get_meta("rt", 0)) - 1
		s.set_meta("rt", rt)
		if pause > 0:
			s.set_meta("pause", pause - 1)
		else:
			var target: Vector3 = s.get_meta("target")
			var to := Vector3(target.x - s.global_position.x, target.y - s.global_position.y, 0.0)
			# Repick on arrival OR if stuck against a wall too long (route timer). Stay
			# near home (a short hop within the local room/corridor) so they don't fight
			# the maze trying to cross it.
			if to.length() < 0.06 or rt <= 0:
				var home: Vector3 = s.get_meta("home")
				s.set_meta("target", home + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), 0.0))
				s.set_meta("rt", randi_range(120, 320))
				if randf() < 0.6:
					s.set_meta("pause", randi_range(40, 180))
			else:
				var vel: Vector3 = s.get_meta("vel")
				vel = vel.lerp(to.limit_length(CREW_SPEED), 0.1)
				s.global_position += Vector3(vel.x, vel.y, 0.0)
				s.set_meta("vel", vel)
				var cc := _clamp_xy(s.global_position.x, s.global_position.y)
				s.global_position.x = cc.x
				s.global_position.y = cc.y
		var phase: float = s.get_meta("phase")
		s.global_position.z = _interior_pilot_z + absf(sin(t * 4.0 + phase)) * 0.012
		_orient_nose(s)   # ambient staff face their walk direction too
