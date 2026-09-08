class_name OpenMMOAudio
extends Node

const ROM_AUDIO_SCRIPT = preload("res://scripts/world/rom_audio.gd")
const MUSIC_SAMPLE_RATE: int = ROM_AUDIO_SCRIPT.SAMPLE_RATE
const MUSIC_BUFFER_LENGTH: float = 2.0
const MUSIC_RENDER_CHUNK_FRAMES: int = 2048
const WEB_RENDER_CHUNK_FRAMES: int = 512
const MUSIC_PREBUFFER_FRAMES: int = 16384
const MUSIC_CACHE_LIMIT: int = 4
const MUSIC_RENDER_WAIT_MSEC: int = 4
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var rom_audio
var current_music_key: String = ""
var current_content_id: String = ""
var music_render_thread: Thread
var music_render_mutex: Mutex = Mutex.new()
var music_render_generation: int = 0
var rendering_music_key: String = ""
var requested_music_key: String = ""
var requested_music_content
var requested_music_id: int = -1
var requested_music_generation: int = 0
var rendered_chunks: Array = []
var render_complete: bool = false
var render_error: String = ""
var music_render_target_frames: int = 0
var music_rendered_frames: int = 0
var music_render_total_frames: int = 0
var playback_chunks: Array = []
var playback_source_complete: bool = false
var playback_chunk_index: int = 0
var playback_chunk_offset: int = 0
var playback_pushed_frames: int = 0
var music_generator: AudioStreamGenerator
var music_playback: AudioStreamGeneratorPlayback
var queued_music_key: String = ""
var music_start_generation: int = 0
var cooperative_prepared: Dictionary = {}
var cooperative_frame: int = 0
var music_cache: Dictionary = {}
var music_cache_order: Array[String] = []
var battle_music_active: bool = false
var map_music_content: OpenMMOContent
var map_music_id: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rom_audio = ROM_AUDIO_SCRIPT.new()
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -14.0
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.volume_db = -6.0
	add_child(sfx_player)
	set_process(true)

func _exit_tree() -> void:
	music_start_generation += 1
	music_render_mutex.lock()
	music_render_generation += 1
	music_render_mutex.unlock()
	if music_render_thread != null and music_render_thread.is_started():
		music_render_thread.wait_to_finish()

func play_map_music(content, map_id: String) -> void:
	map_music_content = content
	map_music_id = map_id
	if battle_music_active:
		return
	if content == null or map_id.is_empty() or music_player == null:
		return
	var map: Dictionary = content.map_data(map_id)
	if map.is_empty():
		return
	var music_id: int = int(map.get("music_id", 0))
	play_song(content, music_id)

func play_battle_music(content: OpenMMOContent, trainer: bool) -> void:
	if content == null:
		return
	var songs: Dictionary = content.source_profile.get("battle_music", {})
	var song_id: int = int(songs.get("trainer" if trainer else "wild", -1))
	if song_id < 0:
		return
	battle_music_active = true
	play_song(content, song_id)

func restore_map_music() -> void:
	battle_music_active = false
	play_map_music(map_music_content, map_music_id)

func play_victory_music(content: OpenMMOContent, state: Dictionary) -> void:
	if content == null or not battle_music_active:
		return
	var opponents: Array = state.get("opponent_party", [])
	if opponents.is_empty():
		return
	for mon in opponents:
		if not mon is Dictionary or int(mon.get("current_hp", -1)) != 0:
			return
	var songs: Dictionary = content.source_profile.get("battle_music", {})
	var song_id: int = int(songs.get("victory_trainer" if bool(state.get("trainer", false)) else "victory_wild", -1))
	if song_id >= 0:
		play_song(content, song_id)

func play_song(content: OpenMMOContent, music_id: int) -> void:
	if content == null or music_player == null:
		return
	var fingerprint: String = content.rom_sha1 if not content.rom_sha1.is_empty() else str(content.rom_data.size())
	var key: String = "%s:%s:%d" % [content.content_id(), fingerprint, music_id]
	if key == current_music_key and (music_player.playing or rendering_music_key == key or requested_music_key == key or queued_music_key == key):
		return
	_cancel_current_music()
	current_music_key = key
	current_content_id = content.content_id()
	var cached: Variant = music_cache.get(key)
	if cached is Array:
		playback_chunks = (cached as Array).duplicate()
		playback_source_complete = true
		_maybe_queue_music_start()
		return
	requested_music_key = key
	requested_music_content = content
	requested_music_id = music_id
	requested_music_generation = music_render_generation
	if OS.has_feature("web"):
		_begin_requested_cooperative_render()
	else:
		_start_music_render_if_idle()

func _process(_delta: float) -> void:
	_poll_music_render_thread()
	if not cooperative_prepared.is_empty():
		_advance_cooperative_render()
	elif not OS.has_feature("web"):
		_start_music_render_if_idle()
	_sync_rendered_chunks()
	_maybe_queue_music_start()
	_pump_music_buffer()
	_update_music_render_target()

func _cancel_current_music() -> void:
	music_start_generation += 1
	music_render_mutex.lock()
	music_render_generation += 1
	music_render_mutex.unlock()
	requested_music_key = ""
	requested_music_content = null
	requested_music_id = -1
	queued_music_key = ""
	playback_chunks = []
	playback_source_complete = false
	playback_chunk_index = 0
	playback_chunk_offset = 0
	playback_pushed_frames = 0
	music_playback = null
	music_generator = null
	cooperative_prepared = {}
	cooperative_frame = 0
	if music_player != null:
		music_player.stop()

func _begin_render_state(key: String) -> void:
	rendering_music_key = key
	playback_chunks = []
	playback_source_complete = false
	playback_chunk_index = 0
	playback_chunk_offset = 0
	playback_pushed_frames = 0
	music_render_mutex.lock()
	rendered_chunks = []
	render_complete = false
	render_error = ""
	music_render_target_frames = MUSIC_PREBUFFER_FRAMES
	music_rendered_frames = 0
	music_render_total_frames = 0
	music_render_mutex.unlock()

func _start_music_render_if_idle() -> void:
	if requested_music_key.is_empty() or requested_music_content == null or requested_music_id < 0:
		return
	if music_render_thread != null and music_render_thread.is_started():
		return
	var key: String = requested_music_key
	var content = requested_music_content
	var song_id: int = requested_music_id
	var generation: int = requested_music_generation
	requested_music_key = ""
	requested_music_content = null
	requested_music_id = -1
	_begin_render_state(key)
	music_render_thread = Thread.new()
	var start_error: Error = music_render_thread.start(Callable(self, "_render_music_worker").bind(content, song_id, key, generation), Thread.PRIORITY_LOW)
	if start_error != OK:
		music_render_thread = null
		rendering_music_key = ""
		requested_music_key = key
		requested_music_content = content
		requested_music_id = song_id
		requested_music_generation = generation
		_begin_requested_cooperative_render()

func _render_music_worker(content, song_id: int, key: String, generation: int) -> Dictionary:
	var decoder = ROM_AUDIO_SCRIPT.new()
	var prepared: Dictionary = decoder.prepare_song(content, song_id)
	if prepared.is_empty():
		music_render_mutex.lock()
		render_error = decoder.last_error
		music_render_mutex.unlock()
		return {"ok": false, "key": key, "generation": generation}
	var total_frames: int = int(prepared.get("loop_frames", prepared.get("duration_frames", 0)))
	music_render_mutex.lock()
	music_render_total_frames = total_frames
	music_render_target_frames = mini(music_render_target_frames, total_frames)
	music_render_mutex.unlock()
	var frame: int = 0
	while frame < total_frames:
		music_render_mutex.lock()
		var cancelled: bool = generation != music_render_generation
		var target_frames: int = music_render_target_frames
		music_render_mutex.unlock()
		if cancelled:
			return {"ok": false, "key": key, "generation": generation, "cancelled": true}
		if frame >= target_frames:
			OS.delay_msec(MUSIC_RENDER_WAIT_MSEC)
			continue
		var chunk_frames: int = mini(MUSIC_RENDER_CHUNK_FRAMES, mini(total_frames - frame, target_frames - frame))
		var chunk: PackedVector2Array = decoder.render_song_frames(prepared, frame, chunk_frames)
		if chunk.size() != chunk_frames:
			return {"ok": false, "key": key, "generation": generation}
		music_render_mutex.lock()
		rendered_chunks.append(chunk)
		music_rendered_frames = frame + chunk_frames
		music_render_mutex.unlock()
		frame += chunk_frames
	music_render_mutex.lock()
	render_complete = true
	music_render_mutex.unlock()
	return {"ok": true, "key": key, "generation": generation}

func _poll_music_render_thread() -> void:
	if music_render_thread == null or not music_render_thread.is_started() or music_render_thread.is_alive():
		return
	var result_value: Variant = music_render_thread.wait_to_finish()
	music_render_thread = null
	music_render_mutex.lock()
	var generation: int = music_render_generation
	music_render_mutex.unlock()
	if result_value is Dictionary:
		var result: Dictionary = result_value as Dictionary
		if bool(result.get("ok", false)) and int(result.get("generation", -1)) == generation:
			_sync_rendered_chunks()
			playback_source_complete = true
			_cache_music_chunks(str(result.get("key", "")), playback_chunks)
		elif int(result.get("generation", -1)) == generation:
			rendering_music_key = ""
	if not requested_music_key.is_empty():
		_start_music_render_if_idle()

func _begin_requested_cooperative_render() -> void:
	if requested_music_key.is_empty() or requested_music_content == null or requested_music_id < 0:
		return
	var key: String = requested_music_key
	var content = requested_music_content
	var song_id: int = requested_music_id
	requested_music_key = ""
	requested_music_content = null
	requested_music_id = -1
	var prepared: Dictionary = rom_audio.prepare_song(content, song_id)
	if prepared.is_empty():
		render_error = rom_audio.last_error
		rendering_music_key = ""
		return
	_begin_render_state(key)
	cooperative_prepared = prepared
	cooperative_frame = 0
	var total_frames: int = int(prepared.get("loop_frames", prepared.get("duration_frames", 0)))
	music_render_mutex.lock()
	music_render_total_frames = total_frames
	music_render_target_frames = mini(music_render_target_frames, total_frames)
	music_render_mutex.unlock()

func _advance_cooperative_render() -> void:
	if cooperative_prepared.is_empty() or rendering_music_key != current_music_key:
		return
	var total_frames: int = int(cooperative_prepared.get("loop_frames", cooperative_prepared.get("duration_frames", 0)))
	if cooperative_frame >= total_frames:
		cooperative_prepared = {}
		playback_source_complete = true
		_cache_music_chunks(rendering_music_key, playback_chunks)
		return
	music_render_mutex.lock()
	var target_frames: int = music_render_target_frames
	music_render_mutex.unlock()
	if cooperative_frame >= target_frames:
		return
	var chunk_frames: int = mini(WEB_RENDER_CHUNK_FRAMES, mini(total_frames - cooperative_frame, target_frames - cooperative_frame))
	var chunk: PackedVector2Array = rom_audio.render_song_frames(cooperative_prepared, cooperative_frame, chunk_frames)
	if chunk.size() != chunk_frames:
		cooperative_prepared = {}
		render_error = "ROM audio renderer produced an incomplete chunk"
		rendering_music_key = ""
		return
	music_render_mutex.lock()
	rendered_chunks.append(chunk)
	music_rendered_frames = cooperative_frame + chunk_frames
	music_render_mutex.unlock()
	cooperative_frame += chunk_frames
	if cooperative_frame >= total_frames:
		music_render_mutex.lock()
		render_complete = true
		music_render_mutex.unlock()

func _sync_rendered_chunks() -> void:
	if rendering_music_key != current_music_key:
		return
	music_render_mutex.lock()
	var available_count: int = rendered_chunks.size()
	while playback_chunks.size() < available_count:
		playback_chunks.append(rendered_chunks[playback_chunks.size()])
	var completed: bool = render_complete
	music_render_mutex.unlock()
	if completed:
		playback_source_complete = true

func _maybe_queue_music_start() -> void:
	if current_music_key.is_empty() or music_player.playing or not queued_music_key.is_empty() or playback_chunks.is_empty():
		return
	if _prebuffered_frame_count() < MUSIC_PREBUFFER_FRAMES and not playback_source_complete:
		return
	queued_music_key = current_music_key
	var generation: int = music_start_generation
	_start_music_after_presented_frame(current_music_key, generation)

func _prebuffered_frame_count() -> int:
	var frame_count: int = 0
	for chunk_value in playback_chunks:
		var chunk: PackedVector2Array = chunk_value as PackedVector2Array
		frame_count += chunk.size()
	return frame_count

func _update_music_render_target() -> void:
	if current_music_key.is_empty() or playback_source_complete:
		return
	var desired_frames: int = MUSIC_PREBUFFER_FRAMES
	if music_playback != null and music_player.playing:
		desired_frames = playback_pushed_frames + music_playback.get_frames_available() + MUSIC_RENDER_CHUNK_FRAMES
	music_render_mutex.lock()
	if music_render_total_frames > 0:
		desired_frames = mini(desired_frames, music_render_total_frames)
	music_render_target_frames = maxi(music_render_target_frames, desired_frames)
	music_render_mutex.unlock()

func _start_music_after_presented_frame(key: String, generation: int) -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	if generation != music_start_generation or key != current_music_key or playback_chunks.is_empty():
		return
	queued_music_key = ""
	music_generator = AudioStreamGenerator.new()
	music_generator.mix_rate = MUSIC_SAMPLE_RATE
	music_generator.buffer_length = MUSIC_BUFFER_LENGTH
	music_player.stream = music_generator
	music_player.play()
	music_playback = music_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_pump_music_buffer()

func _pump_music_buffer() -> void:
	if music_playback == null or not music_player.playing or playback_chunks.is_empty():
		return
	var available: int = music_playback.get_frames_available()
	while available > 0:
		if playback_chunk_index >= playback_chunks.size():
			if playback_source_complete:
				playback_chunk_index = 0
				playback_chunk_offset = 0
			else:
				break
		var chunk: PackedVector2Array = playback_chunks[playback_chunk_index] as PackedVector2Array
		if chunk.is_empty():
			playback_chunk_index += 1
			playback_chunk_offset = 0
			continue
		var remaining: int = chunk.size() - playback_chunk_offset
		if remaining <= 0:
			playback_chunk_index += 1
			playback_chunk_offset = 0
			continue
		var pushed: int = mini(available, remaining)
		if pushed <= 0:
			break
		music_playback.push_buffer(chunk.slice(playback_chunk_offset, playback_chunk_offset + pushed))
		playback_chunk_offset += pushed
		playback_pushed_frames += pushed
		if playback_chunk_offset >= chunk.size():
			playback_chunk_index += 1
			playback_chunk_offset = 0
		available = music_playback.get_frames_available()

func _cache_music_chunks(key: String, chunks: Array) -> void:
	if key.is_empty() or chunks.is_empty():
		return
	music_cache[key] = chunks.duplicate()
	music_cache_order.erase(key)
	music_cache_order.append(key)
	while music_cache_order.size() > MUSIC_CACHE_LIMIT:
		music_cache.erase(music_cache_order.pop_front())

func stop_music() -> void:
	_cancel_current_music()
	current_music_key = ""
	current_content_id = ""

func play_effect(effect: String) -> void:
	if sfx_player == null or effect.is_empty():
		return
	var song_id: int = _effect_song_id(effect)
	if song_id < 0 or GameState.content == null:
		return
	var stream: AudioStream = rom_audio.build_song_stream(GameState.content, song_id)
	if stream == null:
		return
	sfx_player.stream = stream
	sfx_player.play()

func _effect_song_id(effect: String) -> int:
	match effect:
		"door":
			return 241
		"dialogue":
			return 30
		"ledge":
			return 10
		"warp":
			return 39
		"step":
			return -1
	return -1
