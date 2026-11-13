extends Node2D
## The building. Parsed from an ASCII map, then turned into wall collisions,
## light occluders, a pathfinding grid and code-drawn floors/walls.
##
## Legend:
##   #  wall              .  floor
##   P  player spawn      1-5 punch-clock checkpoints
##   V  valuable          L  wall lamp
##   E  outside door (intruders come and go here)
##   S  shadow spawn
##   A  alarm panel       B  breaker box
##   W  window in an outer wall (thieves can smash in)

const TILE := 48

const MAP := [
	"#####W#########################W########",
	"#..........#.........#.................#",
	"#....V.....#....V....#......V.....V....#",
	"#..........#.........#.................#",
	"#.....1....#....2....#.........3.......#",
	"#..L.......#.........#.......L.........#",
	"#####.######...L.....######.############",
	"#....................A.................#",
	"#.........L.........................L..#",
	"E..................P...................E",
	"#......................................#",
	"#......................................#",
	"#######.#########.####.######.##########",
	"#........B..#.............#............#",
	"#...V.......#....V....V...#.....V......#",
	"#.......4...#.............#............#",
	"#...........#......L......#.......5....#",
	"#..L........#.............#..L.........#",
	"#.....S.....#.............#........S...#",
	"#####W###########################W######",
]

const CHECKPOINT_NAMES := ["Archive", "Gallery", "Storage", "Basement", "Office"]

const ROOM_LABELS := [
	["ARCHIVE", Vector2i(1, 1)],
	["GALLERY", Vector2i(12, 1)],
	["STORAGE", Vector2i(22, 1)],
	["LOBBY", Vector2i(16, 7)],
	["BASEMENT", Vector2i(1, 13)],
	["VAULT", Vector2i(13, 13)],
	["OFFICE", Vector2i(27, 13)],
]

const WALL_LAYER := 1
const DOOR_LAYER := 4

var width := 0
var height := 0
var player_spawn := Vector2.ZERO
var checkpoints: Array = []   # [{ "name": String, "pos": Vector2 }]
var valuables: Array[Vector2] = []
var lamps: Array[Vector2] = []
var entries: Array[Vector2] = []
var alarm_pos := Vector2.ZERO
var windows: Array = []   # [{ "name": String, "pos": Vector2 }]
var breaker_pos := Vector2.ZERO
var shadow_spawns: Array[Vector2] = []
var floor_cells: Array[Vector2i] = []
var astar := AStarGrid2D.new()

## Node drawn in the glow layer (walls stay faintly visible in the dark).
var wall_node: Node2D

var _walls := {}
var _doors := {}
var _windows := {}
## Interior doorways (one-tile gaps in a wall) -> seconds since last swing.
var _doorways := {}
var _floor_seed := []


static func unshaded_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


func build() -> void:
	height = MAP.size()
	width = (MAP[0] as String).length()
	var cp_slots := {}
	for y in height:
		var row: String = MAP[y]
		for x in width:
			var ch := row[x]
			var cell := Vector2i(x, y)
			var pos := cell_to_world(cell)
			match ch:
				"#":
					_walls[cell] = true
				"E":
					_doors[cell] = true
					entries.append(pos)
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
					var top := y < height / 2
					var left := x < width / 2
					windows.append({"pos": pos, "name": ("Archive" if left else "Storage") if top else ("Basement" if left else "Office")})
				"A":
					alarm_pos = pos
				"B":
					breaker_pos = pos
				"1", "2", "3", "4", "5":
					cp_slots[int(ch) - 1] = pos
			if ch != "#":
				floor_cells.append(cell)
	for i in CHECKPOINT_NAMES.size():
		if cp_slots.has(i):
			checkpoints.append({"name": CHECKPOINT_NAMES[i], "pos": cp_slots[i]})

	for cell in floor_cells:
		if _doors.has(cell):
			continue
		var lr := _walls.has(cell + Vector2i.LEFT) and _walls.has(cell + Vector2i.RIGHT)
		var ud := _walls.has(cell + Vector2i.UP) and _walls.has(cell + Vector2i.DOWN)
		if lr or ud:
			_doorways[cell] = 99.0

	_build_collision()
	_build_astar()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in width * height:
		_floor_seed.append(rng.randf())

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
	if x < 12:
		return "West"
	if x >= 26:
		return "East"
	return "Centre"


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
		if _doors.has(cell):
			continue
		var p := cell_to_world(cell)
		if p.distance_to(pos) >= min_dist:
			return p
	return cell_to_world(floor_cells.pick_random())


func _draw() -> void:
	# Floors are shaded: you only see them by lamp or flashlight.
	for cell in floor_cells:
		var r := Rect2(cell.x * TILE, cell.y * TILE, TILE, TILE)
		var checker := (cell.x + cell.y) % 2 == 0
		var base := Color(0.36, 0.33, 0.29) if checker else Color(0.31, 0.29, 0.26)
		draw_rect(r, base)
		var s: float = _floor_seed[cell.y * width + cell.x]
		if s > 0.82:
			# A crack or scuff on some tiles.
			var p := r.position + Vector2(8 + s * 20, 10)
			draw_line(p, p + Vector2(14, 18 * s), Color(0.2, 0.18, 0.16), 1.5)
		draw_rect(r, Color(0.22, 0.2, 0.18), false, 1.0)


func _draw_walls() -> void:
	var fill := Color(0.11, 0.12, 0.18)
	var edge := Color(0.22, 0.25, 0.36)
	for cell in _walls:
		var r := Rect2(cell.x * TILE, cell.y * TILE, TILE, TILE)
		wall_node.draw_rect(r, fill)
		# Highlight edges that face a floor tile.
		if not _walls.has(cell + Vector2i.DOWN) and cell.y + 1 < height:
			wall_node.draw_line(Vector2(r.position.x, r.end.y), r.end, edge, 3.0)
		if not _walls.has(cell + Vector2i.UP) and cell.y > 0:
			wall_node.draw_line(r.position, Vector2(r.end.x, r.position.y), edge, 2.0)
		if not _walls.has(cell + Vector2i.LEFT) and cell.x > 0:
			wall_node.draw_line(r.position, Vector2(r.position.x, r.end.y), edge, 2.0)
		if not _walls.has(cell + Vector2i.RIGHT) and cell.x + 1 < width:
			wall_node.draw_line(Vector2(r.end.x, r.position.y), r.end, edge, 2.0)
	for cell in _doors:
		if _windows.has(cell):
			continue
		var r := Rect2(cell.x * TILE + 6, cell.y * TILE + 2, TILE - 12, TILE - 4)
		wall_node.draw_rect(r, Color(0.28, 0.17, 0.1))
		wall_node.draw_rect(r, Color(0.45, 0.3, 0.18), false, 2.0)
	for cell in _doorways:
		_draw_door(cell, _doorways[cell])
	var font := ThemeDB.fallback_font
	for label in ROOM_LABELS:
		var cell: Vector2i = label[1]
		wall_node.draw_string(font, Vector2(cell.x * TILE + 8, cell.y * TILE + 22), label[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.6, 0.8, 0.35))


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
