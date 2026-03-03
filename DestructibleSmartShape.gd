extends Node2D
class_name DestructibleSmartShape

## Manages destructible SS2D_Shape terrain.
## Call carve() to subtract and add() to merge polygons.

## Discard fragments smaller than this.
@export var min_fragment_area: float = 100.0

## If true, hole slits try to find the nearest boundary.
## If false, they just go straight down.
@export var smart_slit_routing: bool = true

## Constrains the slit search direction. Uses SS2D_NormalRange
## so you get a visual angle editor in the inspector.
@export var slit_angle_range: SS2D_NormalRange = SS2D_NormalRange.new(225.0, 90.0)


# -- Public API ----------------------------------------------------------------

func carve(carve_polygon: PackedVector2Array) -> void:
	var local_carve := _to_local_polygon(carve_polygon)
	for shape in _get_all_shapes():
		_carve_shape(shape, local_carve)


func add(add_polygon: PackedVector2Array) -> void:
	var local_add := _to_local_polygon(add_polygon)

	# Keep merging with every shape that overlaps.
	# We restart the loop each time because the unified polygon
	# might have grown enough to touch a new shape.
	var unified := local_add
	var consumed_shapes: Array[SS2D_Shape] = []

	var changed := true
	while changed:
		changed = false
		for shape in _get_all_shapes():
			if consumed_shapes.has(shape):
				continue
			var pa := shape.get_point_array()
			if pa.get_point_count() < 3:
				continue
			var verts := _clean_polygon(pa.get_tessellated_points())
			var local_verts := _transform_polygon(verts, shape.transform)

			var intersections := Geometry2D.intersect_polygons(local_verts, unified)
			if intersections.is_empty():
				continue

			var merged := Geometry2D.merge_polygons(unified, local_verts)
			if not merged.is_empty():
				for poly in merged:
					if not Geometry2D.is_polygon_clockwise(poly):
						unified = poly
						break
			consumed_shapes.append(shape)
			changed = true

	if consumed_shapes.is_empty():
		_create_standalone_shape(unified)
		return

	# Keep the first shape, update its points, remove the rest.
	var keeper := consumed_shapes[0]
	var inv_xform := keeper.transform.affine_inverse()
	_update_shape_points(keeper, _transform_polygon(unified, inv_xform))

	for i in range(1, consumed_shapes.size()):
		_remove_shape(consumed_shapes[i])


# -- Carving -------------------------------------------------------------------

func _carve_shape(shape: SS2D_Shape, carve_polygon: PackedVector2Array) -> void:
	var points := shape.get_point_array()
	if points.get_point_count() < 3:
		return

	var vertices := _clean_polygon(points.get_tessellated_points())
	var shape_xform := shape.transform
	var local_vertices := PackedVector2Array()
	for v in vertices:
		local_vertices.append(shape_xform * v)

	var clipped_polygons := Geometry2D.clip_polygons(local_vertices, carve_polygon)

	if clipped_polygons.is_empty():
		_remove_shape(shape)
		return

	var valid_polygons: Array[PackedVector2Array] = []

	# If clip_polygons gave us 2 results and one is CW, that's a hole.
	if clipped_polygons.size() == 2 and _is_hole(clipped_polygons):
		valid_polygons = _resolve_hole(local_vertices, carve_polygon)
	else:
		for poly in clipped_polygons:
			if not Geometry2D.is_polygon_clockwise(poly):
				valid_polygons.append(poly)

	# Drop tiny fragments.
	var filtered: Array[PackedVector2Array] = []
	for poly in valid_polygons:
		if _polygon_area(poly) >= min_fragment_area:
			filtered.append(poly)
	valid_polygons = filtered

	if valid_polygons.is_empty():
		_remove_shape(shape)
		return

	var inv_xform := shape_xform.affine_inverse()

	# First polygon updates the existing shape, the rest become new fragments.
	_update_shape_points(shape, _transform_polygon(valid_polygons[0], inv_xform))
	for i in range(1, valid_polygons.size()):
		_create_fragment_shape(shape, _transform_polygon(valid_polygons[i], inv_xform))


# -- Hole resolution -----------------------------------------------------------

func _is_hole(clipped_polygons: Array) -> bool:
	return (Geometry2D.is_polygon_clockwise(clipped_polygons[0])
		or Geometry2D.is_polygon_clockwise(clipped_polygons[1]))


func _resolve_hole(
	shape_polygon: PackedVector2Array,
	carve_polygon: PackedVector2Array
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	var carve_center := _avg_position(carve_polygon)
	var dir: Vector2
	var target: Vector2

	if smart_slit_routing:
		target = _find_best_slit_target(carve_center, carve_polygon, shape_polygon)
		dir = (target - carve_center).normalized()
	else:
		dir = Vector2.DOWN
		var shape_bottom := -INF
		for p in shape_polygon:
			if p.y > shape_bottom:
				shape_bottom = p.y
		target = Vector2(carve_center.x, shape_bottom + 2)

	var perp := Vector2(-dir.y, dir.x)

	# Thin rectangle from carve center past the target.
	var slit_width := 0.1
	var slit_start := carve_center
	var slit_end := target + dir * 2.0
	var slit := PackedVector2Array([
		slit_start + perp * slit_width,
		slit_end + perp * slit_width,
		slit_end - perp * slit_width,
		slit_start - perp * slit_width,
	])

	# Merge carve + slit, then clip. Result is a single polygon, no hole.
	var merged := Geometry2D.merge_polygons(carve_polygon, slit)
	if merged.is_empty():
		return result

	var clipped := Geometry2D.clip_polygons(shape_polygon, merged[0])
	for poly in clipped:
		if not Geometry2D.is_polygon_clockwise(poly):
			result.append(poly)

	return result


func _find_best_slit_target(
	carve_center: Vector2,
	carve_polygon: PackedVector2Array,
	shape_polygon: PackedVector2Array
) -> Vector2:
	var best_point := Vector2()
	var best_cost := INF
	var upward_penalty := 4.0

	var n := shape_polygon.size()
	for i in n:
		var a := shape_polygon[i]
		var b := shape_polygon[(i + 1) % n]

		var closest := Geometry2D.get_closest_point_to_segment(carve_center, a, b)

		if Geometry2D.is_point_in_polygon(closest, carve_polygon):
			continue

		var delta := closest - carve_center
		var dist := delta.length()
		if dist < 0.1:
			continue

		if not slit_angle_range.is_in_range(delta):
			continue

		var direction := delta.normalized()
		var penalty := 1.0
		if direction.y < 0.0:
			penalty += (-direction.y) * upward_penalty

		var cost := dist * penalty
		if cost < best_cost:
			best_cost = cost
			best_point = closest

	# Nothing found in the allowed range? Just go straight down.
	if best_cost == INF:
		var shape_bottom := -INF
		for p in shape_polygon:
			if p.y > shape_bottom:
				shape_bottom = p.y
		best_point = Vector2(carve_center.x, shape_bottom + 2)

	return best_point


# -- Shape management ----------------------------------------------------------

func _update_shape_points(shape: SS2D_Shape, new_polygon: PackedVector2Array) -> void:
	var pa := shape.get_point_array()
	pa.begin_update()
	pa.clear()
	for point in new_polygon:
		pa.add_point_direct(point)
	pa.close_shape()
	pa.end_update()


func _create_fragment_shape(original: SS2D_Shape, polygon: PackedVector2Array) -> void:
	var container := StaticBody2D.new()
	container.name = "Shape"
	$Shapes.add_child(container)

	var new_shape := SS2D_Shape.new()
	new_shape.transform = original.transform
	new_shape.modulate = original.modulate

	# Share the material so textures stay consistent across fragments.
	new_shape.shape_material = original.shape_material
	new_shape.flip_edges = original.flip_edges
	new_shape.render_edges = original.render_edges
	new_shape.collision_size = original.collision_size
	new_shape.collision_offset = original.collision_offset
	new_shape.collision_generation_method = original.collision_generation_method
	new_shape.collision_update_mode = SS2D_Shape.CollisionUpdateMode.Runtime

	container.add_child(new_shape)

	var col_poly := CollisionPolygon2D.new()
	container.add_child(col_poly)
	new_shape.collision_polygon_node_path = new_shape.get_path_to(col_poly)

	# Setting points triggers bake_collision() via end_update().
	var pa := new_shape.get_point_array()
	pa.begin_update()
	for point in polygon:
		pa.add_point_direct(point)
	pa.close_shape()
	pa.end_update()


func _create_standalone_shape(polygon: PackedVector2Array) -> void:
	var container := StaticBody2D.new()
	container.name = "Shape"
	$Shapes.add_child(container)

	var new_shape := SS2D_Shape.new()
	var existing := _get_all_shapes()
	if not existing.is_empty():
		var ref := existing[0]
		new_shape.shape_material = ref.shape_material
		new_shape.collision_size = ref.collision_size
		new_shape.collision_offset = ref.collision_offset
		new_shape.collision_generation_method = ref.collision_generation_method
	new_shape.collision_update_mode = SS2D_Shape.CollisionUpdateMode.Runtime

	container.add_child(new_shape)

	var col_poly := CollisionPolygon2D.new()
	container.add_child(col_poly)
	new_shape.collision_polygon_node_path = new_shape.get_path_to(col_poly)

	var pa := new_shape.get_point_array()
	pa.begin_update()
	for point in polygon:
		pa.add_point_direct(point)
	pa.close_shape()
	pa.end_update()


func _remove_shape(shape: SS2D_Shape) -> void:
	var container := shape.get_parent()
	if container and container is StaticBody2D and container.get_parent() == $Shapes:
		container.queue_free()
	else:
		var col_node := shape.get_collision_polygon_node()
		if col_node:
			col_node.queue_free()
		shape.queue_free()


func _get_all_shapes() -> Array[SS2D_Shape]:
	var shapes: Array[SS2D_Shape] = []
	for container in $Shapes.get_children():
		for child in container.get_children():
			if child is SS2D_Shape:
				shapes.append(child)
	return shapes


# -- Helpers -------------------------------------------------------------------

static func _clean_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	if polygon.size() < 2:
		return polygon
	# Remove duplicate last point if it matches first (closed curve)
	if polygon[0].distance_to(polygon[-1]) < 0.1:
		polygon = polygon.slice(0, -1)
	# Remove near-duplicate consecutive points
	var cleaned := PackedVector2Array()
	cleaned.append(polygon[0])
	for i in range(1, polygon.size()):
		if polygon[i].distance_to(polygon[i - 1]) > 0.5:
			cleaned.append(polygon[i])
	return cleaned


func _to_local_polygon(global_polygon: PackedVector2Array) -> PackedVector2Array:
	return global_transform.affine_inverse() * global_polygon


func _transform_polygon(polygon: PackedVector2Array, xform: Transform2D) -> PackedVector2Array:
	return xform * polygon


static func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var n := polygon.size()
	for i in n:
		var j := (i + 1) % n
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	return absf(area) * 0.5


static func _avg_position(polygon: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in polygon:
		sum += p
	return sum / polygon.size()
