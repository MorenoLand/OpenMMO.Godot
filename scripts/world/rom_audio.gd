class_name OpenMMORomAudio
extends RefCounted

const SAMPLE_RATE: int = 13379
const M4A_VBLANK_RATE: float = 59.7275
const M4A_DIV_FREQ: float = 627.0
const MAX_RENDER_SECONDS: float = 60.0
const MAX_TRACK_COMMANDS: int = 12000
const MAX_TRACK_EVENTS: int = 1600
const SONG_RECORD_SIZE: int = 8
const SONG_HEADER_SIZE: int = 8
const TONE_DATA_SIZE: int = 12
const COMMAND_FINE: int = 0xB1
const COMMAND_GOTO: int = 0xB2
const COMMAND_PATT: int = 0xB3
const COMMAND_PEND: int = 0xB4
const COMMAND_REPT: int = 0xB5
const COMMAND_MEMACC: int = 0xB9
const COMMAND_PRIO: int = 0xBA
const COMMAND_TEMPO: int = 0xBB
const COMMAND_KEYSH: int = 0xBC
const COMMAND_VOICE: int = 0xBD
const COMMAND_VOL: int = 0xBE
const COMMAND_PAN: int = 0xBF
const COMMAND_BEND: int = 0xC0
const COMMAND_BENDR: int = 0xC1
const COMMAND_LFOS: int = 0xC2
const COMMAND_LFODL: int = 0xC3
const COMMAND_MOD: int = 0xC4
const COMMAND_MODT: int = 0xC5
const COMMAND_TUNE: int = 0xC8
const COMMAND_XCMD: int = 0xCD
const COMMAND_EOT: int = 0xCE
const COMMAND_TIE: int = 0xCF
const TONE_TYPE_SPLIT: int = 0x40
const TONE_TYPE_RHYTHM: int = 0x80
const WAVE_LOOP_FLAG: int = 0xC0
const WAVE_HEADER_SIZE: int = 16
const CLOCK_TABLE: Array[int] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x1C, 0x1E, 0x20, 0x24, 0x28, 0x2A, 0x2C, 0x30, 0x34, 0x36, 0x38, 0x3C, 0x40, 0x42, 0x44, 0x48, 0x4C, 0x4E, 0x50, 0x54, 0x58, 0x5A, 0x5C, 0x60]
const DELTA_TABLE: Array[int] = [0, 1, 4, 9, 16, 25, 36, 49, -64, -49, -36, -25, -16, -9, -4, -1]
const MIDI_FREQ_TABLE: Array[int] = [2147483648, 2275179671, 2410468894, 2553802834, 2705659852, 2866546760, 3037000500, 3217589947, 3408917802, 3611622603, 3826380858, 4053909305]
var song_table_cache: Dictionary = {}
var song_cache: Dictionary = {}
var stream_cache: Dictionary = {}
var wave_cache: Dictionary = {}
var last_error: String = ""

func build_song_stream(content: OpenMMOContent, song_id: int) -> AudioStream:
	var prepared: Dictionary = prepare_song(content, song_id)
	if prepared.is_empty():
		return null
	var cache_key: String = str(prepared.get("cache_key", ""))
	var cached: Variant = stream_cache.get(cache_key)
	if cached is AudioStream:
		return cached as AudioStream
	var stream: AudioStream = _render_song(prepared.get("data", PackedByteArray()) as PackedByteArray, prepared.get("song", {}) as Dictionary, prepared.get("parsed", {}) as Dictionary)
	if stream == null:
		last_error = "ROM audio song produced no playable frames"
		return null
	stream_cache[cache_key] = stream
	return stream
func inspect_song(content: OpenMMOContent, song_id: int) -> Dictionary:
	var prepared: Dictionary = prepare_song(content, song_id)
	if prepared.is_empty():
		return {"ok": false, "error": last_error}
	var song: Dictionary = prepared.get("song", {}) as Dictionary
	var parsed: Dictionary = prepared.get("parsed", {}) as Dictionary
	return {"ok": true, "song_table_offset": int(song.get("song_table_offset", -1)), "song_id": song_id, "music_player": int(song.get("music_player", -1)), "track_count": int(song.get("track_count", 0)), "event_count": int(parsed.get("event_count", 0)), "duration": float(parsed.get("duration", 0.0)), "tempo": float(parsed.get("tempo", 150.0))}

func prepare_song(content: OpenMMOContent, song_id: int) -> Dictionary:
	last_error = ""
	if content == null or content.rom_data.is_empty() or song_id < 0:
		last_error = "selected ROM has no audio data"
		return {}
	var cache_key: String = _content_key(content) + ":" + str(song_id)
	var cached: Variant = song_cache.get(cache_key)
	if cached is Dictionary:
		return cached as Dictionary
	var song: Dictionary = _read_song(content.rom_data, song_id, _audio_table_hint(content), _content_key(content), _audio_anchor_ids(content))
	if song.is_empty():
		return {}
	var parsed: Dictionary = _parse_song(content.rom_data, song)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "ROM audio track could not be parsed"))
		return {}
	var duration: float = clampf(float(parsed.get("duration", 0.0)) + 0.05, 0.25, MAX_RENDER_SECONDS)
	var duration_frames: int = maxi(int(ceil(duration * SAMPLE_RATE)), 1)
	var loop_duration: float = float(parsed.get("loop_duration", duration))
	if loop_duration <= 0.0:
		loop_duration = duration
	loop_duration = clampf(loop_duration, 0.25, duration)
	var prepared: Dictionary = {"ok": true, "cache_key": cache_key, "song": song, "parsed": parsed, "data": content.rom_data, "events": parsed.get("events", []), "duration": duration, "duration_frames": duration_frames, "loop_duration": loop_duration, "loop_frames": maxi(int(ceil(loop_duration * SAMPLE_RATE)), 1)}
	song_cache[cache_key] = prepared
	return prepared

func _content_key(content: OpenMMOContent) -> String:
	var fingerprint: String = content.rom_sha1
	if fingerprint.is_empty():
		fingerprint = str(content.rom_data.size())
	return str(content.source_profile.get("id", "gba")) + ":" + fingerprint

func _audio_table_hint(content: OpenMMOContent) -> int:
	var audio_profile: Dictionary = content.source_profile.get("audio", {})
	return int(audio_profile.get("song_table_offset", -1))

func _audio_anchor_ids(content: OpenMMOContent) -> Array[int]:
	var audio_profile: Dictionary = content.source_profile.get("audio", {})
	var values: Array[int] = []
	for value in audio_profile.get("anchor_song_ids", []):
		values.append(int(value))
	return values

func _read_song(data: PackedByteArray, song_id: int, table_hint: int = -1, table_cache_key: String = "", anchor_ids: Array[int] = []) -> Dictionary:
	var table_offset: int = _song_table_offset(data, table_hint, table_cache_key, anchor_ids)
	if table_offset < 0:
		last_error = "ROM song table was not found"
		return {}
	var record_offset: int = table_offset + song_id * SONG_RECORD_SIZE
	if not _valid_range(data, record_offset, SONG_RECORD_SIZE):
		last_error = "ROM song ID %d is outside the discovered song table" % song_id
		return {}
	var header_offset: int = _read_pointer(data, record_offset)
	if header_offset < 0 or not _valid_song_header(data, header_offset):
		last_error = "ROM song ID %d has an invalid song header" % song_id
		return {}
	var track_count: int = int(data[header_offset])
	var tracks: Array = []
	for track_index in range(track_count):
		tracks.append(_read_pointer(data, header_offset + SONG_HEADER_SIZE + track_index * 4))
	return {"song_table_offset": table_offset, "song_id": song_id, "header_offset": header_offset, "music_player": _read_u16(data, record_offset + 4), "unknown": _read_u16(data, record_offset + 6), "track_count": track_count, "tone_offset": _read_pointer(data, header_offset + 4), "tracks": tracks}

func _song_table_offset(data: PackedByteArray, table_hint: int = -1, table_cache_key: String = "", anchor_ids: Array[int] = []) -> int:
	var cache_key: String = table_cache_key + ":" + str(data.size()) + ":" + str(table_hint)
	var cached: Variant = song_table_cache.get(cache_key)
	if cached is int and int(cached) >= 0:
		return int(cached)
	if anchor_ids.is_empty():
		return -1
	if table_hint >= 0 and _valid_song_table_candidate(data, table_hint, anchor_ids):
		song_table_cache[cache_key] = table_hint
		return table_hint
	var min_anchor: int = anchor_ids[0]
	var max_anchor: int = anchor_ids[0]
	for anchor_id in anchor_ids:
		min_anchor = mini(min_anchor, anchor_id)
		max_anchor = maxi(max_anchor, anchor_id)
	var scan_end: int = data.size() - (max_anchor + 1) * SONG_RECORD_SIZE
	var candidate: int = -1
	if scan_end >= 0:
		for record_offset in range(0, scan_end + 1, 4):
			var header_offset: int = _read_pointer(data, record_offset)
			if header_offset < 0 or not _valid_song_header(data, header_offset):
				continue
			var base_offset: int = record_offset - min_anchor * SONG_RECORD_SIZE
			if base_offset < 0 or not _valid_song_table_candidate(data, base_offset, anchor_ids):
				continue
			candidate = base_offset
			break
	if candidate >= 0:
		song_table_cache[cache_key] = candidate
	return candidate

func _valid_song_table_candidate(data: PackedByteArray, table_offset: int, anchor_ids: Array[int]) -> bool:
	for song_id in anchor_ids:
		var record_offset: int = table_offset + song_id * SONG_RECORD_SIZE
		if not _valid_range(data, record_offset, SONG_RECORD_SIZE):
			return false
		var header_offset: int = _read_pointer(data, record_offset)
		if header_offset < 0 or not _valid_song_header(data, header_offset):
			return false
		var music_player: int = _read_u16(data, record_offset + 4)
		if music_player < 0 or music_player > 3:
			return false
	return true

func _valid_song_header(data: PackedByteArray, offset: int) -> bool:
	if not _valid_range(data, offset, SONG_HEADER_SIZE):
		return false
	var track_count: int = int(data[offset])
	if track_count < 1 or track_count > 16:
		return false
	var tone_offset: int = _read_pointer(data, offset + 4)
	if tone_offset < 0 or not _valid_range(data, tone_offset, TONE_DATA_SIZE):
		return false
	if not _valid_range(data, offset + SONG_HEADER_SIZE, track_count * 4):
		return false
	for track_index in range(track_count):
		var track_offset: int = _read_pointer(data, offset + SONG_HEADER_SIZE + track_index * 4)
		if track_offset < 0 or not _valid_range(data, track_offset, 1):
			return false
		if int(data[track_offset]) < 0x80:
			return false
	return true

func _parse_song(data: PackedByteArray, song: Dictionary) -> Dictionary:
	var all_events: Array = []
	var tempo_changes: Array = []
	var parsed_tracks: Array = []
	var duration_ticks: int = 0
	var duration_extra_seconds: float = 0.0
	var loop_duration_ticks: int = 0
	var loop_extra_seconds: float = 0.0
	var event_count: int = 0
	var tracks: Array = song.get("tracks", [])
	for track_index in range(tracks.size()):
		var track_value: Variant = tracks[track_index]
		var track_offset: int = int(track_value)
		var parsed_track: Dictionary = _parse_track(data, track_offset, int(song.get("tone_offset", -1)), 150.0)
		if not bool(parsed_track.get("ok", false)):
			continue
		parsed_tracks.append(parsed_track)
		duration_ticks = maxi(duration_ticks, int(parsed_track.get("duration_ticks", 0)))
		duration_extra_seconds = maxf(duration_extra_seconds, float(parsed_track.get("duration_extra_seconds", 0.0)))
		var track_loop_ticks: int = int(parsed_track.get("loop_duration_ticks", 0))
		if track_loop_ticks > loop_duration_ticks:
			loop_duration_ticks = track_loop_ticks
			loop_extra_seconds = float(parsed_track.get("loop_extra_seconds", 0.0))
		for change_value in parsed_track.get("tempo_changes", []):
			var change: Dictionary = change_value as Dictionary
			var change_tick: int = int(change.get("tick", 0))
			var inserted: bool = false
			for existing_index in range(tempo_changes.size()):
				if change_tick < int((tempo_changes[existing_index] as Dictionary).get("tick", 0)):
					tempo_changes.insert(existing_index, change)
					inserted = true
					break
			if not inserted:
				tempo_changes.append(change)
	for parsed_track_value in parsed_tracks:
		var parsed_track: Dictionary = parsed_track_value as Dictionary
		var track_events: Array = parsed_track.get("events", [])
		for event_value in track_events:
			var event: Dictionary = (event_value as Dictionary).duplicate(true)
			var start_tick: int = int(event.get("start_tick", 0))
			var end_tick: int = start_tick + int(event.get("duration_ticks", 0))
			var start_seconds: float = _ticks_to_seconds(start_tick, tempo_changes) + float(event.get("start_extra_seconds", 0.0))
			var end_seconds: float = _ticks_to_seconds(end_tick, tempo_changes) + float(event.get("start_extra_seconds", 0.0))
			event["start"] = start_seconds
			event["duration"] = maxf(end_seconds - start_seconds, 1.0 / float(SAMPLE_RATE))
			all_events.append(event)
			event_count += 1
	if all_events.is_empty():
		return {"ok": false, "error": "ROM song contains no decodable note events"}
	var duration: float = _ticks_to_seconds(duration_ticks, tempo_changes) + duration_extra_seconds
	var loop_duration: float = 0.0
	if loop_duration_ticks > 0:
		loop_duration = _ticks_to_seconds(loop_duration_ticks, tempo_changes) + loop_extra_seconds
	return {"ok": true, "events": all_events, "event_count": event_count, "duration": duration, "loop_duration": loop_duration, "tempo": float(tempo_changes[0].get("tempo", 150.0)) if not tempo_changes.is_empty() else 150.0, "tempo_changes": tempo_changes}

func _parse_track(data: PackedByteArray, track_offset: int, tone_offset: int, initial_tempo: float = 150.0) -> Dictionary:
	if track_offset < 0 or not _valid_range(data, track_offset, 1):
		return {"ok": false}
	var cursor: int = track_offset
	var now_ticks: int = 0
	var now_extra_seconds: float = 0.0
	var tempo: float = initial_tempo
	var running_status: int = 0
	var key: int = 60
	var velocity: int = 127
	var voice_index: int = 0
	var volume: int = 127
	var pan: int = 0
	var key_shift: int = 0
	var bend: int = 0
	var bend_range: int = 2
	var tune: int = 0
	var dynamic_tone: Dictionary = _read_tone(data, tone_offset, voice_index)
	var pattern_stack: Array[int] = []
	var repeat_counts: Dictionary = {}
	var mem_acc: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var events: Array = []
	var command_count: int = 0
	var loop_target: int = -1
	var loop_duration_ticks: int = 0
	var loop_extra_seconds: float = 0.0
	var tempo_changes: Array = []
	while cursor >= 0 and cursor < data.size() and command_count < MAX_TRACK_COMMANDS and events.size() < MAX_TRACK_EVENTS:
		command_count += 1
		var command_offset: int = cursor
		var raw: int = int(data[cursor])
		var status: int = raw
		if raw >= 0x80:
			cursor += 1
			if raw >= 0xBD:
				running_status = raw
		else:
			if running_status == 0:
				break
			status = running_status
		if status >= 0x80 and status <= 0xB0:
			now_ticks += _clock_value(status - 0x80)
			continue
		if status >= COMMAND_TIE:
			var note_index: int = status - 0xCF
			var gate_ticks: int = _clock_value(note_index)
			var note_key: int = key
			if raw < 0x80:
				note_key = raw
				cursor += 1
			elif cursor < data.size() and int(data[cursor]) < 0x80:
				note_key = int(data[cursor])
				cursor += 1
			if cursor < data.size() and int(data[cursor]) < 0x80:
				velocity = int(data[cursor])
				cursor += 1
			if cursor < data.size() and int(data[cursor]) < 0x80:
				gate_ticks += int(data[cursor])
				cursor += 1
			key = note_key
			if gate_ticks > 0:
				var event_tone: Dictionary = dynamic_tone.duplicate(true)
				var pitch_units: int = (tune + bend * bend_range) * 4
				var pitch_key_offset: int = floori(float(pitch_units) / 256.0)
				var fine_adjust: int = posmod(pitch_units, 256)
				events.append({"start_tick": now_ticks, "duration_ticks": gate_ticks, "start_extra_seconds": now_extra_seconds, "key": note_key + key_shift + pitch_key_offset, "fine_adjust": fine_adjust, "velocity": velocity, "volume": volume, "pan": pan, "bend": bend, "bend_range": bend_range, "tune": tune, "tone": event_tone})
			continue
		match status:
			COMMAND_FINE:
				break
			COMMAND_GOTO:
				if not _valid_range(data, cursor, 4):
					break
				var target: int = _read_pointer(data, cursor)
				cursor += 4
				if target < 0:
					break
				if target == loop_target or (target <= command_offset and now_ticks > 0):
					loop_target = target
					loop_duration_ticks = now_ticks
					loop_extra_seconds = now_extra_seconds
					break
				loop_target = target
				cursor = target
			COMMAND_PATT:
				if not _valid_range(data, cursor, 4) or pattern_stack.size() >= 3:
					break
				var pattern_target: int = _read_pointer(data, cursor)
				pattern_stack.append(cursor + 4)
				cursor = pattern_target
			COMMAND_PEND:
				if pattern_stack.is_empty():
					break
				cursor = int(pattern_stack.pop_back())
			COMMAND_REPT:
				if not _valid_range(data, cursor, 5):
					break
				var repeat_offset: int = cursor
				var repeat_total: int = int(data[cursor])
				var repeat_target: int = _read_pointer(data, cursor + 1)
				if repeat_total == 0:
					cursor = repeat_target
					continue
				var repeat_count: int = int(repeat_counts.get(repeat_offset, 0)) + 1
				if repeat_count < repeat_total:
					repeat_counts[repeat_offset] = repeat_count
					cursor = repeat_target
				else:
					repeat_counts.erase(repeat_offset)
					cursor += 5
			COMMAND_MEMACC:
				if not _valid_range(data, cursor, 3):
					break
				var mem_op: int = int(data[cursor])
				var mem_address: int = int(data[cursor + 1]) & 0x0F
				var mem_value: int = int(data[cursor + 2])
				cursor += 3
				var condition: bool = _apply_memacc(mem_acc, mem_op, mem_address, mem_value)
				if mem_op >= 6:
					if condition and _valid_range(data, cursor, 4):
						cursor = _read_pointer(data, cursor)
					else:
						cursor += 4
			COMMAND_PRIO, COMMAND_LFOS, COMMAND_LFODL, COMMAND_MOD, COMMAND_MODT:
				if cursor < data.size():
					cursor += 1
			COMMAND_TEMPO:
				if cursor >= data.size():
					break
				tempo = maxf(float(int(data[cursor]) * 2), 1.0)
				tempo_changes.append({"tick": now_ticks, "tempo": tempo})
				cursor += 1
			COMMAND_KEYSH:
				if cursor >= data.size():
					break
				key_shift = _signed_byte(int(data[cursor]))
				cursor += 1
			COMMAND_VOICE:
				if cursor >= data.size():
					break
				voice_index = int(data[cursor])
				dynamic_tone = _read_tone(data, tone_offset, voice_index)
				cursor += 1
			COMMAND_VOL:
				if cursor >= data.size():
					break
				volume = int(data[cursor])
				cursor += 1
			COMMAND_PAN:
				if cursor >= data.size():
					break
				pan = _signed_byte(int(data[cursor]) - 0x40)
				cursor += 1
			COMMAND_BEND:
				if cursor >= data.size():
					break
				bend = _signed_byte(int(data[cursor]) - 0x40)
				cursor += 1
			COMMAND_BENDR:
				if cursor >= data.size():
					break
				bend_range = maxi(int(data[cursor]), 1)
				cursor += 1
			COMMAND_TUNE:
				if cursor >= data.size():
					break
				tune = _signed_byte(int(data[cursor]) - 0x40)
				cursor += 1
			COMMAND_XCMD:
				var xcmd_result: Dictionary = _parse_xcmd(data, cursor, dynamic_tone)
				if not bool(xcmd_result.get("ok", false)):
					break
				cursor = int(xcmd_result.get("cursor", cursor))
				dynamic_tone = xcmd_result.get("tone", dynamic_tone)
				if float(xcmd_result.get("wait_seconds", 0.0)) > 0.0:
					now_extra_seconds += float(xcmd_result.get("wait_seconds", 0.0))
				if bool(xcmd_result.get("stop", false)):
					break
			COMMAND_EOT:
				if cursor < data.size() and int(data[cursor]) < 0x80:
					key = int(data[cursor])
					cursor += 1
			_:
				if status >= 0x80 and status < COMMAND_TIE and cursor <= command_offset:
					break
	return {"ok": not events.is_empty(), "events": events, "duration_ticks": now_ticks, "duration_extra_seconds": now_extra_seconds, "loop_duration_ticks": loop_duration_ticks, "loop_extra_seconds": loop_extra_seconds, "tempo_changes": tempo_changes}

func _parse_xcmd(data: PackedByteArray, cursor: int, tone: Dictionary) -> Dictionary:
	if cursor >= data.size():
		return {"ok": false}
	var command: int = int(data[cursor])
	cursor += 1
	var updated: Dictionary = tone.duplicate(true)
	var wait_seconds: float = 0.0
	match command:
		1:
			if not _valid_range(data, cursor, 4):
				return {"ok": false}
			updated["wav"] = _read_pointer(data, cursor)
			cursor += 4
		2, 4, 5, 6, 7, 8, 9, 10, 11:
			if cursor >= data.size():
				return {"ok": false}
			match command:
				2:
					updated["type"] = int(data[cursor])
				3:
					updated["type"] = int(data[cursor])
				4:
					updated["attack"] = int(data[cursor])
				5:
					updated["decay"] = int(data[cursor])
				6:
					updated["sustain"] = int(data[cursor])
				7:
					updated["release"] = int(data[cursor])
				8:
					updated["echo_volume"] = int(data[cursor])
				9:
					updated["echo_length"] = int(data[cursor])
				10:
					updated["length"] = int(data[cursor])
				11:
					updated["pan_sweep"] = int(data[cursor])
			cursor += 1
		3:
			return {"ok": true, "cursor": cursor, "tone": updated, "wait_seconds": 0.0, "stop": true}
		12:
			if not _valid_range(data, cursor, 2):
				return {"ok": false}
			wait_seconds = float(_read_u16(data, cursor)) / M4A_VBLANK_RATE
			cursor += 2
		13:
			if not _valid_range(data, cursor, 4):
				return {"ok": false}
			cursor += 4
		_:
			return {"ok": false}
	return {"ok": true, "cursor": cursor, "tone": updated, "wait_seconds": wait_seconds}

func _apply_memacc(memory: Array[int], operation: int, address: int, value: int) -> bool:
	var current: int = int(memory[address])
	match operation:
		0:
			memory[address] = value & 0xFF
		1:
			memory[address] = (current + value) & 0xFF
		2:
			memory[address] = (current - value) & 0xFF
		3:
			memory[address] = int(memory[value & 0x0F])
		4:
			memory[address] = (current + int(memory[value & 0x0F])) & 0xFF
		5:
			memory[address] = (current - int(memory[value & 0x0F])) & 0xFF
		6:
			return current == value
		7:
			return current != value
		8:
			return current > value
		9:
			return current >= value
		10:
			return current <= value
		11:
			return current < value
		12:
			return current == int(memory[value & 0x0F])
		13:
			return current != int(memory[value & 0x0F])
		14:
			return current > int(memory[value & 0x0F])
		15:
			return current >= int(memory[value & 0x0F])
		16:
			return current <= int(memory[value & 0x0F])
		17:
			return current < int(memory[value & 0x0F])
	return false

func _read_tone(data: PackedByteArray, tone_offset: int, voice_index: int) -> Dictionary:
	var offset: int = tone_offset + voice_index * TONE_DATA_SIZE
	if tone_offset < 0 or voice_index < 0 or not _valid_range(data, offset, TONE_DATA_SIZE):
		return {}
	var pan_sweep: int = int(data[offset + 3])
	return {"offset": offset, "type": int(data[offset]), "base_key": int(data[offset + 1]), "length": int(data[offset + 2]), "pan_sweep": pan_sweep, "pan": (pan_sweep & 0x7F) - 64 if (pan_sweep & 0x80) != 0 else 0, "duty": int(data[offset + 4]) & 0x03, "period": int(data[offset + 4]) & 0x01, "wav": _read_pointer(data, offset + 4), "keysplit": _read_pointer(data, offset + 8), "attack": int(data[offset + 8]), "decay": int(data[offset + 9]), "sustain": int(data[offset + 10]), "release": int(data[offset + 11])}

func _resolve_tone(data: PackedByteArray, tone: Dictionary, key: int, depth: int = 0) -> Dictionary:
	if tone.is_empty() or depth >= 8:
		return {}
	var type: int = int(tone.get("type", -1))
	if (type & TONE_TYPE_SPLIT) != 0:
		var group_offset: int = int(tone.get("wav", -1))
		var split_offset: int = int(tone.get("keysplit", -1))
		if group_offset < 0 or split_offset < 0 or not _valid_range(data, split_offset + clampi(key, 0, 255), 1):
			return {}
		var child_index: int = int(data[split_offset + clampi(key, 0, 255)])
		return _resolve_tone(data, _read_tone(data, group_offset, child_index), key, depth + 1)
	if (type & TONE_TYPE_RHYTHM) != 0:
		var rhythm_group: int = int(tone.get("wav", -1))
		if rhythm_group < 0:
			return {}
		var resolved: Dictionary = _resolve_tone(data, _read_tone(data, rhythm_group, clampi(key, 0, 255)), key, depth + 1).duplicate()
		var pan_sweep: int = int(resolved.get("pan_sweep", 0))
		resolved["rhythm_pan"] = ((pan_sweep & 0x7F) - 64) * 2 if (pan_sweep & 0x80) != 0 else 0
		return resolved
	return tone

func _render_song(data: PackedByteArray, song: Dictionary, parsed: Dictionary) -> AudioStream:
	var events: Array = parsed.get("events", [])
	var duration: float = clampf(float(parsed.get("duration", 0.0)) + 0.05, 0.25, MAX_RENDER_SECONDS)
	var frame_count: int = maxi(int(ceil(duration * SAMPLE_RATE)), 1)
	var mix: PackedFloat32Array = PackedFloat32Array()
	mix.resize(frame_count * 2)
	for event_value in events:
		if not event_value is Dictionary:
			continue
		_render_event(mix, frame_count, data, event_value as Dictionary)
	var peak: float = 0.0
	for value in mix:
		peak = maxf(peak, absf(float(value)))
	var scale: float = 0.82 if peak <= 0.82 else 0.82 / peak
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(frame_count * 4)
	for frame in range(frame_count):
		var left: int = clampi(int(round(clampf(float(mix[frame * 2]) * scale, -1.0, 1.0) * 32767.0)), -32768, 32767)
		var right: int = clampi(int(round(clampf(float(mix[frame * 2 + 1]) * scale, -1.0, 1.0) * 32767.0)), -32768, 32767)
		pcm.encode_s16(frame * 4, left)
		pcm.encode_s16(frame * 4 + 2, right)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = pcm
	if int(song.get("music_player", 1)) == 0:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frame_count
	return stream

func render_song_frames(prepared: Dictionary, start_frame: int, frame_count: int) -> PackedVector2Array:
	var output: PackedVector2Array = PackedVector2Array()
	if not bool(prepared.get("ok", false)) or frame_count <= 0:
		return output
	var data: PackedByteArray = prepared.get("data", PackedByteArray()) as PackedByteArray
	var events: Array = prepared.get("events", [])
	var loop_frames: int = maxi(int(prepared.get("loop_frames", prepared.get("duration_frames", 0))), 1)
	output.resize(frame_count)
	var written: int = 0
	var cursor: int = posmod(start_frame, loop_frames)
	while written < frame_count:
		var segment_frames: int = mini(frame_count - written, loop_frames - cursor)
		var mix: PackedFloat32Array = PackedFloat32Array()
		mix.resize(segment_frames * 2)
		for event_value in events:
			if event_value is Dictionary:
				_render_event(mix, segment_frames, data, event_value as Dictionary, cursor)
		for frame in range(segment_frames):
			var left: float = clampf(float(mix[frame * 2]) * 0.62, -1.0, 1.0)
			var right: float = clampf(float(mix[frame * 2 + 1]) * 0.62, -1.0, 1.0)
			output[written + frame] = Vector2(left, right)
		written += segment_frames
		cursor = 0
	return output

func _render_event(mix: PackedFloat32Array, frame_count: int, data: PackedByteArray, event: Dictionary, base_frame: int = 0) -> void:
	var start_frame: int = maxi(int(floor(float(event.get("start", 0.0)) * SAMPLE_RATE)), 0)
	var event_frames: int = maxi(int(ceil(float(event.get("duration", 0.0)) * SAMPLE_RATE)), 1)
	var tone: Dictionary = _resolve_tone(data, event.get("tone", {}) as Dictionary, int(event.get("key", 60)))
	var pcm_envelope: PackedFloat32Array = PackedFloat32Array()
	if (int(tone.get("type", -1)) & 0x0F) in [0, 8]:
		pcm_envelope = _pcm_envelope(tone, event_frames)
	var rendered_frames: int = maxi(event_frames, ceili(float(pcm_envelope.size()) * SAMPLE_RATE / M4A_VBLANK_RATE))
	var end_frame: int = start_frame + rendered_frames
	var mix_start: int = maxi(start_frame, base_frame)
	var mix_end: int = mini(base_frame + frame_count, end_frame)
	if mix_start >= mix_end:
		return
	if tone.is_empty():
		return
	var type: int = int(tone.get("type", -1))
	var note_key: int = int(event.get("key", 60))
	var fine_adjust: int = clampi(int(event.get("fine_adjust", 0)), 0, 255)
	var pitch_key: float = float(note_key) + float(fine_adjust) / 256.0
	var gains: Vector2 = _pcm_stereo_gains(int(event.get("velocity", 127)), int(event.get("volume", 127)), int(event.get("pan", 0)), int(tone.get("rhythm_pan", 0))) * (0.28 * sqrt(2.0) / 255.0)
	var left_gain: float = gains.x
	var right_gain: float = gains.y
	var phase: float = 0.0
	var noise_state: int = 0x7FFF
	var wave: Dictionary = {}
	if (type & 0x0F) == 0 or (type & 0x0F) == 8:
		wave = _read_wave(data, int(tone.get("wav", -1)))
		if wave.is_empty():
			return
	var phase_step: float = 440.0 * pow(2.0, (pitch_key - 69.0) / 12.0) / float(SAMPLE_RATE)
	if not wave.is_empty():
		if (type & 0x0F) == 8:
			phase_step = 1.0
		else:
			var frequency_fixed: int = _midi_key_to_freq(wave, note_key, fine_adjust)
			phase_step = float(frequency_fixed) * M4A_DIV_FREQ / 8388608.0
	phase = float(mix_start - start_frame) * phase_step
	for frame in range(mix_start, mix_end):
		var local_frame: int = frame - start_frame
		var sample: float = _voice_sample(data, tone, type, phase, wave, noise_state)
		if (type & 0x0F) == 4 or (type & 0x0F) == 12:
			noise_state = int(_voice_sample_state)
		var envelope: float = pcm_envelope[mini(floori(float(local_frame) * M4A_VBLANK_RATE / SAMPLE_RATE), pcm_envelope.size() - 1)] if not pcm_envelope.is_empty() else _envelope(float(local_frame) / float(maxi(event_frames, 1)), tone)
		var mix_frame: int = frame - base_frame
		mix[mix_frame * 2] += sample * envelope * left_gain
		mix[mix_frame * 2 + 1] += sample * envelope * right_gain
		phase += phase_step

var _voice_sample_state: int = 0x7FFF

func _voice_sample(data: PackedByteArray, tone: Dictionary, type: int, phase: float, wave: Dictionary, noise_state: int) -> float:
	var base_type: int = type & 0x0F
	if base_type == 0 or base_type == 8:
		var samples: PackedFloat32Array = wave.get("samples", PackedFloat32Array()) as PackedFloat32Array
		if samples.is_empty():
			return 0.0
		var sample_index: int = floori(phase)
		var loop_start: int = int(wave.get("loop_start", 0))
		var loop_end: int = int(wave.get("loop_end", samples.size()))
		var looping: bool = bool(wave.get("loop", false)) and loop_end > loop_start
		if sample_index >= loop_end:
			if looping:
				sample_index = loop_start + posmod(sample_index - loop_start, loop_end - loop_start)
			else:
				return 0.0
		if sample_index < 0 or sample_index >= samples.size():
			return 0.0
		var next_index: int = sample_index + 1
		if next_index >= loop_end:
			next_index = loop_start if looping else mini(next_index, samples.size() - 1)
		return lerpf(float(samples[sample_index]), float(samples[next_index]), clampf(phase - floorf(phase), 0.0, 1.0))
	if base_type == 1 or base_type == 2:
		var duty_table: Array[float] = [0.125, 0.25, 0.5, 0.75]
		var duty: float = duty_table[clampi(int(tone.get("duty", 0)), 0, 3)]
		return 1.0 if fmod(phase, 1.0) < duty else -1.0
	if base_type == 3:
		var wave_offset: int = int(tone.get("wav", -1))
		if not _valid_range(data, wave_offset, 16):
			return 0.0
		var sample_index: int = posmod(int(floor(phase * 32.0)), 32)
		var packed: int = int(data[wave_offset + (sample_index >> 1)])
		var nibble: int = packed & 0x0F if (sample_index & 1) == 0 else (packed >> 4) & 0x0F
		return float(nibble - 8) / 8.0
	if base_type == 4:
		var state: int = noise_state & 0x7FFF
		var bit: int = (state ^ (state >> 1)) & 1
		state = (state >> 1) | (bit << 14)
		_voice_sample_state = state
		return 1.0 if (state & 1) != 0 else -1.0
	return 0.0

func _read_wave(data: PackedByteArray, offset: int) -> Dictionary:
	if offset < 0 or not _valid_range(data, offset, WAVE_HEADER_SIZE):
		return {}
	var cached: Variant = wave_cache.get(str(offset))
	if cached is Dictionary:
		return cached as Dictionary
	var wave_type: int = _read_u16(data, offset)
	var status: int = _read_u16(data, offset + 2)
	var frequency_fixed: int = _read_u32(data, offset + 4)
	var loop_start: int = _read_u32(data, offset + 8)
	var sample_count: int = _read_u32(data, offset + 12)
	if sample_count <= 0 or sample_count > 2000000 or frequency_fixed <= 0:
		return {}
	var block_count: int = (sample_count + 63) >> 6
	var payload_size: int = sample_count if wave_type == 0 else block_count * 33
	if not _valid_range(data, offset + 16, payload_size):
		return {}
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(sample_count)
	if wave_type == 0:
		for sample_index in range(sample_count):
			samples[sample_index] = float(_signed_byte(int(data[offset + WAVE_HEADER_SIZE + sample_index]))) / 128.0
	else:
		for block_index in range(block_count):
			var block_sample: int = block_index << 6
			var block_offset: int = offset + WAVE_HEADER_SIZE + block_index * 33
			var current: int = _signed_byte(int(data[block_offset]))
			samples[block_sample] = float(current) / 128.0
			for sample_in_block in range(1, mini(64, sample_count - block_sample)):
				var payload_index: int = sample_in_block - 1
				var byte_index: int = 0 if payload_index == 0 else 1 + ((payload_index - 1) >> 1)
				var packed: int = int(data[block_offset + 1 + byte_index])
				var delta_index: int = packed & 0x0F if payload_index == 0 or ((payload_index - 1) & 1) == 1 else (packed >> 4) & 0x0F
				current = clampi(current + DELTA_TABLE[delta_index], -128, 127)
				samples[block_sample + sample_in_block] = float(current) / 128.0
	var loop_end: int = sample_count
	var result: Dictionary = {"samples": samples, "frequency_fixed": frequency_fixed, "sample_rate": float(frequency_fixed), "loop_start": clampi(loop_start, 0, sample_count), "loop_end": loop_end, "loop": (status & WAVE_LOOP_FLAG) != 0}
	wave_cache[str(offset)] = result
	return result

func _midi_key_to_freq(wave: Dictionary, key: int, fine_adjust: int) -> int:
	var clamped_key: int = clampi(key, 0, 178)
	var adjusted_fine: int = clampi(fine_adjust, 0, 255)
	if key > 178:
		adjusted_fine = 255
	var scale: int = ((14 - int(clamped_key / 12)) << 4) | (clamped_key % 12)
	var next_key: int = mini(clamped_key + 1, 179)
	var next_scale: int = ((14 - int(next_key / 12)) << 4) | (next_key % 12)
	var value_one: int = MIDI_FREQ_TABLE[scale & 0x0F] >> (scale >> 4)
	var value_two: int = MIDI_FREQ_TABLE[next_scale & 0x0F] >> (next_scale >> 4)
	var interpolated: int = value_one + ((value_two - value_one) * adjusted_fine >> 8)
	return int((int(wave.get("frequency_fixed", 0)) * interpolated) >> 32)

func _pcm_stereo_gains(velocity: int, volume: int, pan: int, rhythm_pan: int = 0) -> Vector2:
	var track_volume: int = clampi(volume, 0, 127) * 2
	var track_pan: int = clampi(pan * 2, -128, 127)
	var right: int = ((track_pan + 128) * track_volume) >> 8
	var left: int = ((127 - track_pan) * track_volume) >> 8
	var note_velocity: int = clampi(velocity, 0, 127)
	var drum_pan: int = clampi(rhythm_pan, -128, 127)
	return Vector2(mini(255, ((127 - drum_pan) * note_velocity * left) >> 14), mini(255, ((128 + drum_pan) * note_velocity * right) >> 14))

var pcm_envelope_cache: Dictionary = {}

func _pcm_envelope(tone: Dictionary, gate_frames: int) -> PackedFloat32Array:
	var attack: int = clampi(int(tone.get("attack", 0)), 0, 255)
	var decay: int = clampi(int(tone.get("decay", 0)), 0, 255)
	var sustain: int = clampi(int(tone.get("sustain", 0)), 0, 255)
	var release: int = clampi(int(tone.get("release", 0)), 0, 255)
	var gate_ticks: int = maxi(1, ceili(float(gate_frames) * M4A_VBLANK_RATE / SAMPLE_RATE))
	var key: String = "%d:%d:%d:%d:%d" % [attack, decay, sustain, release, gate_ticks]
	if pcm_envelope_cache.has(key):
		return pcm_envelope_cache[key]
	var levels: PackedFloat32Array = PackedFloat32Array()
	var level: int = 0
	var attacking: bool = true
	for tick in range(gate_ticks):
		if attacking:
			level = mini(255, level + attack)
			attacking = level < 255
		else:
			level = maxi(sustain, (level * decay) >> 8)
		levels.append(float(level) / 255.0)
	while level > 0:
		level = (level * release) >> 8
		levels.append(float(level) / 255.0)
	pcm_envelope_cache[key] = levels
	return levels

func _envelope(progress: float, tone: Dictionary) -> float:
	var attack: float = float(int(tone.get("attack", 0)))
	var decay: float = float(int(tone.get("decay", 0)))
	var sustain: float = clampf(float(int(tone.get("sustain", 15))) / 15.0, 0.0, 1.0)
	var release: float = float(int(tone.get("release", 0)))
	var attack_time: float = minf(0.4, attack * 0.0125)
	var decay_time: float = minf(0.5, decay * 0.01875)
	var release_time: float = minf(0.5, release * 0.01875)
	var release_start: float = maxf(0.0, 1.0 - release_time)
	if attack_time > 0.0 and progress < attack_time:
		return progress / attack_time
	if decay_time > 0.0 and progress < attack_time + decay_time:
		return lerpf(1.0, sustain, (progress - attack_time) / decay_time)
	if release_time > 0.0 and progress > release_start:
		return sustain * (1.0 - (progress - release_start) / release_time)
	return sustain

func _ticks_to_seconds(ticks: int, tempo_changes: Array = []) -> float:
	if ticks <= 0:
		return 0.0
	var seconds: float = 0.0
	var current_tick: int = 0
	var tempo: float = 150.0
	for change_value in tempo_changes:
		var change: Dictionary = change_value as Dictionary
		var change_tick: int = maxi(int(change.get("tick", 0)), 0)
		if change_tick > ticks:
			break
		if change_tick > current_tick:
			seconds += float(change_tick - current_tick) * 150.0 / (maxf(tempo, 1.0) * M4A_VBLANK_RATE)
			current_tick = change_tick
		tempo = maxf(float(change.get("tempo", tempo)), 1.0)
	if ticks > current_tick:
		seconds += float(ticks - current_tick) * 150.0 / (maxf(tempo, 1.0) * M4A_VBLANK_RATE)
	return seconds

func _clock_value(index: int) -> int:
	return CLOCK_TABLE[clampi(index, 0, CLOCK_TABLE.size() - 1)]

func _signed_byte(value: int) -> int:
	var normalized: int = value & 0xFF
	return normalized - 256 if normalized >= 128 else normalized

func _read_pointer(data: PackedByteArray, offset: int) -> int:
	if not _valid_range(data, offset, 4):
		return -1
	var value: int = _read_u32(data, offset)
	var region: int = value & 0xFF000000
	if region != 0x08000000 and region != 0x09000000 and region != 0x0A000000:
		return -1
	var file_offset: int = value & 0x01FFFFFF
	return file_offset if _valid_range(data, file_offset, 1) else -1

func _read_u16(data: PackedByteArray, offset: int) -> int:
	return int(data[offset]) | (int(data[offset + 1]) << 8)

func _read_u32(data: PackedByteArray, offset: int) -> int:
	return int(data[offset]) | (int(data[offset + 1]) << 8) | (int(data[offset + 2]) << 16) | (int(data[offset + 3]) << 24)

func _valid_range(data: PackedByteArray, offset: int, length: int) -> bool:
	return offset >= 0 and length >= 0 and offset <= data.size() and length <= data.size() - offset
