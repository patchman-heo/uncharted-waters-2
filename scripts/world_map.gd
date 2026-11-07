extends Node2D
## Uncharted Waters 2 (대항해시대 2) - World Map Sailing & Exploration View
## Renders the 2160x1080 autotiled World Map around the player's fleet with horizontal wrap,
## 8-directional sailing with wind/current physics, port entry, and discovery landing.

signal port_docked(port_id: int)
signal discovery_found(discovery_data: Dictionary)
signal fleet_encountered(fleet_data: Dictionary)
signal sea_hazard_triggered(hazard_data: Dictionary)
signal status_message(msg: String)

const VIEW_TILES_X: int = 28
const VIEW_TILES_Y: int = 21
const TILE_SIZE: int = 16

const DIR_VECTORS: Array[Vector2i] = [
	Vector2i(0, -1),  # 0: N (북)
	Vector2i(1, -1),  # 1: NE (북동)
	Vector2i(1, 0),   # 2: E (동)
	Vector2i(1, 1),   # 3: SE (남동)
	Vector2i(0, 1),   # 4: S (남)
	Vector2i(-1, 1),  # 5: SW (남서)
	Vector2i(-1, 0),  # 6: W (서)
	Vector2i(-1, -1), # 7: NW (북서)
]

const DIR_NAMES_KR: Array[String] = ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]

# Map DIR_VECTORS index (0..7) to the 32x32 ship sprite column in worldmap_ships.png:
# In DATA1.lzw[11] second half (cols=8 of 32x32):
# Row 0: [NW_0, NW_1, NE_0, NE_1, SW_0, SW_1, SE_0, SE_1]
# Row 1: [N_0,  N_1,  W_0,  W_1,  S_0,  S_1,  E_0,  E_1]
const DIR_TO_SPRITE_CELL: Array[Vector2i] = [
	Vector2i(0, 1), # 0: N
	Vector2i(2, 0), # 1: NE
	Vector2i(6, 1), # 2: E
	Vector2i(6, 0), # 3: SE
	Vector2i(4, 1), # 4: S
	Vector2i(4, 0), # 5: SW
	Vector2i(2, 1), # 6: W
	Vector2i(0, 0), # 7: NW
]

var sail_timer: float = 0.0
var is_anchored: bool = false
var anim_frame: int = 0
var is_modal_open: bool = false


func activate_at_port(port_id: int) -> void:
	var p := GameData.get_port(port_id)
	var wx: int = int(p.get("world_x", 120))
	var wy: int = int(p.get("world_y", 358))
	# Spawn on an adjacent water tile if possible so the ship is ready to sail
	GameData.world_tile_x = wx
	GameData.world_tile_y = wy
	for d in range(8):
		var v := DIR_VECTORS[d]
		var tx := posmod(wx + v.x, GameData.WORLD_W)
		var ty := clampi(wy + v.y, 0, GameData.WORLD_H - 1)
		if GameData.is_world_tile_sailable(GameData.get_world_tile(tx, ty)):
			GameData.world_tile_x = tx
			GameData.world_tile_y = ty
			GameData.ship_heading = d
			break
	is_anchored = false
	queue_redraw()


func _process(delta: float) -> void:
	if is_modal_open:
		return

	if sail_timer > 0.0:
		sail_timer -= delta
		return

	var moved_dir := -1
	var up := Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
	var down := Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
	var left := Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
	var right := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)

	if up and right:
		moved_dir = 1
	elif down and right:
		moved_dir = 3
	elif down and left:
		moved_dir = 5
	elif up and left:
		moved_dir = 7
	elif up:
		moved_dir = 0
	elif right:
		moved_dir = 2
	elif down:
		moved_dir = 4
	elif left:
		moved_dir = 6

	if moved_dir != -1:
		GameData.ship_heading = moved_dir
		_step_ship(moved_dir)
		sail_timer = 0.12


func _unhandled_input(event: InputEvent) -> void:
	if is_modal_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_Z]:
			_inspect_or_dock_nearby()


func _step_ship(dir_idx: int) -> void:
	var vec := DIR_VECTORS[dir_idx]
	var nx := posmod(GameData.world_tile_x + vec.x, GameData.WORLD_W)
	var ny := clampi(GameData.world_tile_y + vec.y, 1, GameData.WORLD_H - 2)
	anim_frame = 1 - anim_frame

	# Check if stepping directly onto a port coordinate
	var pid := GameData.find_port_at_world_pos(nx, ny, 1)
	if pid != -1:
		GameData.world_tile_x = nx
		GameData.world_tile_y = ny
		GameData.current_port_id = pid
		queue_redraw()
		port_docked.emit(pid)
		return

	var tid := GameData.get_world_tile(nx, ny)
	if GameData.is_world_tile_sailable(tid):
		GameData.world_tile_x = nx
		GameData.world_tile_y = ny
		GameData.advance_hours(4)
		GameData.step_ai_fleets()
		_consume_daily_supplies()

		# Check if an AI fleet is on the same tile
		var hit_fleet := GameData.find_ai_fleet_near_world_pos(nx, ny, 0)
		if not hit_fleet.is_empty():
			fleet_encountered.emit(hit_fleet)
			queue_redraw()
			return

		# Check if stepping into a MONSTER.DAT sea monster coordinate
		var mon := GameData.find_monster_near_world_pos(nx, ny, 2)
		if not mon.is_empty():
			sea_hazard_triggered.emit({
				"hazard_type": "monster",
				"title": "바다 괴물 출현 — %s" % mon["name"],
				"message": "%s\n\n%s" % [mon["message_1"], mon["message_2"]],
				"hull_damage": 12,
				"crew_loss": 3
			})

		queue_redraw()
	else:
		# Check if there is a discovery on this coastline
		var disc := GameData.find_discovery_near_world_pos(nx, ny, 3)
		if not disc.is_empty():
			discovery_found.emit(disc)
		else:
			status_message.emit("암초/육지입니다! [Space/Enter] 키로 주변 항구 입항, 타 함대 교전 또는 상륙 탐색이 가능합니다.")
		queue_redraw()


func _consume_daily_supplies() -> void:
	if GameData.hour_of_day < 4 and not GameData.fleet_ships.is_empty():
		GameData.sailing_days_at_sea += 1
		var ship: Dictionary = GameData.fleet_ships[0]
		if ship["food"] > 0 and (GameData.day % 2 == 0):
			ship["food"] = maxi(0, ship["food"] - 1)
		if ship["water"] > 0 and (GameData.day % 2 == 1):
			ship["water"] = maxi(0, ship["water"] - 1)

		# Authentic sea hazards: Storm, Rats, Scurvy
		if GameData.is_storm_active:
			GameData.is_storm_active = false
			var storm_end_msg: String = GameData.system_messages[1111] if GameData.system_messages.size() > 1111 else "폭풍이 그쳤다."
			status_message.emit("[color=#77ddff]%s[/color]" % storm_end_msg)
		elif (GameData.sailing_days_at_sea % 14 == 7):
			GameData.is_storm_active = true
			ship["hull"] = maxi(10, int(ship["hull"]) - 15)
			var storm_msg: String = GameData.system_messages[357] if GameData.system_messages.size() > 357 else "폭풍우입니다! 키가 전혀 안 듣습니다!"
			sea_hazard_triggered.emit({
				"hazard_type": "storm",
				"title": "해상 폭풍우 조우!",
				"message": storm_msg + "\n\n거센 폭풍우로 인해 기함의 선체 내구도가 15 감소했습니다!",
				"hull_damage": 0,
				"crew_loss": 0
			})
		elif (GameData.sailing_days_at_sea % 19 == 11) and int(ship["food"]) > 5:
			ship["food"] = maxi(0, int(ship["food"]) - 5)
			var rat_msg: String = GameData.system_messages[478] if GameData.system_messages.size() > 478 else "제독님. 쥐떼가 발생하고 있는 모양입니다."
			sea_hazard_triggered.emit({
				"hazard_type": "rats",
				"title": "선내 쥐떼 발생!",
				"message": rat_msg + "\n\n창고의 식량 5일분이 쥐떼에게 갉아먹혔습니다!",
				"hull_damage": 0,
				"crew_loss": 0
			})
		elif (GameData.sailing_days_at_sea >= 25 and GameData.sailing_days_at_sea % 15 == 0):
			ship["crew"] = maxi(5, int(ship["crew"]) - 4)
			var scurvy_msg: String = GameData.system_messages[479] if GameData.system_messages.size() > 479 else "제독님. 선원 중에 괴혈병에 걸린 자가 있는 모양입니다."
			sea_hazard_triggered.emit({
				"hazard_type": "scurvy",
				"title": "선원 괴혈병 발생!",
				"message": scurvy_msg + "\n\n장기 항해로 인한 괴혈병으로 선원 4명이 쓰러졌습니다!",
				"hull_damage": 0,
				"crew_loss": 0
			})


func _inspect_or_dock_nearby() -> void:
	var pid := GameData.find_port_at_world_pos(GameData.world_tile_x, GameData.world_tile_y, 2)
	if pid != -1:
		GameData.current_port_id = pid
		port_docked.emit(pid)
		return

	var near_fleet := GameData.find_ai_fleet_near_world_pos(GameData.world_tile_x, GameData.world_tile_y, 3)
	if not near_fleet.is_empty():
		fleet_encountered.emit(near_fleet)
		return

	var disc := GameData.find_discovery_near_world_pos(GameData.world_tile_x, GameData.world_tile_y, 4)
	if not disc.is_empty():
		discovery_found.emit(disc)
		return

	status_message.emit("주변에 항구, 타 함대 또는 발견물이 없습니다. (현재 좌표: %d, %d)" % [GameData.world_tile_x, GameData.world_tile_y])


func _draw() -> void:
	var tod_key := GameData.get_time_of_day_key()
	var tileset_tex: Texture2D = GameData.worldmap_tileset_textures.get(tod_key)
	if tileset_tex == null:
		return

	var cam_x := GameData.world_tile_x - VIEW_TILES_X / 2
	var cam_y := clampi(GameData.world_tile_y - VIEW_TILES_Y / 2, 0, GameData.WORLD_H - VIEW_TILES_Y)

	# 1. Draw 28x21 viewport of 16x16 autotiled World Map tiles (448 x 336 pixels)
	for vy in range(VIEW_TILES_Y):
		var wy := cam_y + vy
		for vx in range(VIEW_TILES_X):
			var wx := posmod(cam_x + vx, GameData.WORLD_W)
			var tid := GameData.get_world_tile(wx, wy)
			# Ensure tile ID stays in 0..127 range of worldmap_tiles
			var safe_tid := tid & 0x7F
			var src_rect := Rect2((safe_tid % 16) * 16, (safe_tid / 16) * 16, 16, 16)
			var dst_rect := Rect2(vx * 16, vy * 16, 16, 16)
			draw_texture_rect_region(tileset_tex, dst_rect, src_rect)

	# 2. Highlight Ports within the visible viewport
	var font: Font = GameData.korean_font if GameData.korean_font != null else ThemeDB.fallback_font
	for p in GameData.ports:
		var px: int = int(p["world_x"])
		var py: int = int(p["world_y"])
		var rel_x := posmod(px - cam_x, GameData.WORLD_W)
		var rel_y := py - cam_y
		if rel_x >= 0 and rel_x < VIEW_TILES_X and rel_y >= 0 and rel_y < VIEW_TILES_Y:
			var screen_pos := Vector2(rel_x * 16, rel_y * 16)
			# Draw a glowing port beacon marker and Korean port name
			draw_rect(Rect2(screen_pos + Vector2(2, 2), Vector2(12, 12)), Color(1.0, 0.85, 0.2, 0.85), false, 2.0)
			draw_rect(Rect2(screen_pos + Vector2(-4, -14), Vector2(p["name"].length() * 11 + 8, 14)), Color(0, 0, 0, 0.75), true)
			draw_string(font, screen_pos + Vector2(0, -3), p["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.95, 0.4))

	# 3. Draw Visible AI Fleets (Merchant, Patrol, Pirate) on the World Map
	if GameData.ship_sprites_tex != null:
		for fl in GameData.ai_fleets:
			if int(fl.get("hull", 0)) <= 0 or int(fl.get("crew", 0)) <= 0:
				continue
			var fx: int = int(fl["world_x"])
			var fy: int = int(fl["world_y"])
			var rel_x := posmod(fx - cam_x, GameData.WORLD_W)
			var rel_y := fy - cam_y
			if rel_x >= 0 and rel_x < VIEW_TILES_X and rel_y >= 0 and rel_y < VIEW_TILES_Y:
				var f_cell := DIR_TO_SPRITE_CELL[int(fl.get("heading", 0)) % 8]
				var f_src := Rect2((f_cell.x + anim_frame) * 32, (f_cell.y + 2) * 32, 32, 32)
				var f_sx := rel_x * 16 - 8
				var f_sy := rel_y * 16 - 12
				draw_texture_rect_region(GameData.ship_sprites_tex, Rect2(f_sx, f_sy, 32, 32), f_src)
				var tag_color := Color(1.0, 0.45, 0.45) if fl.get("is_hostile", false) else Color(0.55, 0.9, 1.0)
				draw_string(font, Vector2(f_sx, f_sy - 2), str(fl.get("captain_name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tag_color)

	# 4. Draw 32x32 Player Fleet Ship Sprite centered at the player's world tile
	if GameData.ship_sprites_tex != null:
		var cell := DIR_TO_SPRITE_CELL[GameData.ship_heading % 8]
		var col := cell.x + anim_frame
		var row := cell.y
		var src_rect := Rect2(col * 32, row * 32, 32, 32)
		var ship_sx := (GameData.world_tile_x - cam_x) * 16 - 8
		var ship_sy := (GameData.world_tile_y - cam_y) * 16 - 12
		draw_texture_rect_region(GameData.ship_sprites_tex, Rect2(ship_sx, ship_sy, 32, 32), src_rect)
