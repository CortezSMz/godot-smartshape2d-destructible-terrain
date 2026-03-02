extends DestructibleSmartShape

## Quick demo. Left-click to carve, right-click to add, Space to spawn rigidbodies.

@export var carve_radius: int = 15
@export var carve_segments: int = 16
@export var min_movement_update: int = 5

var _mouse_pos := Vector2()
var _old_mouse_pos := Vector2()
var _carve_circle := PackedVector2Array()
var _touches: Dictionary = {}
var _touch_action_done := false

@onready var _carve_visualizer: Polygon2D = $CarveVisualizer

var Rigid = preload("res://RigidBody.tscn")


func _ready() -> void:
	_build_carve_circle()
	if _carve_visualizer:
		_carve_visualizer.polygon = _carve_circle


func _process(_delta: float) -> void:
	var moved := _old_mouse_pos.distance_to(_mouse_pos) > min_movement_update

	if Input.is_action_pressed("click_left") and moved:
		_do_carve()
		_old_mouse_pos = _mouse_pos

	if Input.is_action_pressed("click_right") and moved:
		_do_add()
		_old_mouse_pos = _mouse_pos

	if Input.is_action_pressed("ui_accept"):
		_spawn_rigid_body()

	# Touch: 1 finger = carve, 2 = add, 3 = spawn
	if _touches.size() > 0:
		var tp := _get_touch_center()
		var tm := _old_mouse_pos.distance_to(tp) > min_movement_update
		match _touches.size():
			1:
				if tm:
					_mouse_pos = tp
					_do_carve()
					_old_mouse_pos = tp
			2:
				if tm:
					_mouse_pos = tp
					_do_add()
					_old_mouse_pos = tp
			3:
				if not _touch_action_done:
					_mouse_pos = tp
					_spawn_rigid_body()
					_touch_action_done = true
		if _carve_visualizer:
			_carve_visualizer.global_position = tp


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = get_global_mouse_position()
		if _carve_visualizer:
			_carve_visualizer.global_position = _mouse_pos
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_touch_action_done = false
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_touch_action_done = false
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position


func _get_touch_center() -> Vector2:
	var sum := Vector2.ZERO
	for pos in _touches.values():
		sum += pos
	return get_canvas_transform().affine_inverse() * (sum / _touches.size())


func _build_carve_circle() -> void:
	_carve_circle = PackedVector2Array()
	for i in range(carve_segments):
		var angle : Variant = lerp(-PI, PI, float(i) / carve_segments)
		_carve_circle.append(Vector2(cos(angle), sin(angle)) * carve_radius)


func _do_carve() -> void:
	var poly := PackedVector2Array()
	for point in _carve_circle:
		poly.append(point + _mouse_pos)
	carve(poly)


func _do_add() -> void:
	var poly := PackedVector2Array()
	for point in _carve_circle:
		poly.append(point + _mouse_pos)
	add(poly)


func _spawn_rigid_body() -> void:
	if Rigid:
		var rb = Rigid.instantiate()
		rb.position = get_global_mouse_position() + Vector2(randi() % 10, 0)
		$RigidBodies.add_child(rb)
