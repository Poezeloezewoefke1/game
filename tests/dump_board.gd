extends Node
## Saves the painted 2D board for a map straight to a PNG, with no lighting or camera involved.
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/dump_board.gd 2 <map_id> <out>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id := String(args[2]) if args.size() > 2 else "fort_feather"
	var out := String(args[3]) if args.size() > 3 else "/tmp/board_flat.png"
	var def: Dictionary = DataDB.maps.get(map_id, {})
	var mb := MapBuilder.new()
	add_child(mb)
	mb.build(def)
	var painter := BoardPainter.new()
	var img := painter.paint(def, mb.path, mb.board_bounds)
	img.save_png(out)
	print("[BOARD] %s bounds=%s image=%dx%d -> %s" % [map_id, mb.board_bounds, img.get_width(), img.get_height(), out])

func on_frame(_f: int) -> void:
	pass

func on_finish() -> void:
	pass
