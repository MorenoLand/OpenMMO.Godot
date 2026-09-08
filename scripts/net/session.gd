class_name OpenMMOSession
extends Node

const AES_CTR_SCRIPT = preload("res://scripts/net/aes_ctr.gd")
const CODEC_SCRIPT = preload("res://scripts/net/codec.gd")
const P256_SCRIPT = preload("res://scripts/net/p256.gd")

signal established
signal packet_received(opcode: int, payload: PackedByteArray)
signal connection_changed(connected: bool)
signal failed(message: String)

enum State { DISCONNECTED, CONNECTING, WAITING_SERVER_HELLO, DERIVING_KEYS, ESTABLISHED }

const XOR_KEY_RANDOM: int = 3214621489648854472
const XOR_KEY_TIMESTAMP: int = -4214651440992349575
const CONNECT_TIMEOUT_MSEC: int = 10000

var peer: StreamPeerTCP = StreamPeerTCP.new()
var state: State = State.DISCONNECTED
var root_public_key_path: String = ""
var compressed_inbound: bool = false
var receive_buffer: PackedByteArray = PackedByteArray()
var connect_deadline_msec: int = 0
var derivation_thread: Thread
var pending_checksum_size: int = 0
var outgoing_cipher: RefCounted
var incoming_cipher: RefCounted
var outgoing_checksum_key: PackedByteArray = PackedByteArray()
var incoming_checksum_key: PackedByteArray = PackedByteArray()
var outgoing_round: int = 0
var incoming_round: int = 0
var inflater: StreamPeerGZIP
var inflater_needs_header: bool = true

func connect_openmmo(host: String, port: int, public_key_path: String, use_compression: bool = false) -> Error:
	close()
	if host.strip_edges().is_empty() or port <= 0 or port > 65535 or public_key_path.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	root_public_key_path = public_key_path
	compressed_inbound = use_compression
	peer = StreamPeerTCP.new()
	var error: Error = peer.connect_to_host(host.strip_edges(), port)
	if error != OK:
		return error
	state = State.CONNECTING
	connect_deadline_msec = Time.get_ticks_msec() + CONNECT_TIMEOUT_MSEC
	set_process(true)
	return OK

func send_packet(opcode: int, payload: PackedByteArray = PackedByteArray()) -> bool:
	if state != State.ESTABLISHED:
		return false
	var plain: PackedByteArray = PackedByteArray([opcode & 0xFF])
	plain.append_array(payload)
	var encrypted: PackedByteArray = outgoing_cipher.update(plain)
	var checksum: PackedByteArray = _checksum(encrypted, outgoing_checksum_key, outgoing_round, pending_checksum_size)
	if pending_checksum_size >= 4:
		outgoing_round += 1
	encrypted.append_array(checksum)
	return _write_frame(encrypted)

func close() -> void:
	set_process(false)
	if outgoing_cipher != null:
		outgoing_cipher.finish()
	if incoming_cipher != null:
		incoming_cipher.finish()
	if inflater != null:
		inflater.finish()
	inflater = null
	inflater_needs_header = true
	if peer.get_status() != StreamPeerTCP.STATUS_NONE:
		peer.disconnect_from_host()
	var was_connected: bool = state != State.DISCONNECTED
	state = State.DISCONNECTED
	receive_buffer.clear()
	connect_deadline_msec = 0
	outgoing_round = 0
	incoming_round = 0
	if was_connected:
		connection_changed.emit(false)

func _process(_delta: float) -> void:
	if state == State.DERIVING_KEYS and derivation_thread != null and not derivation_thread.is_alive():
		var result_value: Variant = derivation_thread.wait_to_finish()
		derivation_thread = null
		if result_value is Dictionary:
			_finish_key_derivation(result_value)
		else:
			_fail("OpenMMO P-256 key agreement failed")
		return
	peer.poll()
	var status: StreamPeerTCP.Status = peer.get_status()
	if state == State.CONNECTING:
		if status == StreamPeerTCP.STATUS_CONNECTED:
			peer.set_no_delay(true)
			connection_changed.emit(true)
			if not _write_frame(_client_hello()):
				_fail("OpenMMO ClientHello could not be sent")
				return
			state = State.WAITING_SERVER_HELLO
		elif status == StreamPeerTCP.STATUS_ERROR or Time.get_ticks_msec() >= connect_deadline_msec:
			_fail("OpenMMO TCP connection failed")
			return
	elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_fail("OpenMMO connection closed")
		return
	_read_available()

func _read_available() -> void:
	var available: int = peer.get_available_bytes()
	if available <= 0:
		return
	var result: Array = peer.get_partial_data(available)
	if int(result[0]) != OK:
		_fail("OpenMMO TCP read failed")
		return
	var chunk: PackedByteArray = result[1] as PackedByteArray
	receive_buffer.append_array(chunk)
	while receive_buffer.size() >= 2:
		var frame_length: int = receive_buffer.decode_u16(0)
		if frame_length < 3 or frame_length > 0xFFFF:
			_fail("OpenMMO frame length is invalid")
			return
		if receive_buffer.size() < frame_length:
			return
		var frame: PackedByteArray = receive_buffer.slice(2, frame_length)
		receive_buffer = receive_buffer.slice(frame_length)
		_handle_frame(frame)
		if state == State.DISCONNECTED:
			return

func _handle_frame(frame: PackedByteArray) -> void:
	if state == State.WAITING_SERVER_HELLO:
		_handle_server_hello(frame)
	elif state == State.ESTABLISHED:
		_handle_application_frame(frame)

func _handle_server_hello(frame: PackedByteArray) -> void:
	if frame.is_empty() or frame[0] != 1:
		_fail("Expected OpenMMO ServerHello")
		return
	var reader = CODEC_SCRIPT.Reader.new(frame.slice(1))
	var server_public: PackedByteArray = reader.read_u16_bytes()
	var signature: PackedByteArray = reader.read_u16_bytes()
	var checksum_size: int = reader.read_u8()
	if reader.failed or reader.remaining() != 0 or server_public.size() != 65 or not _valid_checksum_size(checksum_size):
		_fail("OpenMMO ServerHello is malformed")
		return
	var root_public: PackedByteArray = _load_root_public_point()
	var root_public_pem: String = FileAccess.get_file_as_string(root_public_key_path)
	var raw_signature: PackedByteArray = _ecdsa_der_to_raw(signature)
	if root_public.is_empty() or root_public_pem.strip_edges().is_empty() or raw_signature.size() != 64:
		_fail("OpenMMO root public key or server signature is malformed")
		return
	pending_checksum_size = checksum_size
	state = State.DERIVING_KEYS
	derivation_thread = Thread.new()
	var error: Error = derivation_thread.start(Callable(self, "_derive_handshake").bind(server_public, root_public, _sha256(server_public), raw_signature, signature, root_public_pem))
	if error != OK:
		derivation_thread = null
		_fail("OpenMMO P-256 worker could not start")

func _derive_handshake(server_public: PackedByteArray, root_public: PackedByteArray, digest: PackedByteArray, signature: PackedByteArray, signature_der: PackedByteArray, root_public_pem: String) -> Dictionary:
	if not OS.has_feature("web"):
		var native_key := CryptoKey.new()
		if native_key.load_from_string(root_public_pem, true) == OK:
			if not Crypto.new().verify(HashingContext.HASH_SHA256, digest, signature_der, native_key):
				return {"ok": false, "error": "OpenMMO server signature is invalid"}
			return P256_SCRIPT.new().generate_handshake(server_public)
	return P256_SCRIPT.new().generate_verified_handshake(server_public, root_public, digest, signature)

func _finish_key_derivation(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_fail(str(result.get("error", "OpenMMO P-256 key agreement failed")))
		return
	var client_public: PackedByteArray = result.get("public") as PackedByteArray
	var secret: PackedByteArray = result.get("secret") as PackedByteArray
	var ready: PackedByteArray = PackedByteArray([2])
	if not CODEC_SCRIPT.append_u16_bytes(ready, client_public) or not _write_frame(ready):
		_fail("OpenMMO ClientReady could not be sent")
		return
	var client_seed: PackedByteArray = _triple_hash(secret, PackedByteArray([75, 101, 121, 83, 97, 108, 116, 1]))
	var server_seed: PackedByteArray = _triple_hash(secret, PackedByteArray([75, 101, 121, 83, 97, 108, 116, 2]))
	outgoing_cipher = AES_CTR_SCRIPT.new()
	incoming_cipher = AES_CTR_SCRIPT.new()
	if outgoing_cipher.start(client_seed, _triple_hash(client_seed, "IVDERIV".to_ascii_buffer())) != OK or incoming_cipher.start(server_seed, _triple_hash(server_seed, "IVDERIV".to_ascii_buffer())) != OK:
		_fail("OpenMMO AES-CTR initialization failed")
		return
	outgoing_checksum_key = client_seed
	incoming_checksum_key = server_seed
	outgoing_round = 0
	incoming_round = 0
	if compressed_inbound:
		inflater = StreamPeerGZIP.new()
		inflater_needs_header = true
		if inflater.start_decompression(true, 1024 * 1024) != OK:
			_fail("OpenMMO deflate stream could not start")
			return
	state = State.ESTABLISHED
	established.emit()

func _handle_application_frame(frame: PackedByteArray) -> void:
	if frame.size() < pending_checksum_size:
		_fail("OpenMMO frame is shorter than its checksum")
		return
	var payload_size: int = frame.size() - pending_checksum_size
	var encrypted: PackedByteArray = frame.slice(0, payload_size)
	var expected: PackedByteArray = frame.slice(payload_size)
	var actual: PackedByteArray = _checksum(encrypted, incoming_checksum_key, incoming_round, pending_checksum_size)
	if pending_checksum_size >= 4:
		incoming_round += 1
	if not Crypto.new().constant_time_compare(actual, expected):
		_fail("OpenMMO frame checksum mismatch")
		return
	var plain: PackedByteArray = incoming_cipher.update(encrypted)
	if compressed_inbound:
		plain = _decompress_packet(plain)
		if plain.is_empty():
			return
	if plain.is_empty():
		_fail("OpenMMO application frame is empty")
		return
	packet_received.emit(plain[0], plain.slice(1))

func _decompress_packet(packet: PackedByteArray) -> PackedByteArray:
	if packet.size() < 2:
		_fail("OpenMMO compressed frame is malformed")
		return PackedByteArray()
	var output: PackedByteArray = PackedByteArray([packet[0]])
	if packet[1] == 0:
		output.append_array(packet.slice(2))
		return output
	var compressed: PackedByteArray = packet.slice(2)
	if inflater_needs_header:
		compressed = PackedByteArray([0x78, 0x9C]) + compressed
		inflater_needs_header = false
	compressed.append_array(PackedByteArray([0, 0, 0xFF, 0xFF]))
	var input_offset: int = 0
	while input_offset < compressed.size():
		var put_result: Array = inflater.put_partial_data(compressed.slice(input_offset))
		if put_result.size() < 2 or int(put_result[0]) != OK:
			_fail("OpenMMO compressed frame could not be inflated")
			return PackedByteArray()
		var consumed: int = int(put_result[1])
		if consumed <= 0 and inflater.get_available_bytes() <= 0:
			_fail("OpenMMO compressed frame made no progress")
			return PackedByteArray()
		input_offset += consumed
		while inflater.get_available_bytes() > 0:
			var result: Array = inflater.get_partial_data(inflater.get_available_bytes())
			if result.size() < 2 or int(result[0]) != OK:
				_fail("OpenMMO compressed frame read failed")
				return PackedByteArray()
			output.append_array(result[1] as PackedByteArray)
	return output

func _client_hello() -> PackedByteArray:
	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	var random_value: int = random_bytes.decode_s64(0)
	var timestamp: int = Time.get_unix_time_from_system() * 1000
	var payload: PackedByteArray = PackedByteArray([0])
	CODEC_SCRIPT.append_s64_le(payload, random_value ^ XOR_KEY_RANDOM)
	CODEC_SCRIPT.append_s64_le(payload, timestamp ^ XOR_KEY_TIMESTAMP ^ random_value)
	return payload

func _load_root_public_point() -> PackedByteArray:
	var file: FileAccess = FileAccess.open(root_public_key_path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var encoded: String = ""
	for line in file.get_as_text().split("\n"):
		var value: String = line.strip_edges()
		if not value.is_empty() and not value.begins_with("-----"):
			encoded += value
	var der: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if der.size() < 68:
		return PackedByteArray()
	var marker: int = der.size() - 68
	if der[marker] != 0x03 or der[marker + 1] != 0x42 or der[marker + 2] != 0 or der[marker + 3] != 0x04:
		return PackedByteArray()
	return der.slice(der.size() - 65)

func _ecdsa_der_to_raw(value: PackedByteArray) -> PackedByteArray:
	if value.size() < 8 or value[0] != 0x30:
		return PackedByteArray()
	var sequence_length: Dictionary = _der_length(value, 1)
	if not bool(sequence_length.get("ok", false)):
		return PackedByteArray()
	var offset: int = int(sequence_length.get("offset", 0))
	if offset + int(sequence_length.get("length", 0)) != value.size() or offset >= value.size() or value[offset] != 0x02:
		return PackedByteArray()
	var r_length: Dictionary = _der_length(value, offset + 1)
	if not bool(r_length.get("ok", false)):
		return PackedByteArray()
	offset = int(r_length.get("offset", 0))
	var r: PackedByteArray = value.slice(offset, offset + int(r_length.get("length", 0)))
	offset += r.size()
	if offset >= value.size() or value[offset] != 0x02:
		return PackedByteArray()
	var s_length: Dictionary = _der_length(value, offset + 1)
	if not bool(s_length.get("ok", false)):
		return PackedByteArray()
	offset = int(s_length.get("offset", 0))
	var s: PackedByteArray = value.slice(offset, offset + int(s_length.get("length", 0)))
	if offset + s.size() != value.size():
		return PackedByteArray()
	var raw: PackedByteArray = _pad_integer(r)
	raw.append_array(_pad_integer(s))
	return raw if raw.size() == 64 else PackedByteArray()

func _der_length(data: PackedByteArray, offset: int) -> Dictionary:
	if offset >= data.size():
		return {"ok": false}
	var first: int = data[offset]
	if first < 0x80:
		return {"ok": true, "length": first, "offset": offset + 1}
	var count: int = first & 0x7F
	if count <= 0 or count > 2 or offset + 1 + count > data.size():
		return {"ok": false}
	var length: int = 0
	for index in count:
		length = length << 8 | data[offset + 1 + index]
	return {"ok": true, "length": length, "offset": offset + 1 + count}

func _pad_integer(value: PackedByteArray) -> PackedByteArray:
	var normalized: PackedByteArray = value
	while normalized.size() > 32 and normalized[0] == 0:
		normalized = normalized.slice(1)
	if normalized.size() > 32:
		return PackedByteArray()
	var output: PackedByteArray = PackedByteArray()
	output.resize(32 - normalized.size())
	output.append_array(normalized)
	return output

func _triple_hash(secret: PackedByteArray, salt: PackedByteArray) -> PackedByteArray:
	var input: PackedByteArray = salt.duplicate()
	input.append_array(secret)
	input.append_array(salt)
	return _sha256(input).slice(0, 16)

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(data) != OK:
		return PackedByteArray()
	return context.finish()

func _checksum(data: PackedByteArray, key: PackedByteArray, round_value: int, size: int) -> PackedByteArray:
	if size == 0:
		return PackedByteArray()
	if size == 2:
		var value: int = _crc16(data)
		return PackedByteArray([value & 0xFF, value >> 8 & 0xFF])
	var message: PackedByteArray = data.duplicate()
	message.append_array(PackedByteArray([round_value >> 24 & 0xFF, round_value >> 16 & 0xFF, round_value >> 8 & 0xFF, round_value & 0xFF]))
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, message).slice(0, size)

func _crc16(data: PackedByteArray) -> int:
	var sum: int = 0
	for value in data:
		sum ^= value
		for _bit_index in 8:
			sum = sum >> 1 ^ 0xA001 if sum & 1 else sum >> 1
	return sum & 0xFFFF

func _valid_checksum_size(value: int) -> bool:
	return value == 0 or value == 2 or value >= 4 and value <= 32

func _write_frame(payload: PackedByteArray) -> bool:
	var frame: PackedByteArray = CODEC_SCRIPT.frame(payload)
	return not frame.is_empty() and peer.put_data(frame) == OK

func _fail(message: String) -> void:
	close()
	failed.emit(message)

func _exit_tree() -> void:
	close()
	if derivation_thread != null:
		derivation_thread.wait_to_finish()
