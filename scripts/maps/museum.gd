extends "res://scripts/maps/map_def.gd"
## The original location: an old museum with galleries, a vault and a basement.


func _init() -> void:
	id = "museum"
	title = "Museum"
	twist = ""
	blurb = "Galleries, a vault and a basement. The classic night shift."
	duty_hint = "Lock both outside doors and arm the alarm in the lobby."
	map = [
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
	checkpoint_names = ["Archive", "Gallery", "Storage", "Basement", "Office"]
	room_labels = [
		["ARCHIVE", Vector2i(1, 1)],
		["GALLERY", Vector2i(12, 1)],
		["STORAGE", Vector2i(22, 1)],
		["LOBBY", Vector2i(16, 7)],
		["BASEMENT", Vector2i(1, 13)],
		["VAULT", Vector2i(13, 13)],
		["OFFICE", Vector2i(27, 13)],
	]
	door_names = ["west", "east"]
	window_names = ["Archive", "Storage", "Basement", "Office"]
	loot = "art"
