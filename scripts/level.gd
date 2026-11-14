extends Node2D
## The building. Built from a location definition (scripts/maps/*.gd): an
## ASCII map turned into wall collisions, light occluders, a pathfinding grid
## and code-drawn floors/walls. See scripts/maps/map_def.gd for the legend.

const TILE := 48

const WALL_LAYER := 1
const DOOR_LAYER := 4

var width := 0
var height := 0
var player_spawn := Vector2.ZERO
var checkpoints: Array = []   # [{ "name": String, "pos": Vector2 }]
var valuables: Array[Vector2] = []
var lamps: Array[Vector2] = []
## Location being guarded (a map_def.gd instance).
var def
## Outside doors / windows / shutters / call spots / machine panels:
## [{ "name": String, "pos": Vector2 }] in reading order.
var entries: Array = []
var windows: Array = []
var shutters: Array = []
var call_spots: Array = []
var machines: Array = []
var alarm_pos := Vector2.ZERO
var breaker_pos := Vector2.ZERO
var shadow_spawns: Array[Vector2] = []
var floor_cells: Array[Vector2i] = []
var astar := AStarGrid2D.new()

## Node drawn in the glow layer (walls stay faintly visible in the dark).
var wall_node: Node2D

var _walls := {}
var _doors := {}
var _windows := {}
var _machinery := {}
var _shutter_cells := {}
## Interior doorways (one-tile gaps in a wall) -> seconds since last swing.
var _doorways := {}
var _floor_seed := []


static func unshaded_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


func _named(list: Array, names: Array, pos: Vector2, fallback: String) -> void:
	var i := list.size()
	list.append({"pos": pos, "name": names[i] if i < names.size() else "%s %d" % [fallback, i + 1]})


func build(location) -> void:
	def = location
	height = def.map.size()
	width = (def.map[0] as String).length()
	var cp_slots := {}
	for y in height:
		var row: String = def.map[y]
		for x in width:
			var ch := row[x]
			var cell := Vector2i(x, y)
			var pos := cell_to_world(cell)
			match ch:
				"#":
					_walls[cell] = true
				"K":
					_walls[cell] = true
					_machinery[cell] = true
				"E":
					_doors[cell] = true
					_named(entries, def.door_names, pos, "door")
				"H":
					_shutter_cells[cell] = true
					_named(shutters, def.shutter_names, pos, "Shop")
				"F":
					_named(call_spots, def.call_names, pos, "Flat")
				"M":
					_named(machines, def.machine_names, pos, "Machine")
				"P":
					player_spawn = pos
				"V":
					valuables.append(pos)
				"L":
					lamps.append(pos)
				"S":
					shadow_spawns.append(pos)
				"W":
					_doors[cell] = true
					_windows[cell] = true
					_named(windows, def.window_names, pos, "window")
				"A":
					alarm_pos = pos
				"B":
					breaker_pos = pos
				"1", "2", "3", "4", "5":
					cp_slots[int(ch) - 1] = pos
			if ch != "#" and ch != "K":
				floor_cells.append(cell)
	for i in def.checkpoint_names.size():
		if cp_slots.has(i):
			checkpoints.append({"name": def.checkpoint_names[i], "pos": cp_slots[i]})

	for cell in floor_cells:
		if _doors.has(cell) or _shutter_cells.has(cell):
			continue
		# A doorway is a one-tile gap in a thin wall (not a narrow corridor).
		var lr := _walls.has(cell + Vector2i.LEFT) and _walls.has(cell + Vector2i.RIGHT) \
				and not _walls.has(cell + Vector2i(-1, -1)) and not _walls.has(cell + Vector2i(-1, 1))
		var ud := _walls.has(cell + Vector2i.UP) and _walls.has(cell + Vector2i.DOWN) \
				and not _walls.has(cell + Vector2i(-1, -1)) and not _walls.has(cell + Vector2i(1, -1))
		if lr or ud:
			_doorways[cell] = 99.0

	_build_collision()
	_build_astar()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in width * height:
		_floor_seed.append(rng.randf())

	_bake()
	wall_node = Node2D.new()
	wall_node.name = "Walls"
	wall_node.draw.connect(_draw_walls)
	queue_redraw()


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "WallBody"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	# Merge horizontal runs of wall tiles into single rectangles.
	for y in height:
		var x := 0
		while x < width:
			if _walls.has(Vector2i(x, y)):
				var start := x
				while x < width and _walls.has(Vector2i(x, y)):
					x += 1
				_add_wall_rect(body, Rect2(start * TILE, y * TILE, (x - start) * TILE, TILE))
			else:
				x += 1
	# Doors to the outside: block the player, but not light rays or intruders.
	var door_body := StaticBody2D.new()
	door_body.name = "DoorBody"
	door_body.collision_layer = DOOR_LAYER
	door_body.collision_mask = 0
	add_child(door_body)
	for cell in _doors:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = cell_to_world(cell)
		door_body.add_child(shape)


func _add_wall_rect(body: StaticBody2D, r: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	shape.shape = rect
	shape.position = r.get_center()
	body.add_child(shape)

	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	])
	occ.occluder = poly
	add_child(occ)


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE / 2.0, TILE / 2.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for cell in _walls:
		astar.set_point_solid(cell, true)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(pos.x / TILE), 0, width - 1), clampi(int(pos.y / TILE), 0, height - 1))


## Which breaker circuit a position belongs to.
func wing_of(pos: Vector2) -> String:
	var x := world_to_cell(pos).x
	if x < def.wing_bounds.x:
		return "West"
	if x >= def.wing_bounds.y:
		return "East"
	return "Centre"


## Direction from an edge cell (door/window) towards the inside of the building.
func inward_of(pos: Vector2) -> Vector2:
	var cell := world_to_cell(pos)
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var n: Vector2i = cell + d
		if n.x >= 0 and n.y >= 0 and n.x < width and n.y < height and not _walls.has(n):
			return Vector2(d)
	return Vector2.ZERO


## Make a cell impassable (or passable again) for pathfinding.
func set_cell_solid(pos: Vector2, solid: bool) -> void:
	astar.set_point_solid(world_to_cell(pos), solid)


func is_cell_solid(pos: Vector2) -> bool:
	return astar.is_point_solid(world_to_cell(pos))


## Door, window or shutter cell: walkable for thieves but not a place for items.
func is_opening(cell: Vector2i) -> bool:
	return _doors.has(cell) or _shutter_cells.has(cell)


func is_doorway(cell: Vector2i) -> bool:
	return _doorways.has(cell)


func swing_door(cell: Vector2i) -> void:
	if _doorways.has(cell):
		_doorways[cell] = 0.0


func _process(delta: float) -> void:
	var animating := false
	for cell in _doorways:
		if _doorways[cell] < 3.0:
			_doorways[cell] += delta
			animating = true
	if animating and wall_node:
		wall_node.queue_redraw()


func is_wall(cell: Vector2i) -> bool:
	return _walls.has(cell)


func world_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


## Grid path between two world points (cell centres), empty if unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := world_to_cell(from)
	var b := world_to_cell(to)
	if is_wall(a) or is_wall(b):
		return PackedVector2Array()
	var path := astar.get_point_path(a, b)
	if path.size() > 0:
		path[path.size() - 1] = to
	return path


func random_floor_far_from(pos: Vector2, min_dist: float) -> Vector2:
	for i in 40:
		var cell: Vector2i = floor_cells.pick_random()
		if _doors.has(cell) or _shutter_cells.has(cell):
			continue
		var p := cell_to_world(cell)
		if p.distance_to(pos) >= min_dist:
			return p
	return cell_to_world(floor_cells.pick_random())


## Floor and walls never change, so they are painted once into two images
## at load time and drawn as two textures (instead of thousands of shapes
## every frame, which cheap phones struggle with).
var _floor_tex: ImageTexture
var _wall_tex: ImageTexture


func _bake() -> void:
	var w := width * TILE
	var h := height * TILE
	var floor_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var grout: Color = def.theme["grout"]
	var crack: Color = def.theme["crack"]
	for cell in floor_cells:
		var x0: int = cell.x * TILE
		var y0: int = cell.y * TILE
		var checker := (cell.x + cell.y) % 2 == 0
		floor_img.fill_rect(Rect2i(x0, y0, TILE, TILE), def.theme["floor_a"] if checker else def.theme["floor_b"])
		for edge in [Rect2i(x0, y0, TILE, 1), Rect2i(x0, y0 + TILE - 1, TILE, 1), Rect2i(x0, y0, 1, TILE), Rect2i(x0 + TILE - 1, y0, 1, TILE)]:
			floor_img.fill_rect(edge, grout)
		var sd: float = _floor_seed[cell.y * width + cell.x]
		if sd > 0.82:
			# A crack or scuff on some tiles.
			var a := Vector2(x0 + 8 + sd * 20, y0 + 10)
			var b := a + Vector2(14, 18 * sd)
			for i in 24:
				var q := a.lerp(b, i / 23.0)
				floor_img.fill_rect(Rect2i(int(q.x), int(q.y), 2, 2), crack)
	_floor_tex = ImageTexture.create_from_image(floor_img)

	var wall_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fill: Color = def.theme["wall"]
	var edge_col: Color = def.theme["wall_edge"]
	for cell in _walls:
		var x0: int = cell.x * TILE
		var y0: int = cell.y * TILE
		if _machinery.has(cell):
			_bake_machinery(wall_img, cell, x0, y0)
			continue
		wall_img.fill_rect(Rect2i(x0, y0, TILE, TILE), fill)
		# Highlight edges that face a floor tile.
		if not _walls.has(cell + Vector2i.DOWN) and cell.y + 1 < height:
			wall_img.fill_rect(Rect2i(x0, y0 + TILE - 3, TILE, 3), edge_col)
		if not _walls.has(cell + Vector2i.UP) and cell.y > 0:
			wall_img.fill_rect(Rect2i(x0, y0, TILE, 2), edge_col)
		if not _walls.has(cell + Vector2i.LEFT) and cell.x > 0:
			wall_img.fill_rect(Rect2i(x0, y0, 2, TILE), edge_col)
		if not _walls.has(cell + Vector2i.RIGHT) and cell.x + 1 < width:
			wall_img.fill_rect(Rect2i(x0 + TILE - 2, y0, 2, TILE), edge_col)
	for cell in _doors:
		if _windows.has(cell):
			continue
		var r := Rect2i(cell.x * TILE + 6, cell.y * TILE + 2, TILE - 12, TILE - 4)
		wall_img.fill_rect(r, Color(0.45, 0.3, 0.18))
		wall_img.fill_rect(r.grow(-2), Color(0.28, 0.17, 0.1))
	_wall_tex = ImageTexture.create_from_image(wall_img)


## Machinery and racks: steel blocks with rivets and hazard edges.
func _bake_machinery(img: Image, cell: Vector2i, x0: int, y0: int) -> void:
	img.fill_rect(Rect2i(x0, y0, TILE, TILE), Color(0.2, 0.22, 0.24))
	img.fill_rect(Rect2i(x0 + 4, y0 + 4, TILE - 8, TILE - 8), Color(0.26, 0.28, 0.3))
	img.fill_rect(Rect2i(x0 + 6, y0 + 6, 4, 4), Color(0.4, 0.42, 0.45))
	img.fill_rect(Rect2i(x0 + TILE - 10, y0 + TILE - 10, 4, 4), Color(0.4, 0.42, 0.45))
	if not _machinery.has(cell + Vector2i.DOWN):
		img.fill_rect(Rect2i(x0, y0 + TILE - 4, TILE, 3), Color(0.58, 0.49, 0.17))


func _draw() -> void:
	# Floors are shaded: you only see them by lamp or flashlight.
	if _floor_tex != null:
		draw_texture(_floor_tex, Vector2.ZERO)


func _draw_walls() -> void:
	if _wall_tex != null:
		wall_node.draw_texture(_wall_tex, Vector2.ZERO)
	for cell in _doorways:
		_draw_door(cell, _doorways[cell])
	var font := ThemeDB.fallback_font
	for label in def.room_labels:
		var cell: Vector2i = label[1]
		wall_node.draw_string(font, Vector2(cell.x * TILE + 8, cell.y * TILE + 22), label[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, def.theme["label"])


## A door leaf hinged on the doorway's wall, standing open. After the
## watchman walks through it swings part-way shut and settles back.
func _draw_door(cell: Vector2i, since_swing: float) -> void:
	var passage_vertical := _walls.has(cell + Vector2i.LEFT)  # walls left/right -> walk up/down
	var hinge: Vector2
	var closed: float
	if passage_vertical:
		hinge = Vector2(cell.x * TILE, cell.y * TILE + TILE / 2.0)
		closed = 0.0            # leaf pointing right, across the gap
	else:
		hinge = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE)
		closed = PI / 2.0       # leaf pointing down, across the gap
	var swing := 0.0
	if since_swing < 3.0:
		swing = 1.1 * sin(since_swing * 7.0) * exp(-since_swing * 2.2)
	var angle := closed + PI / 2.0 - absf(swing)
	var length := TILE * 0.9
	wall_node.draw_arc(hinge, length, closed, closed + PI / 2.0, 12, Color(0.45, 0.32, 0.2, 0.18), 1.0)
	var tip := hinge + Vector2.from_angle(angle) * length
	wall_node.draw_line(hinge, tip, Color(0.42, 0.27, 0.15), 5.0)
	wall_node.draw_line(hinge, tip, Color(0.6, 0.42, 0.25), 1.5)
	wall_node.draw_circle(hinge, 3.0, Color(0.7, 0.6, 0.35))
