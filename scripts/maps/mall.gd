extends "res://scripts/maps/map_def.gd"
## A shopping mall: shops behind roll-down shutters around a concourse.


func _init() -> void:
	id = "mall"
	title = "Shopping Mall"
	twist = "shutters"
	blurb = "Shops behind roll-down shutters. Close them all; thieves force them open."
	duty_hint = "Close every shop shutter, lock the doors and arm the alarm."
	map = [
		"####W###################W###############",
		"#.........#.........#.........#........#",
		"#.........#.........#..V......#........#",
		"#..V.L....#....V....#....L....#....V...#",
		"#.........#.........#.........#....L...#",
		"#......V..#.........#......V..#........#",
		"#.........#.........#.........#........#",
		"#####H#########H#########H#########H####",
		"#.1..........A.......................3.#",
		"E.........L.......####.P...............#",
		"#.................####.......L.........#",
		"#...............2......................#",
		"####......#########H###########.########",
		"#............#............#..........B.#",
		"#.S..........#............#............#",
		"#.....L......#.....L......#.....L......E",
		"#............#..V.........#............#",
		"#...4........#.........V..#........5.S.#",
		"#............#............#............#",
		"######W#################################",
	]
	checkpoint_names = ["West Entrance", "Fountain", "East Concourse", "Food Court", "Loading Bay"]
	room_labels = [
		["BOUTIQUE", Vector2i(1, 1)],
		["JEWELLER", Vector2i(11, 1)],
		["ELECTRONICS", Vector2i(21, 1)],
		["SPORTS", Vector2i(31, 1)],
		["CONCOURSE", Vector2i(2, 10)],
		["FOOD COURT", Vector2i(1, 13)],
		["DEPT. STORE", Vector2i(14, 13)],
		["LOADING BAY", Vector2i(27, 14)],
	]
	door_names = ["main", "loading bay"]
	window_names = ["Boutique", "Electronics", "Food Court"]
	shutter_names = ["Boutique", "Jeweller", "Electronics", "Sports", "Dept. Store"]
	loot = "retail"
	theme["floor_a"] = Color(0.4, 0.4, 0.42)
	theme["floor_b"] = Color(0.36, 0.36, 0.38)
	theme["grout"] = Color(0.26, 0.26, 0.28)
	theme["wall"] = Color(0.12, 0.13, 0.17)
	theme["wall_edge"] = Color(0.3, 0.36, 0.48)
	theme["label"] = Color(0.6, 0.75, 0.95, 0.35)
	theme["lamp"] = Color(0.85, 0.92, 1.0)
