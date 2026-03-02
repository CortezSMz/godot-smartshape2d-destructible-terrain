# SmartShape2D Destructible Terrain

Destructible 2D terrain for Godot 4.6 using the [SmartShape2D](https://github.com/SirRamEsq/SmartShape2D) plugin.

Carve and rebuild terrain in real-time with polygon booleans. SmartShape2D takes care of re-texturing everything automatically (grass on top, rock on sides, fill, etc), so you don't have to worry about materials after carving.


## How it works

Each terrain piece is an `SS2D_Shape` inside a `StaticBody2D`. Carving uses `Geometry2D.clip_polygons`, adding uses `Geometry2D.merge_polygons`. After modifying the points, SmartShape2D handles mesh + collision regeneration.

- **Carving** (`carve()`): Subtracts a polygon from terrain. Splits the shape into fragments when needed.
- **Adding** (`add()`): Merges a polygon into terrain. If two fragments overlap after adding, they get unified back into one. (IMPROVEMENT)
- **Splitting**: Fragments share the same `shape_material`, so edge and fill textures are preserved.
- **Holes**: Instead of splitting the shape in two when carving a hole in the middle, a thin slit connects the hole to the nearest edge. (IMPROVEMENT) There's also a "smart slit routing" option that looks for the shortest path to an existing cut or boundary, which helps avoid unnecessary splits. (IMPROVEMENT) It favors going downward to keep the grass texture intact. You can toggle it off or adjust the angle range in the Inspector.


## Files

| File | Description |
|------|-------------|
| `DestructibleSmartShape.gd` | Core class. Carving, adding, fragments, holes, scene tree. |
| `DestructibleSmartShapeDemo.gd` | Demo. Left-click = carve, right-click = add, Space = spawn rigidbody. |
| `Main.tscn` | Example scene, ready to run. |


## Configuration

| Property | Default | Description |
|----------|---------|-------------|
| `min_fragment_area` | 100.0 | Fragments smaller than this get discarded. |
| `smart_slit_routing` | true | Routes hole slits toward nearest edge. Off = straight down. (IMPROVEMENT) |
| `slit_angle_range` | 225, 90 | Constrains slit direction. Uses `SS2D_NormalRange` with a visual editor. (IMPROVEMENT) |


## Credits

Built on top of:

- **Destructible terrain base** by matterda -- [github.com/matterda/godot-destructible-terrain](https://github.com/matterda/godot-destructible-terrain). The clipping logic and hole-splitting approach were adapted from here.
- **SmartShape2D** by SirRamEsq -- [github.com/SirRamEsq/SmartShape2D](https://github.com/SirRamEsq/SmartShape2D)
- **Sprites and SS2D tutorial** by Picster -- [youtube.com/watch?v=45PldDNCQhw](https://www.youtube.com/watch?v=r-pd2yuNPvA)
