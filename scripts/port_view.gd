extends Node2D
## Uncharted Waters 2 (대항해시대 2) - Port Exploration & Building Interaction View
## Renders the 96x96 port map from PORTMAP.LZW using the regional PORTCHIP.LZW tileset,
## animates the 16x32 protagonist sprite from CHAR.LZW, and handles building entry via ZA_DAT.DAT.

signal request_sail_out(port_id: int)
signal building_entered(building_info: Dictionary)

const VIEW_TILES_X: int = 28
const VIEW_TILES_Y: int = 21
const TILE_SIZE: int = 16
const MAP_W: int = 96
const MAP_H: int = 96

var port_id: int = 0
var port_data: Dictionary = {}
var map_bytes: PackedByteArray = PackedByteArray()
var walk_thresholds: Array = [0, 29, 34, 40]

var player_x: int = 36
var player_y: int = 48
var player_dir: int = 2 # 0: Up(North), 1: Right(East), 2: Down(South), 3: Left(West)
var anim_frame: int = 0
var move_cooldown: float = 0.0
var is_modal_open: bool = false


func setup_port(new_port_id: int) -> void:
	port_id = new_port_id
	port_data = GameData.get_port(port_id)
	map_bytes = GameData.get_port_map_bytes(port_id)
	walk_thresholds = port_data.get("walkability_thresholds", [0, 29, 34, 40])
	player_x = clampi(int(port_data.get("spawn_x", 48)), 2, MAP_W - 3)
	player_y = clampi(int(port_data.get("spawn_y", 48)), 2, MAP_H - 3)
	player_dir = 2
	queue_redraw()


func _process(delta: float) -> void:
	if is_modal_open:
		return

	if move_cooldown > 0.0:
		move_cooldown -= delta
		return

	var dx := 0
	var dy := 0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dy = -1
		player_dir = 0
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dx = 1
		player_dir = 1
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dy = 1
		player_dir = 2
	elif Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dx = -1
		player_dir = 3

	if dx != 0 or dy != 0:
		_try_step(dx, dy)
		move_cooldown = 0.11


func _unhandled_input(event: InputEvent) -> void:
	if is_modal_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_Z]:
			var b := _find_nearby_building(player_x, player_y)
			if not b.is_empty():
				building_entered.emit(b)


func _try_step(dx: int, dy: int) -> void:
	var nx := clampi(player_x + dx, 1, MAP_W - 2)
	var ny := clampi(player_y + dy, 1, MAP_H - 2)
	anim_frame = 1 - anim_frame

	# Check if stepping directly into a building door
	var b := _find_building_at_door(nx, ny)
	if not b.is_empty():
		player_x = nx
		player_y = ny
		GameData.advance_hours(1)
		queue_redraw()
		building_entered.emit(b)
		return

	if _is_tile_walkable(nx, ny):
		player_x = nx
		player_y = ny
		queue_redraw()
	else:
		queue_redraw()


func _is_tile_walkable(tx: int, ty: int) -> bool:
	if map_bytes.is_empty():
		return true
	var tid: int = int(map_bytes[ty * MAP_W + tx])
	# In Uncharted Waters 2 PORTCHIP.LZW:
	# Walkable ground/road/plaza/bridge/door tiles are below the walkability threshold (typically <= 40),
	# plus open doorway tiles (0x16, 0x17, 0x29..0x2e).
	var max_walk: int = int(walk_thresholds[3]) if walk_thresholds.size() >= 4 else 40
	if tid < max_walk:
		return true
	if tid in [0x16, 0x17, 0x22, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E]:
		return true
	return false


func _find_building_at_door(tx: int, ty: int) -> Dictionary:
	var buildings: Array = port_data.get("buildings", [])
	for b in buildings:
		var bx: int = int(b["x"])
		var by: int = int(b["y"])
		# Each building in ZA_DAT.DAT has its sign/roof at (bx, by) and its 2-tile wide door at (bx, by+1) & (bx+1, by+1)
		if (tx == bx or tx == bx + 1) and (ty == by or ty == by + 1):
			return b
	return {}


func _find_nearby_building(tx: int, ty: int) -> Dictionary:
	var buildings: Array = port_data.get("buildings", [])
	for b in buildings:
		var bx: int = int(b["x"])
		var by: int = int(b["y"])
		if abs(tx - bx) <= 2 and abs(ty - (by + 1)) <= 2:
			return b
	return {}


func _draw() -> void:
	if map_bytes.is_empty():
		return

	var chip_no: int = int(port_data.get("chip_no", 0))
	var tod_key := GameData.get_port_time_of_day_key()
	var tex_key := "%d_%s" % [chip_no, tod_key]
	var tileset_tex: Texture2D = GameData.port_tileset_textures.get(tex_key)
	if tileset_tex == null:
		return

	var cam_x := clampi(player_x - VIEW_TILES_X / 2, 0, MAP_W - VIEW_TILES_X)
	var cam_y := clampi(player_y - VIEW_TILES_Y / 2, 0, MAP_H - VIEW_TILES_Y)

	# 1. Draw 28x21 viewport of 16x16 port tiles (448 x 336 pixels)
	for vy in range(VIEW_TILES_Y):
		var my := cam_y + vy
		var row_off := my * MAP_W
		for vx in range(VIEW_TILES_X):
			var mx := cam_x + vx
			var tid: int = map_bytes[row_off + mx]
			var src_rect := Rect2((tid % 16) * 16, (tid / 16) * 16, 16, 16)
			var dst_rect := Rect2(vx * 16, vy * 16, 16, 16)
			draw_texture_rect_region(tileset_tex, dst_rect, src_rect)

	# 2. Draw subtle markers/labels for buildings in view when holding TAB or near them
	var buildings: Array = port_data.get("buildings", [])
	var font: Font = GameData.korean_font if GameData.korean_font != null else ThemeDB.fallback_font
	for b in buildings:
		var b_tile_x: int = int(b["x"])
		var b_tile_y: int = int(b["y"])
		var bx: int = b_tile_x - cam_x
		var by: int = b_tile_y - cam_y
		if bx >= 0 and bx < VIEW_TILES_X and by >= 0 and by < VIEW_TILES_Y:
			var dist: int = abs(player_x - b_tile_x) + abs(player_y - (b_tile_y + 1))
			if dist <= 6:
				var label_pos := Vector2(bx * 16 - 4, by * 16 - 4)
				draw_rect(Rect2(label_pos + Vector2(-2, -11), Vector2(b["name_kr"].length() * 11 + 6, 14)), Color(0, 0, 0, 0.75), true)
				draw_string(font, label_pos, b["name_kr"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.4))

	# 3. Draw 32x32 Player Character Sprite from CHAR.LZW (assembled as 2 cols x 4 rows of 32x32 frames):
	# Row 0: North (Up)    [frame 0, frame 1]
	# Row 1: East  (Right) [frame 0, frame 1]
	# Row 2: South (Down)  [frame 0, frame 1]
	# Row 3: West  (Left)  [frame 0, frame 1]
	var char_tex: Texture2D = GameData.char_sprite_textures.get(GameData.protagonist_id)
	if char_tex != null:
		var dir_row := player_dir
		var col := anim_frame
		var screen_x := (player_x - cam_x) * 16 - 8
		var screen_y := (player_y - cam_y) * 16 - 16
		var src_rect := Rect2(col * 32, dir_row * 32, 32, 32)
		draw_texture_rect_region(char_tex, Rect2(screen_x, screen_y, 32, 32), src_rect)
