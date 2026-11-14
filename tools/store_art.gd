extends SceneTree
## Renders the Play Store icon (store/icon_512.png) from icon.svg.
## Run: godot --headless --path . --script res://tools/store_art.gd

func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var img := Image.new()
	var err := img.load_svg_from_string(svg, 1.0)
	if err != OK:
		push_error("Could not render icon.svg (%d)" % err)
		quit(1)
		return
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://store"))
	img.save_png("res://store/icon_512.png")
	print("Saved store/icon_512.png (%dx%d)" % [img.get_width(), img.get_height()])
	quit()
