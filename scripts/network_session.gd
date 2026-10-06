extends Node3D
class_name NetworkSession

@export_range(1024, 65535, 1) var port: int = 7000
@export_range(1, 8, 1) var max_remote_players: int = 1

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const MAIN_MENU_SCENE_PATH := "res://scenes/menu/main_menu.tscn"

var _started := false
var _is_client_session := false
var _local_peer_id := 0
var _player_ids: Array[int] = []
var _next_allowed_shot_time: Dictionary = {}


func is_networked() -> bool:
	return _started


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	call_deferred("_start_pending_session")


func _start_pending_session() -> void:
	var requested_mode := GameSettings.pending_session_mode
	var requested_address := GameSettings.pending_server_address
	GameSettings.pending_session_mode = &""
	GameSettings.pending_server_address = ""
	if requested_mode == &"":
		return

	var started := false
	if requested_mode == &"host":
		started = start_host_session()
	elif requested_mode == &"client":
		started = start_client_session(requested_address)
	if not started:
		_return_to_menu("Não foi possível iniciar a sessão de rede. Confira a porta e o endereço informados.")


func start_host_session() -> bool:
	if _started:
		return false
	var host_player := get_node_or_null("Player") as CharacterBody3D
	if host_player == null:
		push_error("Arena needs its existing Player instance to host a session.")
		return false

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_remote_players)
	if error != OK:
		push_error("Could not host multiplayer session. Error: %s" % error)
		return false

	multiplayer.multiplayer_peer = peer
	_started = true
	_is_client_session = false
	_local_peer_id = 1
	_player_ids = [1]

	host_player.name = "Player_1"
	_configure_player(host_player, 1)
	_place_player_at_spawn(host_player, 0)
	_spawn_player.rpc(1, 0)
	print("Hosting on UDP port %d." % port)
	return true


func start_client_session(address: String) -> bool:
	if _started or address.strip_edges().is_empty():
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		push_error("Could not connect to %s:%d. Error: %s" % [address, port, error])
		return false

	multiplayer.multiplayer_peer = peer
	_started = true
	_is_client_session = true
	_local_peer_id = 0
	print("Connecting to %s:%d..." % [address, port])
	return true


func _on_connected_to_server() -> void:
	GameSettings.last_network_message = ""
	_local_peer_id = multiplayer.get_unique_id()
	var local_player := get_node_or_null("Player") as CharacterBody3D
	if local_player != null:
		local_player.name = _player_node_name(_local_peer_id)
		_configure_player(local_player, _local_peer_id)
		# This prototype has one remote slot, which uses the second spawn marker.
		_place_player_at_spawn(local_player, 1)
	if not _player_ids.has(_local_peer_id):
		_player_ids.append(_local_peer_id)
	_spawn_player(_local_peer_id, 1)
	print("Connected to host as peer %d." % _local_peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not _player_ids.has(peer_id):
		_player_ids.append(peer_id)
	# Send the full current player list so a newly joined peer can build the same arena.
	for spawn_index in range(_player_ids.size()):
		_spawn_player.rpc(_player_ids[spawn_index], spawn_index)
	print("Peer %d connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_player_ids.erase(peer_id)
	_despawn_player.rpc(peer_id)
	print("Peer %d disconnected." % peer_id)


func _on_connection_failed() -> void:
	_return_to_menu("Falha ao conectar. Confira o IP, a rede local e a liberação de UDP 7000 no firewall do host.")
	_reset_network_peer()


func _on_server_disconnected() -> void:
	_return_to_menu("A conexão com o host foi encerrada.")
	_reset_network_peer()


func _return_to_menu(message: String) -> void:
	GameSettings.last_network_message = message
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _reset_network_peer() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_started = false
	_is_client_session = false
	_player_ids.clear()


@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, spawn_index: int) -> void:
	var node_name := _player_node_name(peer_id)
	if get_node_or_null(node_name) != null:
		return
	# The client ID is assigned asynchronously; wait for it before spawning peers above ID 1.
	if _is_client_session and _local_peer_id == 0 and peer_id != 1:
		return

	# On a joining client, reuse the arena's pre-placed Player as its local player.
	if _is_client_session and _local_peer_id != 0 and peer_id == _local_peer_id:
		var bootstrap_player := get_node_or_null("Player") as CharacterBody3D
		if bootstrap_player != null:
			bootstrap_player.name = node_name
			_configure_player(bootstrap_player, peer_id)
			_place_player_at_spawn(bootstrap_player, spawn_index)
			return

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	if player == null:
		push_error("The player scene root must be a CharacterBody3D.")
		return
	player.name = node_name
	_configure_player(player, peer_id)
	add_child(player)
	_place_player_at_spawn(player, spawn_index)


@rpc("authority", "call_local", "reliable")
func _despawn_player(peer_id: int) -> void:
	var player := get_node_or_null(_player_node_name(peer_id))
	if player != null:
		player.queue_free()


func _configure_player(player: CharacterBody3D, peer_id: int) -> void:
	player.set_multiplayer_authority(peer_id, true)
	if player.is_inside_tree() and player.has_method("refresh_multiplayer_role"):
		player.call("refresh_multiplayer_role")

	if player.has_node("NetworkSynchronizer"):
		return

	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "NetworkSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.set_multiplayer_authority(peer_id, true)
	var replication := SceneReplicationConfig.new()
	var position_path := NodePath(".:position")
	var rotation_path := NodePath(".:rotation")
	var animation_path := NodePath(".:replicated_animation_state")
	var camera_pitch_path := NodePath(".:replicated_camera_pitch")
	var weapon_index_path := NodePath(".:replicated_weapon_index")
	for property_path in [position_path, rotation_path]:
		replication.add_property(property_path)
		replication.property_set_replication_mode(
			property_path,
			SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)
	replication.add_property(animation_path)
	replication.property_set_replication_mode(
		animation_path,
		SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	)
	for property_path in [camera_pitch_path, weapon_index_path]:
		replication.add_property(property_path)
		replication.property_set_replication_mode(
			property_path,
			SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
		)
	synchronizer.replication_config = replication
	player.add_child(synchronizer)


func process_local_shot(weapon_index: int) -> void:
	if multiplayer.is_server():
		_process_authoritative_shot(1, weapon_index)


@rpc("any_peer", "call_remote", "reliable")
func request_shot(weapon_index: int) -> void:
	if not multiplayer.is_server():
		return
	_process_authoritative_shot(multiplayer.get_remote_sender_id(), weapon_index)


func _process_authoritative_shot(shooter_peer_id: int, weapon_index: int) -> void:
	var shooter := get_node_or_null(_player_node_name(shooter_peer_id)) as CharacterBody3D
	if shooter == null or shooter.get_multiplayer_authority() != shooter_peer_id:
		return

	var weapon_controller := shooter.get_node_or_null("WeaponController") as WeaponController
	if weapon_controller == null:
		return
	var definition := weapon_controller.get_weapon_definition_for_index(weapon_index)
	if definition == null:
		return

	var cooldown_key := "%d:%d" % [shooter_peer_id, weapon_index]
	var now_seconds := float(Time.get_ticks_msec()) / 1000.0
	if now_seconds < float(_next_allowed_shot_time.get(cooldown_key, 0.0)):
		return
	_next_allowed_shot_time[cooldown_key] = now_seconds + 60.0 / maxf(definition.rounds_per_minute, 1.0)

	var shot_trace := weapon_controller.trace_shot(definition)
	var result: Dictionary = shot_trace.get("hit", {})
	if result.is_empty():
		return

	var hit_position: Vector3 = result["position"]
	var surface_normal: Vector3 = result["normal"]
	_show_network_impact.rpc(shooter_peer_id, hit_position, surface_normal)
	var target := _find_damage_receiver(result["collider"])
	if target != null:
		_apply_network_damage.rpc(target.get_path(), definition.damage, shooter_peer_id)


@rpc("authority", "call_local", "unreliable")
func _show_network_impact(shooter_peer_id: int, hit_position: Vector3, surface_normal: Vector3) -> void:
	var shooter := get_node_or_null(_player_node_name(shooter_peer_id))
	if shooter == null:
		return
	var weapon_controller := shooter.get_node_or_null("WeaponController")
	if weapon_controller != null and weapon_controller.has_method("spawn_network_impact"):
		weapon_controller.call("spawn_network_impact", hit_position, surface_normal)


@rpc("authority", "call_local", "reliable")
func _apply_network_damage(target_path: NodePath, amount: float, shooter_peer_id: int) -> void:
	var target := get_node_or_null(target_path)
	if target == null or not target.has_method("take_damage"):
		return
	var shooter := get_node_or_null(_player_node_name(shooter_peer_id))
	target.call("take_damage", amount, shooter)


func _find_damage_receiver(hit_object: Object) -> Node:
	var candidate := hit_object as Node
	while candidate != null:
		if candidate.has_method("take_damage"):
			return candidate
		candidate = candidate.get_parent()
	return null


func _player_node_name(peer_id: int) -> String:
	return "Player_%d" % peer_id


func _place_player_at_spawn(player: CharacterBody3D, spawn_index: int) -> void:
	var spawn_marker := _get_spawn_marker(spawn_index)
	var opponent_marker := _get_spawn_marker(spawn_index ^ 1)
	if spawn_marker == null or opponent_marker == null:
		push_error("Arena needs a unique SpawnPoint%d Marker3D for this player." % (spawn_index + 1))
		return

	var facing_target := opponent_marker.global_position
	facing_target.y = spawn_marker.global_position.y
	var spawn_transform := Transform3D(Basis.IDENTITY, spawn_marker.global_position)
	player.global_transform = spawn_transform
	player.look_at(facing_target, Vector3.UP)
	if player.has_method("set_spawn_transform"):
		player.call("set_spawn_transform", player.global_transform)


func _get_spawn_marker(spawn_index: int) -> Marker3D:
	if spawn_index < 0:
		return null
	return get_node_or_null("SpawnPoint%d" % (spawn_index + 1)) as Marker3D
