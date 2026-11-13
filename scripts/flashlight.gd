extends RefCounted
## Helpers that generate light textures in code (no image assets needed).


## A cone pointing along +X, centred in a size x size texture.
static func make_cone_texture(size: int, half_angle: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	var r := size / 2.0
	var soft_edge := half_angle * 0.35
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := p.length()
			var v := 0.0
			if d < r:
				var ang := absf(p.angle())
				if ang < half_angle:
					var radial := pow(1.0 - d / r, 0.7)
					var edge := clampf((half_angle - ang) / soft_edge, 0.0, 1.0)
					v = radial * edge
				# A small spill of light right at the lens.
				v = maxf(v, clampf(1.0 - d / (r * 0.12), 0.0, 1.0) * 0.6)
			img.set_pixel(x, y, Color(v, v, v, v))
	return ImageTexture.create_from_image(img)


## Soft round light, white in the middle fading to nothing at the edge.
static func make_radial_texture(size: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
