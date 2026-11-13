extends "res://scripts/maps/map_def.gd"
## A block of flats: six homes, a long corridor and a lobby.


func _init() -> void:
	id = "apartment"
	title = "Apartment Block"
	twist = "calls"
	blurb = "Six flats and nervous residents. Answer the intercom calls in time."
	duty_hint = "Lock both doors, arm the alarm in the lobby, and answer resident calls."
	map = [
		"######W#############W############W######",
		"#............#............#............#",
		"#........V...#...2........#..V.........#",
		"#..1.........#.........V..#......L..3..#",
		"#....L.......#.......L....#............#",
		"#............#............#..........S.#",
		"#..V..F......#..V...F.....#......F...V.#",
		"#............#............#............#",
		"######.#############.############.######",
		"#.......L..............................E",
		"#.............................L........#",
		"#######.#########......#########.#######",
		"#......F......#.A........#......F......#",
		"#.............#..........#...........B.#",
		"#....L........#..........#........L....#",
		"#.S...........#....L.....#.............#",
		"#.........V...#....P.....#.............#",
		"#..4..........#..........#...V......5..#",
		"#.............#..........#.............#",
		"######W############E############W#######",
	]
	checkpoint_names = ["Flat 1A", "Flat 1B", "Flat 1C", "Flat 2A", "Flat 2B"]
	room_labels = [
		["FLAT 1A", Vector2i(1, 1)],
		["FLAT 1B", Vector2i(14, 1)],
		["FLAT 1C", Vector2i(27, 1)],
		["CORRIDOR", Vector2i(11, 10)],
		["FLAT 2A", Vector2i(1, 13)],
		["LOBBY", Vector2i(20, 13)],
		["FLAT 2B", Vector2i(27, 14)],
	]
	door_names = ["back", "main"]
	window_names = ["Flat 1A", "Flat 1B", "Flat 1C", "Flat 2A", "Flat 2B"]
	call_names = ["Flat 1A", "Flat 1B", "Flat 1C", "Flat 2A", "Flat 2B"]
	loot = "homes"
	theme["floor_a"] = Color(0.34, 0.27, 0.22)
	theme["floor_b"] = Color(0.3, 0.24, 0.2)
	theme["grout"] = Color(0.2, 0.15, 0.12)
	theme["wall"] = Color(0.15, 0.12, 0.14)
	theme["wall_edge"] = Color(0.34, 0.26, 0.28)
	theme["label"] = Color(0.85, 0.7, 0.6, 0.35)
	theme["lamp"] = Color(1.0, 0.8, 0.55)
