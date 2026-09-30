extends StaticBody3D

signal health_changed(current_health: float, maximum_health: float)
signal eliminated
signal respawned

@export_range(1.0, 1000.0, 1.0) var maximum_health: float = 100.0
@export_range(0.1, 30.0, 0.1) var respawn_delay: float = 2.0

var current_health: float
var _is_eliminated: bool = false


func _ready() -> void:
	current_health = maximum_health


func take_damage(amount: float, _instigator: Node = null) -> void:
	if _is_eliminated or amount <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, maximum_health)
	if current_health == 0.0:
		_eliminate_and_respawn()


func _eliminate_and_respawn() -> void:
	_is_eliminated = true
	eliminated.emit()
	visible = false
	_set_collision_shapes_disabled(true)
	await get_tree().create_timer(respawn_delay).timeout

	current_health = maximum_health
	visible = true
	_set_collision_shapes_disabled(false)
	_is_eliminated = false
	health_changed.emit(current_health, maximum_health)
	respawned.emit()


func _set_collision_shapes_disabled(disabled: bool) -> void:
	for node in find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", disabled)
