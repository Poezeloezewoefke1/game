class_name SkinData
extends RefCounted
## A parsed Minecraft-style skin: normalized RGBA8 image (64x64 or HD multiple), model variant, origin.

var id: String = ""
var image: Image
var slim: bool = false          # 3px-wide arms ("Alex" layout)
var legacy: bool = false        # originally a 64x32 skin (no second layers on body/limbs, mirrored left limbs)
var source_path: String = ""
var placeholder: bool = false   # true if generated because no supplied asset existed
var scale: int = 1              # 1 for 64x64, 2 for 128x128, ...
var _texture: ImageTexture

func get_texture() -> ImageTexture:
	if _texture == null and image != null:
		_texture = ImageTexture.create_from_image(image)
	return _texture

func texture_size() -> Vector2:
	return Vector2(image.get_width(), image.get_height()) if image != null else Vector2(64, 64)

func describe() -> String:
	return "%s (%dx%d, %s%s%s)" % [id, image.get_width(), image.get_height(),
		"slim" if slim else "classic", ", legacy" if legacy else "", ", placeholder" if placeholder else ""]
