extends Node

const MIX_RATE := 44100
const ROOT_FREQ := 261.625565 # C4
const PLAYER_POOL := 24
const STREAM_CACHE_LIMIT := 160
const SFX_LOW_SEMITONE := -5
const SFX_HIGH_SEMITONE := 24

const MODES := {
	# Church modes
	"IONIAN": [0, 2, 4, 5, 7, 9, 11],
	"DORIAN": [0, 2, 3, 5, 7, 9, 10],
	"PHRYGIAN": [0, 1, 3, 5, 7, 8, 10],
	"LYDIAN": [0, 2, 4, 6, 7, 9, 11],
	"MIXOLYDIAN": [0, 2, 4, 5, 7, 9, 10],
	"AEOLIAN": [0, 2, 3, 5, 7, 8, 10],
	"LOCRIAN": [0, 1, 3, 5, 6, 8, 10],
	# Minor / major variants
	"HARMONIC_MINOR": [0, 2, 3, 5, 7, 8, 11],
	"MELODIC_MINOR": [0, 2, 3, 5, 7, 9, 11],
	"HARMONIC_MAJOR": [0, 2, 4, 5, 7, 8, 11],
	"NEAPOLITAN_MINOR": [0, 1, 3, 5, 7, 8, 11],
	"NEAPOLITAN_MAJOR": [0, 1, 3, 5, 7, 9, 11],
	"HUNGARIAN_MINOR": [0, 2, 3, 6, 7, 8, 11],
	"HUNGARIAN_MAJOR": [0, 3, 4, 6, 7, 9, 10],
	# Symmetric / exotic
	"WHOLE": [0, 2, 4, 6, 8, 10],
	"DIMINISHED": [0, 2, 3, 5, 6, 8, 9, 11],
	"DIM_HALFWHOLE": [0, 1, 3, 4, 6, 7, 9, 10],
	"AUGMENTED": [0, 3, 4, 7, 8, 11],
	"ENIGMATIC": [0, 1, 4, 6, 8, 10, 11],
	"PROMETHEUS": [0, 2, 4, 6, 9, 10],
	# Blues / jazz
	"PENTATONIC": [0, 2, 4, 7, 9],
	"PENTA_MINOR": [0, 3, 5, 7, 10],
	"BLUES": [0, 3, 5, 6, 7, 10],
	"BLUES_MAJOR": [0, 2, 3, 4, 7, 9],
	"BEBOP_DOM": [0, 2, 4, 5, 7, 9, 10, 11],
	# Spanish / flamenco
	"SPANISH": [0, 1, 4, 5, 7, 8, 10],
	"SPANISH8": [0, 1, 3, 4, 5, 6, 8, 10],
	# Arabic / middle-eastern maqamat
	"DOUBLE_HARMONIC": [0, 1, 4, 5, 7, 8, 11],
	"SABA": [0, 2, 3, 4, 7, 8, 10],
	# Japanese
	"HIROJOSHI": [0, 2, 3, 7, 8],
	"INSEN": [0, 1, 5, 7, 10],
	"YO": [0, 2, 5, 7, 9],
	"MIYAKOBUSHI": [0, 1, 5, 7, 8],
	"KUMOI": [0, 2, 3, 7, 9],
	"IWATO": [0, 1, 5, 6, 10],
	"RYUKYU": [0, 4, 5, 7, 11],
	# Other ethnic
	"EGYPTIAN": [0, 2, 5, 7, 10],
	"CHINESE": [0, 4, 6, 7, 11],
	"PELOG": [0, 1, 3, 7, 8],
}

var _players: Array[AudioStreamPlayer] = []
var _player_idx := 0
var _cache: Dictionary = {}
var _cache_order: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _stage_key := ""
var _mode_name := "IONIAN"
var _scale: Array = MODES["IONIAN"]
var _bpm := 128.0
var _beat_len := 60.0 / 128.0
var _clock := 0.0
var _next_step := 0.0
var _step := 0
var _melody_cursor := 0
var _shot_cursor := 0
var _shot_gate := 0.0
var _unit_gate: Dictionary = {}
var _unit3_gate := 0.0
var _combo_gate := 0.0
var _unit2_gate := 0.0
var _unit4_gate := 0.0
var _unit5_gate := 0.0
var _hit_gate := 0.0
var _destroy_gate := 0.0
var _angel_voice_gate := 0.0
var _terrain_gate := 0.0
var _terrain_tone_gate := 0.0
var _dive_gate := 0.0
var _pickup_gate := 0.0
var _pickup_window_start := 0.0
var _pickup_window_count := 0
var _events: Array[Dictionary] = []

# Ending music (FINAL_ENDING): a warm sustained wash, then PARTWAY IN free, undulating
# 16th-note arpeggio phrases — random but quantized to the harmonic-minor scale, several
# voices weaving at once, like an organist improvising. No chord progression, no drums.
const ENDING_16TH := 0.12           # base grid; the runs play on this, no percussion (a touch slower)
const ENDING_PHRASE_IN := 96        # ~11s of the slow flow before the fast runs enter
var _ending_music := false
var _ending_musicbox_mode := false
var _ending_music_at := 0.0
var _arp_next := 0.0
var _arp_i := 0
var _arp_voices: Array = []          # per-voice fast-run improv state
var _slow_deg := 0                   # slow base-melody walker
var _slow_dir := 1

# GOLDEN robot music: the game's climax. A loud, fast minor-PENTATONIC rock groove at
# ~170 BPM that overrides the sector music for the 10s the aura is up.
const GOLDEN_SCALE := [0, 3, 5, 7, 10]   # minor pentatonic (the rock/blues scale)
const GOLDEN_BPM := 170.0
# Driving 16-sixteenth power riff (degrees into the pentatonic), and a wailing lead lick.
const GOLDEN_RIFF := [0, 0, 3, 0, 0, 3, 5, 3, 0, 0, 3, 0, 5, 3, 5, 7]
const GOLDEN_LEAD := [7, 10, 12, 10, 7, 5, 7, 3]
# GOLDEN中は全サウンド(音楽+アウラSFX)をこのdB分だけ一律に下げ、発動時の音量跳ね上がりを抑える。
const GOLDEN_DB := -8.0
# 大型爆発の本体(boom/blast等)だけを流すリバーブ専用バス名。
const REVERB_BUS := &"ExplosionVerb"
# 常時走るリバーブはアイドル時にバッファノイズを出すので、普段はバスをミュートし、爆発の瞬間
# だけ起こしてテイル分(REVERB_TAIL_SEC)経過後に自動で再ミュートする。
const REVERB_TAIL_SEC := 2.5
var _reverb_bus_idx := -1
var _reverb_off_at := 0.0
# GOD(AngelBoss)/GENESIS の最期の爆発(boss_destroy)を一括で増減するノブ。0=元の音量、負で静かに。
const BOSS_DESTROY_DB := -9.0
var _golden_music := false
var _aura_gate := 0.0
var _arena_music := false
var _arena_next := 0.0
var _arena_breath_next := 0.0

# FINAL_BOSS music: a dark, ceremonial 和風 theme on the 都節 (miyako-bushi) minor scale —
# slow taiko pulse, a low drone, and a sparse koto/shamisen melody that escalates.
const BOSS_SCALE := [0, 1, 5, 7, 8]   # miyako-bushi: the classic dark Japanese minor (半音入り)
const BOSS_BPM := 104.0
var _boss_music := false
var _genesis_silenced := false
var _god_silenced := false
var _genesis_cry_gate := 0.0
var _genesis_wound_gate := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, 0.0)
	_install_master_dynamics()
	_install_reverb_bus()
	for i in PLAYER_POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = -2.0
		add_child(p)
		_players.append(p)
	_reset_music("boot")
	call_deferred("_startup_ping")

# Master-bus safety: a hard limiter ONLY — a brick-wall ceiling against transient peaks
# (GOD / GENESIS explosion stacks). No compressor: a bus-wide compressor pumps the whole
# mix whenever a reverb tail or loud passage sustains. GOLDEN's loudness jump is handled
# directly by GOLDEN_DB, so the limiter alone is enough to keep nothing blowing out.
func _install_master_dynamics() -> void:
	while AudioServer.get_bus_effect_count(0) > 0:   # hot-reload safe: clear first
		AudioServer.remove_bus_effect(0, 0)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0    # brick-wall ceiling just under 0 dBFS
	AudioServer.add_bus_effect(0, lim)

# WET-ONLY reverb RETURN bus. It outputs pure reverb (dry = 0): the dry explosion plays
# on Master untouched, and _play_boom() sends a quieter COPY here purely for the tail.
# So the reverb is additive on JUST the explosion — nothing else is coloured.
func _install_reverb_bus() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, REVERB_BUS)
	AudioServer.set_bus_send(idx, &"Master")   # the bus's OUTPUT must reach Master to be heard
	var rev := AudioEffectReverb.new()
	rev.room_size = 1.1      # smaller room → shorter, less washy tail
	rev.damping = 1.0        # darker/quicker decay
	rev.predelay_msec = 18.0
	rev.dry = 0.0            # NO dry here (the dry is on Master); pure wet return
	rev.wet = 0.06
	AudioServer.add_bus_effect(idx, rev)
	_reverb_bus_idx = idx
	AudioServer.set_bus_mute(idx, true)   # idle = muted → the always-on reverb makes no buffer noise

func _startup_ping() -> void:
	_play_stream(_tone_stream(_degree_freq(0, 0), 0.26, "tri", 0.34), -1.0)

func _process(delta: float) -> void:
	# Re-mute the reverb bus once its tail has decayed, so it isn't left running (and hissing)
	# during the long idle stretches between explosions.
	if _reverb_bus_idx >= 0 and _clock >= _reverb_off_at \
			and not AudioServer.is_bus_mute(_reverb_bus_idx):
		AudioServer.set_bus_mute(_reverb_bus_idx, true)
	# Final-boss ENTRANCE hush: the boss gate has just been crossed. Cut every voice so the
	# theme can swell out of true silence as GOD descends. Stop the previous sector groove
	# once; keep the clock advancing so the music re-seeds cleanly when the hush lifts.
	if GameState.boss_intro_hush:
		_boss_music = false
		_stage_key = ""
		_events.clear()
		_stop_all_players()
		_clock += delta
		return
	# The true-route standoff (the silent GOD, then GENESIS) plays out in total silence.
	if GameState.god_phase > 0:
		if not _god_silenced:
			_god_silenced = true
			_events.clear()
			_stop_all_players()
		_clock += delta
		return
	_god_silenced = false
	# Once AngelBoss falls, THE GENESIS enters in absolute hush. Stop the boss groove and
	# any queued fragments exactly once; the carrier battle remains deliberately silent.
	var genesis_active := GameState.final_phase == GameState.FINAL_BOSS \
		and get_tree().get_first_node_in_group("genesis_boss") != null
	if genesis_active:
		if not _genesis_silenced:
			_genesis_silenced = true
			_boss_music = false
			_events.clear()
			_stop_all_players()
		_clock += delta
		return
	_genesis_silenced = false
	# Final boss battle: a dark, solemn 和風 minor theme — 都節 (miyako-bushi) scale over
	# taiko drums and a sparse koto/shamisen line.
	if GameState.final_phase == GameState.FINAL_BOSS:
		if not _boss_music:
			_boss_music = true
			_scale = BOSS_SCALE
			_bpm = BOSS_BPM
			_beat_len = 60.0 / _bpm
			_next_step = _clock + 0.05
			_step = 0
			_melody_cursor = 0
		_clock += delta
		while _clock >= _next_step:
			_emit_boss_step(_step)
			_step += 1
			_next_step += _beat_len * 0.25
		_update_events()
		return
	_boss_music = false
	# The quiet Genesis battle resolves into the existing generative ending composition. The
	# arena survivor's monologue reuses the very same ending music.
	if GameState.final_phase == GameState.FINAL_ENDING or GameState.survivor_monologue_active \
			or GameState.musicbox_ending:
		var musicbox_now := GameState.musicbox_ending
		if not _ending_music:
			_ending_music = true
			_ending_musicbox_mode = musicbox_now
			# Let the Genesis death blast fully resolve before the ending's first warm chord.
			# The battle was already silent, so no stop() is needed here.
			_events.clear()
			# TRUE END resolves into a gentle MAJOR-key (IONIAN) music box; the normal ending AND the
			# stoneface survivor monologue stay the darker harmonic-minor organ.
			_mode_name = "IONIAN" if musicbox_now else "HARMONIC_MINOR"
			_scale = MODES[_mode_name]
			_ending_music_at = _clock + 1.35
			_arp_next = _ending_music_at
			_arp_i = 0
			_arp_voices.clear()
			_slow_deg = 0
			_slow_dir = 1
		elif _ending_musicbox_mode != musicbox_now:
			# The true route can switch from the survivor/normal ending machinery into the
			# music-box ending without restarting TsgAudio. Re-quantize immediately so no
			# stale harmonic-minor scale leaks into TRUE END.
			_ending_musicbox_mode = musicbox_now
			_mode_name = "IONIAN" if musicbox_now else "HARMONIC_MINOR"
			_scale = MODES[_mode_name]
			_arp_next = _clock + 0.1
			_arp_i = 0
			_arp_voices.clear()
			_slow_deg = 0
			_slow_dir = 1
		elif musicbox_now:
			_mode_name = "IONIAN"
			_scale = MODES["IONIAN"]
		_clock += delta
		if _clock >= _ending_music_at:
			if GameState.musicbox_ending:
				_emit_musicbox_ending()
			else:
				_emit_ending_music()
		return
	if _ending_music:
		_ending_music = false
		_stage_key = ""
	# GOLDEN robot: slam into a fast rock-pentatonic groove for the 10s the aura is up.
	if GameState.golden_active:
		if not _golden_music:
			_golden_music = true
			_scale = GOLDEN_SCALE
			_bpm = GOLDEN_BPM
			_beat_len = 60.0 / _bpm
			_next_step = _clock + 0.05
			_step = 0
			golden_start()   # power-chord crash stinger
		_clock += delta
		while _clock >= _next_step:
			_emit_golden_step(_step)
			_step += 1
			_next_step += _beat_len * 0.25
		_update_events()
		return
	if _golden_music:
		_golden_music = false
		_stage_key = ""   # force the sector music to re-seed (mode/tempo) next frame
	# Cave arena: no rhythm, no drums. Keep this intentionally light: one sparse low tone,
	# plus rare breath noise. Random WAV generation here caused frame drops.
	# Survivor monologue / endings are handled above and keep their own music.
	if GameState.arena_active:
		if not _arena_music:
			_arena_music = true
			_stage_key = ""
			_events.clear()
			_mode_name = "INSEN"
			_scale = MODES["INSEN"]
			_arena_next = _clock + 0.15
			_arena_breath_next = _clock + 6.0
			_melody_cursor = -6
		_clock += delta
		_emit_arena_music()
		_update_events()
		return
	if _arena_music:
		_arena_music = false
		_stage_key = ""
	# Sector is part of the key so each star system seeds its own mode/tempo — the
	# music changes when you warp through a gate into a new region.
	var key := "%s/%s/%s/S%d" % [GameState.stage, GameState.planet_name,
		GameState.planet_type, GameState.sector]
	if key != _stage_key and not GameState.in_transition():
		_reset_music(key)
	_clock += delta
	while _clock >= _next_step:
		_emit_step(_step)
		_step += 1
		_next_step += _beat_len * 0.25
	_update_events()

func _reset_music(key: String) -> void:
	_stage_key = key
	_rng.seed = hash(key)
	var names := MODES.keys()
	_mode_name = String(names[abs(int(_rng.randi())) % names.size()])
	_scale = MODES[_mode_name]
	_bpm = float(92 + int(_rng.randi() % 76))
	if GameState.stage == "planet":
		_bpm += 10.0
	_beat_len = 60.0 / _bpm
	_next_step = _clock + 0.08
	_step = 0
	_melody_cursor = abs(int(_rng.randi())) % maxi(1, _scale.size())
	_shot_cursor = _melody_cursor + int(_rng.randi() % 5)
	_events.clear()

func _emit_arena_music() -> void:
	if _clock >= _arena_breath_next:
		_arena_breath_next = _clock + 9.0
		_play_stream(_noise_stream(0.45, 0.012), -27.0)
	if _clock < _arena_next:
		return
	_arena_next = _clock + 4.0
	var cave_degrees: Array[int] = [-8, -6, -5, -3]
	var idx: int = int(_rng.randi() % cave_degrees.size())
	_melody_cursor = cave_degrees[idx]
	_play_note(-2, _melody_cursor, 2.4, "tri", 0.040, -21.0)

# Harmonic-minor organ improv. The BASE is a slow, flowing scale-walk over a warm pad
# (no chord progression); PARTWAY IN, fast random 16th-note runs weave in on top — several
# voices at once. Notes are scale degrees → _play_note quantizes them to harmonic minor.
func _emit_ending_music() -> void:
	if _arp_voices.is_empty():
		for v in 3:
			_arp_voices.append({"rest": v * 5, "rem": 0, "deg": v * 2, "dir": 1, "oct": v})
	if _clock < _arp_next:
		return
	_arp_next = _clock + ENDING_16TH
	_arp_i += 1
	# Warm sustained bass wash. It lands on the ROOT most of the time but is NOT fixed
	# to it — every so often it wanders to another scale degree (kept to a small set so
	# the tone-stream still caches and never causes frame drops).
	if _arp_i % 16 == 0:
		var r := 0
		if _rng.randf() > 0.66:
			r = [2, 3, 4, 5][_rng.randi() % 4]
		_play_note(-2, r, 2.8, "tri", 0.10, -10.0)
		_play_note(-1, r + 4, 2.6, "saw", 0.028, -16.5)
	# Slow base melody from the very start: one soft, long, scale-walking note every ~0.5s.
	if _arp_i % 5 == 0:
		_slow_deg += _slow_dir * (1 + (1 if _rng.randf() < 0.3 else 0))
		if _rng.randf() < 0.32:
			_slow_dir = -_slow_dir
		if _slow_deg <= -2 or _slow_deg >= 10:
			_slow_dir = -_slow_dir
			_slow_deg = clampi(_slow_deg, -2, 10)
		_play_note(0, _slow_deg, 1.0, "tri", 0.085, -10.5)
		if _rng.randf() < 0.5:
			_play_note(0, _slow_deg + 2, 1.0, "tri", 0.04, -14.5)
	# The FAST improvised runs only come in PARTWAY through.
	if _arp_i < ENDING_PHRASE_IN:
		return
	for vi in _arp_voices.size():
		var v: Dictionary = _arp_voices[vi]
		if int(v["rest"]) > 0:
			v["rest"] = int(v["rest"]) - 1
			continue
		if int(v["rem"]) <= 0:
			# Start a new phrase: random length, start degree, direction.
			v["rem"] = 6 + (_rng.randi() % 11)
			v["deg"] = (_rng.randi() % 7) + int(v["oct"]) * 0
			v["dir"] = 1 if _rng.randf() < 0.5 else -1
		# Play this 16th (occasional gaps make it feel hand-played), legato ring.
		# Durations are a FIXED per-voice set (not random) so the tone-stream cache hits
		# instead of synthesizing a fresh WAV every note (that caused the frame drops).
		if _rng.randf() < 0.86:
			var dur: float = 0.26 + 0.12 * float(vi)
			_play_note(int(v["oct"]), int(v["deg"]), dur, "tri", 0.058, -11.5 - float(vi) * 1.5)
		# Walk the contour with undulation (起伏): step 1-2, sometimes flip direction.
		var step: int = int(v["dir"]) * (1 + (1 if _rng.randf() < 0.3 else 0))
		v["deg"] = int(v["deg"]) + step
		if _rng.randf() < 0.22:
			v["dir"] = -int(v["dir"])
		if int(v["deg"]) <= -3 or int(v["deg"]) >= 13:
			v["dir"] = -int(v["dir"])
			v["deg"] = clampi(int(v["deg"]), -3, 13)
		v["rem"] = int(v["rem"]) - 1
		if int(v["rem"]) <= 0:
			v["rest"] = 2 + (_rng.randi() % 9)   # breath between phrases

# TRUE END: a soft, hopeful MAJOR-key music box. A warm sustained triad bed under a gentle,
# FLOWING melody (stepwise walk, not random plinks) with a couple of quiet counter-voices that
# weave in over time. Tender and unhurried — no drums, no harsh intervals.
const MUSICBOX_PENT := [0, 1, 2, 4, 5]   # pentatonic degree indices into IONIAN
func _emit_musicbox_ending() -> void:
	if _clock < _arp_next:
		return
	_arp_next = _clock + 0.22
	_arp_i += 1
	# Warm sustained PAD — a soft major triad held underneath (the emotional bed), refreshed slowly.
	if _arp_i % 16 == 0:
		_play_note(-1, 0, 3.6, "tri", 0.060, -15.0)   # root
		_play_note(0, 2, 3.6, "tri", 0.040, -18.0)    # major third
		_play_note(0, 4, 3.6, "tri", 0.034, -19.0)    # fifth
	# Gentle FLOWING lead: a stepwise major walk with a hopeful, rising-then-settling contour —
	# one tender bell every ~0.44s. Soft gaps keep it hand-wound, never busy.
	if _arp_i % 2 == 0:
		_slow_deg += _slow_dir
		if _rng.randf() < 0.28:
			_slow_dir = -_slow_dir
		if _slow_deg <= 0 or _slow_deg >= 9:
			_slow_dir = -_slow_dir
			_slow_deg = clampi(_slow_deg, 0, 9)
		if _rng.randf() < 0.86:
			_play_note(1, _slow_deg, 1.5, "tri", 0.055, -11.5)
	# Counter-voices layer IN over time (quiet, sparse, octave-shimmer) so melodies quietly stack.
	var extra := clampi(_arp_i / 95, 0, 2)
	for vi in extra:
		if (_arp_i + vi * 4) % (5 + vi * 2) != 0:
			continue
		if _rng.randf() < 0.42:
			continue
		var deg: int = MUSICBOX_PENT[_rng.randi() % MUSICBOX_PENT.size()] + 7
		_play_note(1, deg, 1.3, "tri", 0.040, -15.0 - float(vi) * 1.2)

func _emit_step(step: int) -> void:
	var power := _power_level()
	var bar_step := step % 16
	if bar_step == 0:
		_play_note(-2, 0, 0.22, "tri", 0.22, -8.0)
	if bar_step == 8:
		_play_note(-2, 4, 0.20, "tri", 0.17, -9.0)
	if power >= 2 and (bar_step % 4) == 0:
		_play_stream(_kick_stream(0.22, 0.36 + float(power) * 0.025), -5.0)
	if power >= 4 and (bar_step == 4 or bar_step == 12):
		_play_stream(_noise_stream(0.040, 0.11), -12.0)
	if power >= 6 and (bar_step % 2) == 1:
		_play_stream(_noise_stream(0.026, 0.07), -14.0)
	if (bar_step % 4) == 2:
		var deg := _melody_cursor + int(_rng.randi() % 3) - 1
		_play_note(0, deg, 0.13, "pulse", 0.11, -10.0)
		_melody_cursor = posmod(deg + 1 + int(_rng.randi() % 2), _scale.size())
	if power >= 8 and (bar_step % 4) == 0:
		_play_note(1, _melody_cursor + 2, 0.10, "square", 0.08, -12.0)

# Stinger when the Golden robot stands up: a big power-chord crash + rising whoosh.
func golden_start() -> void:
	_play_note(-1, 0, 0.5, "saw", 0.20, -2.5)     # root
	_play_note(-1, 3, 0.5, "saw", 0.13, -6.0)     # fifth (pentatonic deg3 = +7 semis)
	_play_note(0, 0, 0.5, "square", 0.11, -7.0)   # octave bite
	_play_stream(_noise_stream(0.5, 0.20), -5.0)  # cymbal crash
	_play_stream(_sweep_stream(300.0, 1500.0, 0.32, "saw", 0.16), -5.5)

# One bar-step of the driving rock groove (16th grid at GOLDEN_BPM).
func _emit_golden_step(step: int) -> void:
	var bar := step % 16
	if bar % 4 == 0:
		_play_stream(_kick_stream(0.18, 0.55), -3.0)         # four-on-the-floor kick
	if bar == 4 or bar == 12:
		_play_stream(_noise_stream(0.08, 0.24), -6.0)        # snare backbeat
		_play_note(-1, 0, 0.05, "tri", 0.05, -14.0)
	if bar % 2 == 1:
		_play_stream(_noise_stream(0.02, 0.05), -17.0)       # hi-hat sizzle
	var riff: int = GOLDEN_RIFF[bar]                          # palm-muted power riff
	_play_note(-2, riff, 0.11, "saw", 0.17, -5.0)
	_play_note(-2, riff + 3, 0.11, "saw", 0.09, -9.0)        # stacked = thick
	if bar % 2 == 0:                                          # wailing lead on the 8ths
		var lead: int = GOLDEN_LEAD[(step / 2) % GOLDEN_LEAD.size()]
		_play_note(1, lead, 0.10, "square", 0.085, -9.0)

# One 16th-grid step of the 和風 boss theme: a brooding taiko + drone bed with a koto line.
func _emit_boss_step(step: int) -> void:
	var bar := step % 16
	# Low ominous drone at the top of each bar (root + a colour tone), held long.
	if bar == 0:
		_play_note(-2, 0, 1.7, "tri", 0.17, -9.0)
		_play_note(-2, 3, 1.7, "saw", 0.05, -19.0)
	# Taiko: a heavy hit on 1 and a strong one on 3, plus a syncopated softer beat.
	if bar == 0:
		_play_stream(_kick_stream(0.28, 0.62), -3.0)
	if bar == 8:
		_play_stream(_kick_stream(0.24, 0.5), -4.5)
	if bar == 6 or bar == 14:
		_play_stream(_kick_stream(0.16, 0.34), -8.0)
	# Tsuzumi-ish rim accent.
	if bar == 4 or bar == 12:
		_play_stream(_noise_stream(0.05, 0.10), -12.0)
	# Koto: a sparse, plucked line on the Japanese-minor scale (one note per quarter), with
	# an octave shimmer — wanders up/down for a brooding, improvised feel.
	if bar % 4 == 0:
		var deg := _melody_cursor
		_play_note(0, deg, 0.55, "tri", 0.12, -8.5)
		_play_note(1, deg, 0.42, "pulse", 0.035, -16.0)
		var stepdir := 1 if _rng.randf() < 0.6 else -1
		_melody_cursor = posmod(deg + stepdir + int(_rng.randi() % 2), _scale.size())
	# A shamisen-like answering stab late in the bar.
	if bar == 10:
		_play_note(0, _melody_cursor + 2, 0.2, "saw", 0.09, -11.0)
		_play_note(-1, _melody_cursor + 2, 0.2, "saw", 0.05, -16.0)

# Flashy, exhilarating shockwave SFX for each Golden aura pulse: sub boom + power chord
# + bright rising sweep + a sparkle on top.
func aura_pulse() -> void:
	if _clock < _aura_gate:
		return
	_aura_gate = _clock + 0.10
	_play_stream(_boom_stream(0.22, 0.52), -4.5)
	_play_stream(_blast_attack_stream(0.18, 0.42), -7.0)
	var root := _bounded_sfx_note(0)
	_play_note(root.x, root.y, 0.16, "saw", 0.12, -7.0)
	_play_note(root.x, root.y + 3, 0.16, "saw", 0.09, -10.0)
	_queue_note(0.035, root.x + 1, root.y + 4, 0.12, "square", 0.085, -10.0)
	_play_stream(_sweep_stream(520.0, 1550.0, 0.16, "saw", 0.12), -8.5)

func player_shot() -> void:
	if _clock < _shot_gate:
		return
	_shot_gate = _clock + 0.040
	var shot_note := _bounded_sfx_note(_shot_cursor)
	_play_note(shot_note.x, shot_note.y, 0.040, "tri", 0.075, -16.0)

func gerwalk_shot() -> void:
	if _clock < _shot_gate:
		return
	_shot_gate = _clock + 0.045
	var shot_note := _bounded_sfx_note(_shot_cursor)
	_play_note(shot_note.x, shot_note.y, 0.045, "tri", 0.085, -14.0)
	_play_note(shot_note.x - 1, shot_note.y, 0.055, "pulse", 0.050, -15.5)
	_play_stream(_noise_stream(0.018, 0.025), -21.0)

func unit_fire(unit_id: int) -> void:
	if GameState.sep_t <= 0.5:
		_combo_fire(unit_id)
		return
	var gate_key := str(unit_id)
	if _unit_gate.has(gate_key) and _clock < float(_unit_gate[gate_key]):
		return
	_unit_gate[gate_key] = _clock + 0.060
	var cursor := _bounded_sfx_cursor(_melody_cursor + unit_id * 2)
	var note := _bounded_sfx_note(cursor)
	var wave := "pulse" if (unit_id % 2) == 0 else "tri"
	_play_note(note.x, note.y, 0.060, wave, 0.070, -14.0)
	_shot_cursor = _bounded_sfx_cursor(cursor + 1)

func unit3_sweep() -> void:
	if GameState.sep_t <= 0.5:
		_combo_fire(3)
		return
	if _clock < _unit3_gate:
		return
	_unit3_gate = _clock + 0.080
	var cursor := _bounded_sfx_cursor(_melody_cursor + 2)
	var lead := _bounded_sfx_note(cursor)
	_play_note(lead.x, lead.y, 0.075, "pulse", 0.150, -8.0)
	for i in 4:
		var note := _bounded_sfx_note(cursor + i)
		_queue_note(0.020 + float(i) * 0.020, note.x, note.y, 0.060, "saw", 0.100, -10.5 + float(i) * 0.45)
	_play_stream(_noise_stream(0.030, 0.035), -16.0)
	_shot_cursor = _bounded_sfx_cursor(cursor + 4)

func unit2_bomb_launch() -> void:
	if _clock < _unit2_gate:
		return
	_unit2_gate = _clock + 0.120
	var cursor := _bounded_sfx_cursor(_melody_cursor + 3)
	for i in 4:
		var note := _bounded_sfx_note(cursor + i)
		_queue_note(float(i) * 0.030, note.x, note.y, 0.060, "tri", 0.078, -12.0 + float(i) * 0.35)
	_play_stream(_noise_stream(0.030, 0.030), -18.0)

func unit2_bomb_burst() -> void:
	if _clock < _destroy_gate:
		return
	_destroy_gate = _clock + 0.055
	_play_boom(_blast_attack_stream(0.040, 0.190), -8.5)
	_play_boom(_boom_stream(0.230, 0.360), -5.8)
	var note := _bounded_sfx_note(_melody_cursor + 2)
	_play_note(note.x, note.y, 0.080, "square", 0.075, -12.0)

func unit3_explosion() -> void:
	if _clock < _destroy_gate:
		return
	_destroy_gate = _clock + 0.045
	var cursor := _bounded_sfx_cursor(_melody_cursor + 4)
	var note := _bounded_sfx_note(cursor)
	_play_boom(_blast_attack_stream(0.048, 0.240), -5.5)
	_play_boom(_boom_stream(0.260, 0.440), -4.5)
	_play_note(note.x + 1, note.y, 0.070, "square", 0.095, -10.0)
	for i in 3:
		var tail := _bounded_sfx_note(cursor + 2 + i * 2)
		_queue_note(0.034 + float(i) * 0.030, tail.x, tail.y, 0.060, "tri", 0.065, -12.0 - float(i))
	_play_stream(_noise_stream(0.040, 0.055), -16.0)

func unit4_laser_fire() -> void:
	if _clock < _unit4_gate:
		return
	_unit4_gate = _clock + 0.170
	var cursor := _bounded_sfx_cursor(_melody_cursor + 5)
	_play_stream(_noise_stream(0.045, 0.030), -18.5)
	for i in 6:
		var note := _bounded_sfx_note(cursor + i)
		_queue_note(float(i) * 0.022, note.x, note.y, 0.072, "saw", 0.050, -15.0 + float(i) * 0.45)

func unit5_barrage() -> void:
	if _clock < _unit5_gate:
		return
	_unit5_gate = _clock + 0.105
	var cursor := _bounded_sfx_cursor(_shot_cursor + 5)
	for i in 5:
		var note := _bounded_sfx_note(cursor + (i % 3))
		_queue_note(float(i) * 0.018, note.x, note.y, 0.035, "pulse", 0.062, -15.0)
	_shot_cursor = _bounded_sfx_cursor(cursor + 1)

func lock_ping(lock_index: int = 0) -> void:
	# RayStorm-style "pi": a clear, LOUD bright beep that steps UP with each lock, plus a
	# high harmonic so it cuts through the mix. Fixed pitches (not scale-bound) for clarity.
	var freq := 1046.5 * pow(2.0, float(lock_index) / 12.0)   # C6 rising a semitone per lock
	_play_stream(_tone_stream(freq, 0.075, "square", 0.20), -7.0)
	_play_stream(_tone_stream(freq * 2.0, 0.05, "pulse", 0.09), -13.0)

func _combo_fire(unit_id: int) -> void:
	if _clock < _combo_gate:
		return
	_combo_gate = _clock + 0.075
	var count: int = clampi(GameState.formation_count, 1, 5)
	var cursor := _bounded_sfx_cursor(_shot_cursor + unit_id + count)
	var root := _bounded_sfx_note(cursor)
	_play_note(root.x, root.y, 0.050, "pulse", 0.072, -16.0)
	if count >= 3:
		var fifth := _bounded_sfx_note(cursor + 4)
		_queue_note(0.014, fifth.x, fifth.y, 0.044, "tri", 0.046, -18.0)
	if count >= 5:
		var top := _bounded_sfx_note(cursor + 7)
		_queue_note(0.028, top.x, top.y, 0.040, "pulse", 0.036, -19.5)
	_shot_cursor = _bounded_sfx_cursor(cursor + 1)

func enemy_hit() -> void:
	if _clock < _hit_gate:
		return
	_hit_gate = _clock + 0.022
	var turn: Array[int] = [1, 1, 2, 3, 4, 5]
	var step_up: int = turn[int(_rng.randi() % turn.size())]
	_melody_cursor = _bounded_sfx_cursor(_melody_cursor + step_up)
	_shot_cursor = _melody_cursor
	var hit_note := _bounded_sfx_note(_melody_cursor)
	var deg := hit_note.y
	_play_note(hit_note.x, deg, 0.085, "tri", 0.16, -8.0)
	var echo_note := _bounded_sfx_note(_melody_cursor + 2)
	_queue_note(0.038, echo_note.x, echo_note.y, 0.060, "pulse", 0.075, -12.0)
	if (_melody_cursor & 1) == 0:
		var tail_note := _bounded_sfx_note(_melody_cursor + 4)
		_queue_note(0.074, tail_note.x, tail_note.y, 0.052, "tri", 0.052, -14.0)

func enemy_destroy() -> void:
	if _clock < _destroy_gate:
		return
	_destroy_gate = _clock + 0.035
	var cadence: Array[int] = [0, 2, 4, 7]
	var destroy_cursor := _bounded_sfx_cursor(_melody_cursor + int(cadence[int(_rng.randi() % cadence.size())]))
	var destroy_note := _bounded_sfx_note(destroy_cursor)
	_play_stream(_boom_stream(0.180, 0.280), -7.5)
	_play_note(destroy_note.x, destroy_note.y, 0.105, "tri", 0.110, -11.0)
	var finish_note := _bounded_sfx_note(destroy_cursor + 4)
	_queue_note(0.052, finish_note.x, finish_note.y, 0.072, "pulse", 0.060, -14.0)
	_play_stream(_noise_stream(0.026, 0.032), -20.0)
	_melody_cursor = _bounded_sfx_cursor(destroy_cursor + 2)
	_shot_cursor = _melody_cursor

func terrain_break() -> void:
	if _clock < _terrain_gate:
		return
	_terrain_gate = _clock + 0.042
	_play_stream(_debris_stream(0.045, 0.075), -17.0)
	if _clock >= _terrain_tone_gate:
		_terrain_tone_gate = _clock + 0.220
		var note := _bounded_sfx_note(_melody_cursor - 2)
		_play_note(note.x - 1, note.y, 0.050, "tri", 0.026, -22.0)

# Attention fanfare when a ROUTE/BOSS plate is unearthed: a bright rising arpeggio +
# sparkle so the discovery clearly registers.
func route_plate_sfx() -> void:
	for i in 4:
		var note := _bounded_sfx_note(_melody_cursor + i * 2)
		_queue_note(float(i) * 0.06, note.x + 1, note.y, 0.16, "pulse", 0.10, -8.0)
	var top := _bounded_sfx_note(_melody_cursor + 8)
	_queue_note(0.26, top.x + 1, top.y, 0.30, "tri", 0.12, -7.0)
	_play_stream(_noise_stream(0.05, 0.04), -16.0)

var _chip_gate := 0.0

# Pleasant pitched "ting" when a shot chips a block (block survives). Melodic, soft —
# mining should feel nice. Steps the cursor so repeated mining makes a little tune.
func block_chip() -> void:
	if _clock < _chip_gate:
		return
	_chip_gate = _clock + 0.028
	var cur := _bounded_sfx_cursor(_melody_cursor + 5)
	var note := _bounded_sfx_note(cur)
	_play_note(note.x + 1, note.y, 0.055, "tri", 0.075, -14.0)        # bright bell
	_play_note(note.x + 1, note.y + 2, 0.045, "pulse", 0.030, -19.0)  # shimmer third
	_melody_cursor = _bounded_sfx_cursor(_melody_cursor + 1)

# Satisfying crumble when a block is destroyed: a small boom + grit + a resolving tone.
func block_break() -> void:
	if _clock < _destroy_gate:
		return
	_destroy_gate = _clock + 0.04
	_play_stream(_boom_stream(0.16, 0.24), -9.0)
	_play_stream(_debris_stream(0.07, 0.10), -13.0)
	var note := _bounded_sfx_note(_melody_cursor)
	_play_note(note.x, note.y, 0.085, "tri", 0.085, -12.0)
	var top := _bounded_sfx_note(_melody_cursor + 4)
	_queue_note(0.05, top.x, top.y, 0.06, "pulse", 0.05, -15.0)

func arena_block_break() -> void:
	if _clock < _destroy_gate:
		return
	_destroy_gate = _clock + 0.055
	_play_stream(_boom_stream(0.24, 0.46), -5.5)
	_play_stream(_blast_attack_stream(0.11, 0.26), -8.5)
	_play_stream(_debris_stream(0.14, 0.24), -9.0)
	var note := _bounded_sfx_note(_melody_cursor - 2)
	_play_note(note.x - 1, note.y, 0.090, "pulse", 0.075, -12.0)

# Big "DOKAAN" for the dive-attack punching through terrain: a deep sub boom, a
# sharp crack, and flung debris/grit layered together — bigger than terrain_break.
func dive_smash() -> void:
	if _clock < _dive_gate:
		return
	_dive_gate = _clock + 0.12
	_play_stream(_boom_stream(0.34, 0.62), -2.5)
	_play_stream(_blast_attack_stream(0.22, 0.55), -5.5)
	_play_stream(_debris_stream(0.18, 0.34), -10.0)
	_play_stream(_noise_stream(0.06, 0.06), -15.0)
	# A low downward "punch-through" tone under the impact.
	var note := _bounded_sfx_note(_melody_cursor - 3)
	_play_note(note.x - 1, note.y, 0.090, "tri", 0.060, -13.0)

func pickup(rare: bool = false) -> void:
	if _clock - _pickup_window_start > 0.260:
		_pickup_window_start = _clock
		_pickup_window_count = 0
	_pickup_window_count += 1
	var dense := _pickup_window_count >= 4
	if _clock < _pickup_gate:
		return
	_pickup_gate = _clock + (0.075 if dense else (0.100 if rare else 0.046))
	var cursor := _bounded_sfx_cursor(_melody_cursor + (4 if rare else 2))
	var note := _bounded_sfx_note(cursor)
	var octave: int = mini(note.x, 0 if not rare else 1)
	var amp: float = 0.055 if dense else (0.110 if rare else 0.075)
	var vol: float = -19.0 if dense else (-13.5 if rare else -16.5)
	_play_note(octave, note.y, 0.070 if dense else (0.115 if rare else 0.080),
		"tri", amp, vol)
	if rare and not dense:
		var top := _bounded_sfx_note(cursor + 3)
		_play_note(mini(top.x, 1), top.y, 0.105, "pulse", 0.045, -18.0)

# A buried STAR RELIC just surfaced from a blasted block. Players were walking over these
# unnoticed, so this is a bright, RISING two-note bell with a high shimmer — an unmistakable
# "something appeared" ping, distinct from the rapid resource-pickup chimes.
func star_relic_appear() -> void:
	_play_note(0, 4, 0.15, "tri", 0.16, -7.0)
	_play_note(1, 4, 0.13, "pulse", 0.05, -14.0)            # shimmer octave on top
	_queue_note(0.12, 1, 1, 0.20, "tri", 0.15, -7.5)         # step up to the bright note
	_queue_note(0.12, 1, 5, 0.18, "pulse", 0.05, -14.5)

# Securing a STAR RELIC: a rewarding ascending sparkle arpeggio so the catch always registers.
func star_relic_get() -> void:
	_play_note(0, 0, 0.10, "tri", 0.15, -8.0)
	_queue_note(0.075, 0, 4, 0.10, "tri", 0.14, -8.5)
	_queue_note(0.150, 1, 2, 0.20, "pulse", 0.12, -9.0)
	_queue_note(0.150, 2, 2, 0.16, "tri", 0.05, -15.0)       # high sparkle

func _queue_note(delay: float, octave: int, degree: int, dur: float,
		wave: String, amp: float, volume_db: float) -> void:
	if _events.size() >= 40:
		return
	_events.append({
		"t": _clock + delay,
		"oct": octave,
		"deg": degree,
		"dur": dur,
		"wave": wave,
		"amp": amp,
		"vol": volume_db,
	})

func _update_events() -> void:
	for i in range(_events.size() - 1, -1, -1):
		var ev: Dictionary = _events[i]
		if _clock < float(ev["t"]):
			continue
		_play_note(int(ev["oct"]), int(ev["deg"]), float(ev["dur"]),
			String(ev["wave"]), float(ev["amp"]), float(ev["vol"]))
		_events.remove_at(i)

func _play_note(octave: int, degree: int, dur: float, wave: String,
		amp: float, volume_db: float) -> void:
	_play_stream(_tone_stream(_degree_freq(octave, degree), dur, wave, amp), volume_db)

var _beam_gate := 0.0

# Final boss: the carrier's giant beam. Re-triggered each ~0.15s while firing so it
# reads as one continuous, powerful roar — a deep saw drone + bright harmonic edge +
# airy hiss layered together.
func carrier_beam() -> void:
	if _clock < _beam_gate:
		return
	_beam_gate = _clock + 0.15
	_play_stream(_tone_stream(110.0, 0.20, "saw", 0.16), -5.5)    # deep roar body
	_play_stream(_tone_stream(330.0, 0.20, "square", 0.05), -13.0) # bright edge
	_play_stream(_noise_stream(0.20, 0.07), -10.5)                 # plasma hiss

# Final boss death: the biggest blast in the game — layered sub boom, blast crack,
# flung debris, hiss, and a long descending wail.
func boss_destroy() -> void:
	# GOD(AngelBoss)/GENESIS 共通の最期。相対バランスは保ったまま BOSS_DESTROY_DB で一括増減。
	_play_boom(_boom_stream(0.75, 0.9), -0.5 + BOSS_DESTROY_DB)
	_play_boom(_blast_attack_stream(0.42, 0.72), -3.0 + BOSS_DESTROY_DB)
	_play_boom(_debris_stream(0.36, 0.42), -7.5 + BOSS_DESTROY_DB)
	_play_boom(_noise_stream(0.55, 0.11), -9.0 + BOSS_DESTROY_DB)
	_play_stream(_sweep_stream(640.0, 55.0, 0.66, "saw", 0.2), -5.5 + BOSS_DESTROY_DB)  # descending wail (dry)
	var note := _bounded_sfx_note(_melody_cursor)
	_play_note(note.x - 1, note.y, 0.22, "tri", 0.11, -10.0 + BOSS_DESTROY_DB)

# The escalating CHAIN of bursts during GOD's drawn-out death (called ~25× in a row).
# A boomy explosion that ALSO obeys BOSS_DESTROY_DB, so the whole death sequence — not
# just the first blast — scales with that one knob. (Plain enemy_destroy() would ignore it.)
func boss_death_blast() -> void:
	_play_boom(_boom_stream(0.20, 0.34), -6.0 + BOSS_DESTROY_DB)
	_play_stream(_noise_stream(0.03, 0.04), -18.0 + BOSS_DESTROY_DB)

# AngelBoss voice: a sparse choir-like triad plus a rising overtone. It is gated so the
# battle remains intelligible when attack density rises in the final phase.
func angel_boss_voice(entrance: bool = false) -> void:
	if not entrance and _clock < _angel_voice_gate:
		return
	_angel_voice_gate = _clock + (2.4 if entrance else 1.25)
	var dur := 1.15 if entrance else 0.64
	var base := 130.813 if entrance else 196.0
	_play_stream(_tone_stream(base, dur, "tri", 0.18), -8.0)
	_play_stream(_tone_stream(base * 1.25, dur * 0.90, "tri", 0.10), -12.0)
	_play_stream(_sweep_stream(base * 2.0, base * 3.0, dur * 0.78, "sine", 0.075), -13.0)
	if entrance:
		_play_stream(_sweep_stream(360.0, 920.0, 1.15, "tri", 0.11), -11.0)

# THE GENESIS speaks in discontinuous held sine notes: a sacred, synthetic cry that
# feels like a cosmic signal being sampled through time rather than an animal voice.
func genesis_cry() -> void:
	if _clock < _genesis_cry_gate:
		return
	_genesis_cry_gate = _clock + 2.5
	_play_stream(_sample_hold_sine_stream(138.6, 277.2, 1.15, 0.18), -8.5)
	_play_stream(_tone_stream(69.3, 0.72, "tri", 0.07), -17.0)

# A painful but dignified resonance when ordinary fire is absorbed by the Genesis armor.
func genesis_wound() -> void:
	if _clock < _genesis_wound_gate:
		return
	_genesis_wound_gate = _clock + 0.095
	_play_stream(_sweep_stream(840.0, 330.0, 0.20, "sine", 0.12), -9.5)
	_play_stream(_tone_stream(297.0, 0.13, "tri", 0.055), -15.5)

# Boost-lane "vroom": a fast rising pitch sweep plus an airy noise whoosh.
func nav_boost_sfx() -> void:
	_play_stream(_sweep_stream(240.0, 940.0, 0.24, "saw", 0.16), -7.0)
	_play_stream(_noise_stream(0.16, 0.05), -13.0)

# A tone whose frequency ramps f0→f1 over the duration (phase-accumulated).
func _sweep_stream(f0: float, f1: float, dur: float, wave: String, amp: float) -> AudioStreamWAV:
	var key := "sw:%d:%d:%d:%s:%d" % [int(f0), int(f1), int(dur * 1000.0), wave, int(amp * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var u := float(i) / float(maxi(frames - 1, 1))
		var freq := lerpf(f0, f1, u)
		phase = fmod(phase + freq / float(MIX_RATE), 1.0)
		samples[i] = _wave(wave, phase) * amp * _env(t, dur)
	return _cache_stream(key, _samples_to_wav(samples))

# Short frequency steps with literal silence between them: sample-and-hold sine voice.
func _sample_hold_sine_stream(f0: float, f1: float, dur: float, amp: float) -> AudioStreamWAV:
	var key := "sh:%d:%d:%d:%d" % [int(f0), int(f1), int(dur * 1000.0), int(amp * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(dur * MIX_RATE)
	var hold_frames := maxi(1, int(MIX_RATE * 0.072))
	var notes := [0, 7, 3, 10, 5, 12, 8, 2]
	var samples: Array[float] = []
	samples.resize(frames)
	var phase := 0.0
	for i in frames:
		var step := int(i / hold_frames)
		var held := float(notes[step % notes.size()])
		var rise := lerpf(f0, f1, float(step % 10) / 9.0)
		var freq := rise * pow(2.0, held / 24.0)
		phase = fmod(phase + freq / float(MIX_RATE), 1.0)
		var local := float(i % hold_frames) / float(hold_frames)
		var gate := 1.0 if local < 0.48 else 0.0
		var t := float(i) / float(MIX_RATE)
		samples[i] = sin(phase * TAU) * amp * gate * _env(t, dur)
	return _cache_stream(key, _samples_to_wav(samples))

func _play_stream(stream: AudioStreamWAV, volume_db: float, bus := &"Master") -> void:
	if _players.is_empty():
		return
	if _golden_music:
		volume_db += GOLDEN_DB   # GOLDEN中は一律に減衰（音量の跳ね上がり対策）
	var p := _players[_player_idx]
	_player_idx = (_player_idx + 1) % _players.size()
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus              # 既定はMaster
	p.play()

# Big-explosion body: play it DRY on Master as usual, AND send a quieter copy to the
# wet-only reverb return for an additive tail. A proper send — only this sound is verbed.
const REVERB_SEND_DB := -5.0   # how loud the wet copy is relative to the dry blast
func _play_boom(stream: AudioStreamWAV, volume_db: float) -> void:
	_play_stream(stream, volume_db)                            # dry, on Master (untouched)
	_play_stream(stream, volume_db + REVERB_SEND_DB, REVERB_BUS)  # wet send
	if _reverb_bus_idx >= 0:                                   # wake the reverb bus for the tail
		AudioServer.set_bus_mute(_reverb_bus_idx, false)
		_reverb_off_at = _clock + REVERB_TAIL_SEC

func _stop_all_players() -> void:
	for p in _players:
		p.stop()

func _tone_stream(freq: float, dur: float, wave: String, amp: float) -> AudioStreamWAV:
	var key := "t:%d:%d:%s:%d" % [int(freq * 10.0), int(dur * 1000.0), wave, int(amp * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var env := _env(t, dur)
		samples[i] = _wave(wave, fmod(freq * t, 1.0)) * amp * env
	return _cache_stream(key, _samples_to_wav(samples))

func _kick_stream(dur: float, amp: float) -> AudioStreamWAV:
	var key := "k:%d:%d" % [int(dur * 1000.0), int(amp * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var f := lerpf(96.0, 43.0, clampf(t / maxf(dur, 0.001), 0.0, 1.0))
		phase = fmod(phase + f / float(MIX_RATE), 1.0)
		samples[i] = sin(phase * TAU) * amp * (1.0 - clampf(t / dur, 0.0, 1.0))
	return _cache_stream(key, _samples_to_wav(samples))

func _boom_stream(dur: float, amp: float) -> AudioStreamWAV:
	var key := "b:%d:%d" % [int(dur * 1000.0), int(amp * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		var f := lerpf(82.0, 28.0, pow(k, 0.55))
		phase = fmod(phase + f / float(MIX_RATE), 1.0)
		var env := pow(1.0 - k, 1.65)
		var body := sin(phase * TAU) + 0.35 * sin(phase * TAU * 0.5)
		samples[i] = clampf(body * amp * env, -0.92, 0.92)
	return _cache_stream(key, _samples_to_wav(samples))

func _blast_attack_stream(dur: float, amp: float) -> AudioStreamWAV:
	var key := "ba:%d:%d" % [int(dur * 1000.0), int(amp * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	var phase_a := 0.0
	var phase_b := 0.0
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		var env := pow(1.0 - k, 2.4)
		var fa := lerpf(1100.0, 340.0, k)
		var fb := lerpf(620.0, 180.0, k)
		phase_a = fmod(phase_a + fa / float(MIX_RATE), 1.0)
		phase_b = fmod(phase_b + fb / float(MIX_RATE), 1.0)
		var crack := (_rng.randf() * 2.0 - 1.0) * 0.55
		var tone := sin(phase_a * TAU) * 0.35 + sin(phase_b * TAU) * 0.25
		samples[i] = clampf((crack + tone) * amp * env, -0.92, 0.92)
	return _cache_stream(key, _samples_to_wav(samples))

func _debris_stream(dur: float, amp: float) -> AudioStreamWAV:
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	var phase := 0.0
	var base_freq := _rng.randf_range(95.0, 155.0)
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		var env := pow(1.0 - k, 2.0)
		var f := lerpf(base_freq, base_freq * 0.62, k)
		phase = fmod(phase + f / float(MIX_RATE), 1.0)
		var grit := (_rng.randf() * 2.0 - 1.0) * 0.38
		var body := sin(phase * TAU) * 0.42
		samples[i] = clampf((body + grit) * amp * env, -0.92, 0.92)
	return _samples_to_wav(samples)

func _noise_stream(dur: float, amp: float) -> AudioStreamWAV:
	# Do not cache noise; each hit should breathe a little.
	var frames := int(dur * MIX_RATE)
	var samples: Array[float] = []
	samples.resize(frames)
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var env := 1.0 - clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		samples[i] = (_rng.randf() * 2.0 - 1.0) * amp * env
	return _samples_to_wav(samples)

func _cache_stream(key: String, stream: AudioStreamWAV) -> AudioStreamWAV:
	_cache[key] = stream
	_cache_order.append(key)
	while _cache_order.size() > STREAM_CACHE_LIMIT:
		var old: String = _cache_order.pop_front()
		_cache.erase(old)
	return stream

func _samples_to_wav(samples: Array[float]) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var k := 0
	for s_v in samples:
		var v := int(clampf(float(s_v), -0.92, 0.92) * 32767.0)
		if v < 0:
			v += 65536
		data[k] = v & 0xff
		data[k + 1] = (v >> 8) & 0xff
		k += 2
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

func _env(t: float, dur: float) -> float:
	var attack := 0.006
	if t < attack:
		return t / attack
	return pow(1.0 - clampf(t / maxf(dur, 0.001), 0.0, 1.0), 1.35)

func _wave(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"pulse":
			return 1.0 if phase < 0.25 else -0.65
		"saw":
			return phase * 2.0 - 1.0
		"tri":
			return 1.0 - absf(phase * 4.0 - 2.0)
		_:
			return sin(phase * TAU)

func _degree_freq(octave: int, degree: int) -> float:
	var size: int = maxi(1, _scale.size())
	var oct_add: int = floori(float(degree) / float(size))
	var idx: int = posmod(degree, size)
	var semitone: int = int(_scale[idx]) + 12 * (octave + oct_add)
	return ROOT_FREQ * pow(2.0, float(semitone) / 12.0)

func _bounded_sfx_cursor(degree: int) -> int:
	return posmod(degree, _sfx_note_count())

func _bounded_sfx_note(degree: int) -> Vector2i:
	var target := _bounded_sfx_cursor(degree)
	var n := 0
	for octave in range(-1, 3):
		for idx in _scale.size():
			var semitone: int = int(_scale[idx]) + octave * 12
			if semitone < SFX_LOW_SEMITONE or semitone > SFX_HIGH_SEMITONE:
				continue
			if n == target:
				return Vector2i(octave, idx)
			n += 1
	return Vector2i(0, 0)

func _sfx_note_count() -> int:
	var n := 0
	for octave in range(-1, 3):
		for idx in _scale.size():
			var semitone: int = int(_scale[idx]) + octave * 12
			if semitone >= SFX_LOW_SEMITONE and semitone <= SFX_HIGH_SEMITONE:
				n += 1
	return maxi(1, n)

func _power_level() -> int:
	var p: int = GameState.formation_count
	for i in range(1, 6):
		p += max(0, GameState.unit_level(i) - 1)
	if GameState.golden_active:
		p += 6
	return p
