extends RefCounted
## A location to guard: its layout, names, look and signature twist.
##
## Map legend (one character per 48 px tile):
##   #  wall                 .  floor
##   K  machinery / racks (solid, drawn as metal)
##   P  watchman start       1-5 punch clocks (named by checkpoint_names)
##   V  valuable             L  ceiling lamp
##   E  outside door         W  window in an outer wall
##   A  alarm panel          B  breaker box
##   S  Shadow spawn
##   H  shop shutter (mall)  F  flat intercom call spot (apartment)
##   M  machine control panel (factory)
## Names for doors, windows, shutters, call spots and machines are given in
## reading order (row by row, left to right).

var id := ""
var title := ""
## "" (none), "calls", "shutters" or "machines".
var twist := ""
## One line for the menu card.
var blurb := ""
## Opening hint shown at the start of a shift.
var duty_hint := ""

var map: Array = []
var checkpoint_names: Array = []
var room_labels: Array = []      # [[text, Vector2i], ...]
var door_names: Array = []
var window_names: Array = []
var shutter_names: Array = []
var call_names: Array = []
var machine_names: Array = []
## Breaker circuits: x < wing_bounds.x is West, x >= wing_bounds.y is East.
var wing_bounds := Vector2i(12, 26)
## Loot style drawn by valuable.gd: "art", "homes", "retail", "industrial".
var loot := "art"
var theme := {
	"floor_a": Color(0.36, 0.33, 0.29),
	"floor_b": Color(0.31, 0.29, 0.26),
	"grout": Color(0.22, 0.2, 0.18),
	"crack": Color(0.2, 0.18, 0.16),
	"wall": Color(0.11, 0.12, 0.18),
	"wall_edge": Color(0.22, 0.25, 0.36),
	"label": Color(0.55, 0.6, 0.8, 0.35),
	"lamp": Color(1.0, 0.85, 0.6),
}
