extends "res://scripts/maps/map_def.gd"
## A factory: machine hall, offices, warehouse racks and a boiler room.


func _init() -> void:
	id = "factory"
	title = "Factory"
	twist = "machines"
	blurb = "Thieves start the machines to cover their noise. Shut them down before they overheat."
	duty_hint = "Lock the doors, arm the alarm, and keep the machines switched off."
	map = [
		"##########W###################W####W####",
		"#........................#.............#",
		"#.1....................V.#...........V.#",
		"#...KKKK....KKKK...KKK...#....L..3.....#",
		"#...KKKKM...KKKKM..KKK.......V.........#",
		"#.L................KKK...#.............#",
		"E.........LV.....P.KKK...#.............#",
		"#..................KKK...#######.#######",
		"#...KKKK....KKKK...KKK...#.............#",
		"#...KKKKM...KKKK...KKK...#...........S.#",
		"#.V...............L.........KKKKKKKK...#",
		"#......................2.#...........V.#",
		"######.############.######.....L.......#",
		"#............#...........#..KKKKKKKK...E",
		"#.........B..#...........#.............#",
		"#.....L......#.....L.....#.V........L..#",
		"#..5.........#..A.....V..#..KKKKKKKK...#",
		"#.S..........#...........#...........4.#",
		"#............#...........#.............#",
		"######W#################################",
	]
	max_rooms = 2
	checkpoint_names = ["Press Line", "Assembly", "Office", "Warehouse", "Boiler Room"]
	room_labels = [
		["MACHINE HALL", Vector2i(5, 1)],
		["OFFICES", Vector2i(27, 1)],
		["WAREHOUSE", Vector2i(27, 8)],
		["BOILER ROOM", Vector2i(4, 13)],
		["LOCKERS", Vector2i(15, 13)],
	]
	door_names = ["staff", "loading"]
	window_names = ["Machine Hall", "Office", "Office", "Boiler Room"]
	machine_names = ["Press 1", "Press 2", "Lathe"]
	loot = "industrial"
	theme["floor_a"] = Color(0.3, 0.31, 0.28)
	theme["floor_b"] = Color(0.27, 0.28, 0.25)
	theme["grout"] = Color(0.18, 0.19, 0.17)
	theme["crack"] = Color(0.22, 0.2, 0.12)
	theme["wall"] = Color(0.12, 0.13, 0.12)
	theme["wall_edge"] = Color(0.32, 0.34, 0.26)
	theme["label"] = Color(0.85, 0.8, 0.45, 0.35)
	theme["lamp"] = Color(1.0, 0.95, 0.8)
