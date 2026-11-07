extends Node2D
## Uncharted Waters 2 (대항해시대 2) - Port Exploration & Living Town NPC System
## Renders the 96x96 port map from PORTMAP.LZW using the regional PORTCHIP.LZW tileset,
## animates wandering town NPCs (citizens, sailors, guards, elders, dogs, navigators) from CHAR.LZW,
## and handles building entry & interactive NPC dialogue via authentic Koei mechanics.

signal request_sail_out(port_id: int)
signal building_entered(building_info: Dictionary)
signal npc_interacted(npc_info: Dictionary)

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

# Living Town NPC Wander System
var npcs: Array[Dictionary] = []


func setup_port(new_port_id: int) -> void:
	port_id = new_port_id
	port_data = GameData.get_port(port_id)
	map_bytes = GameData.get_port_map_bytes(port_id)
	walk_thresholds = port_data.get("walkability_thresholds", [0, 29, 34, 40])
	player_x = clampi(int(port_data.get("spawn_x", 48)), 2, MAP_W - 3)
	player_y = clampi(int(port_data.get("spawn_y", 48)), 2, MAP_H - 3)
	player_dir = 2
	_spawn_port_npcs()
	queue_redraw()


func _spawn_port_npcs() -> void:
	npcs.clear()
	if map_bytes.is_empty():
		return

	# Collect all candidate walkable tiles in the port
	var candidates: Array[Vector2i] = []
	for ty in range(8, MAP_H - 8):
		for tx in range(8, MAP_W - 8):
			if abs(tx - player_x) < 3 and abs(ty - player_y) < 3:
				continue
			if _is_tile_walkable(tx, ty) and _find_building_at_door(tx, ty).is_empty():
				candidates.append(Vector2i(tx, ty))

	if candidates.is_empty():
		return

	# Shuffle candidates deterministically or pseudo-randomly per port
	var rng := RandomNumberGenerator.new()
	rng.seed = port_id * 10007 + GameData.day * 37 + 1337

	# Pick 8 to 12 distinct positions
	var chosen_positions: Array[Vector2i] = []
	var attempts := 0
	while chosen_positions.size() < 10 and attempts < 100:
		attempts += 1
		var p: Vector2i = candidates[rng.randi() % candidates.size()]
		var too_close := false
		for ep in chosen_positions:
			if abs(ep.x - p.x) + abs(ep.y - p.y) < 4:
				too_close = true
				break
		if not too_close:
			chosen_positions.append(p)

	# NPC template definitions with authentic 90s Koei dialogue
	var templates: Array[Dictionary] = [
		{
			"type": "woman",
			"name": "마을 처녀",
			"tex_id": 6,
			"row_offset": 0,
			"has_dirs": true,
			"is_dog": false,
			"dialogues": [
				"리스본의 항구는 언제나 활기가 넘쳐요. 좋은 항해가 되시길 바랄게요!",
				"시장에는 신선한 올리브유와 포도주가 가득하답니다.",
				"바다 너머 신대륙에는 정말 황금의 도시가 존재할까요?",
				"출항하시기 전에 성당에서 기도를 올리면 신의 가호가 깃들 거예요."
			]
		},
		{
			"type": "sailor",
			"name": "베테랑 선원",
			"tex_id": 6,
			"row_offset": 4,
			"has_dirs": true,
			"is_dog": false,
			"dialogues": [
				"어이 선장! 선원이 모자라면 주점으로 가보쇼. 솜씨 좋은 뱃놈들이 대기 중이오!",
				"바다에서 괴혈병에 걸리면 라임 주스나 채소를 먹어야 해. 식량을 넉넉히 챙기라고!",
				"카라벨은 역풍에 강하지만 적재량이 적지. 원양 항해엔 나오나 갤리온이 최고야!",
				"폭풍우를 만나면 즉시 돛을 접어야 해. 안 그러면 마스트가 부러져 수장된다구!"
			]
		},
		{
			"type": "guard",
			"name": "항구 경비병",
			"tex_id": 6,
			"row_offset": 10,
			"has_dirs": false,
			"is_dog": false,
			"dialogues": [
				"여기는 국왕 폐하의 영지다. 밀수나 약탈 행위는 엄벌에 처한다!",
				"왕궁을 알현하려면 높은 공헌도와 신분이 필요하다.",
				"경비 임무 이상 무! 국왕 폐하 만세!"
			]
		},
		{
			"type": "elder",
			"name": "원로 학자",
			"tex_id": 6,
			"row_offset": 11,
			"has_dirs": false,
			"is_dog": false,
			"dialogues": [
				"세상은 둥글다네. 서쪽으로 계속 나아가면 동방의 황금향에 닿을 수 있지.",
				"세계의 유적과 진귀한 동식물을 발견하면 저택의 스폰서에게 보고하여 후원금을 받게나.",
				"항해자여, 별자리와 나침반을 벗 삼아 미지의 바다를 개척하게."
			]
		},
		{
			"type": "dog",
			"name": "항구 강아지",
			"tex_id": 6,
			"row_offset": 9,
			"has_dirs": false,
			"is_dog": true,
			"dialogues": [
				"멍멍! (선장님을 올려다보며 반갑게 꼬리를 세차게 흔든다)",
				"왈왈! (바다 쪽을 바라보며 신나게 발을 구른다)",
				"낑낑... (주점 문 앞을 기웃거리며 고기 냄새를 맡고 있다)"
			]
		},
		{
			"type": "navigator",
			"name": "방랑 항해사",
			"tex_id": (GameData.protagonist_id + 1) % 6,
			"row_offset": 0,
			"has_dirs": true,
			"is_dog": false,
			"dialogues": [
				"나도 한때는 대함대의 항해장이었지. 배를 몰 땐 조류를 타는 게 핵심이야.",
				"지도제작소에 항해 지도를 보고하면 막대한 명성과 계약금을 챙길 수 있소.",
				"최고의 배는 조선소의 공업 가치가 높아야 건조할 수 있는 법이라네."
			]
		},
		{
			"type": "woman",
			"name": "시장 상인 아가씨",
			"tex_id": 6,
			"row_offset": 0,
			"has_dirs": true,
			"is_dog": false,
			"dialogues": [
				"교역소의 시세는 수시로 변해요. 싸게 사서 비싸게 파는 게 무역의 기본이죠!",
				"항구에 투자하면 새로운 명산품이 개발되어 큰돈을 벌 수 있어요.",
				"조합에서 제시하는 운송 의뢰를 수행해보세요. 짭짤한 보수를 준답니다."
			]
		},
		{
			"type": "sailor",
			"name": "견습 수병",
			"tex_id": 6,
			"row_offset": 4,
			"has_dirs": true,
			"is_dog": false,
			"dialogues": [
				"언젠가는 나도 나만의 배를 타고 신세계를 탐험할 거야!",
				"적 함대를 마주쳤을 때 포격전과 백병전 중 어느 쪽이 유리한지 잘 판단해야 해.",
				"암시장에서는 밤에만 열리는 비밀스런 명검과 보물이 거래된다더군."
			]
		},
		{
			"type": "dog",
			"name": "누렁이",
			"tex_id": 6,
			"row_offset": 9,
			"has_dirs": false,
			"is_dog": true,
			"dialogues": [
				"멍! 멍! (선장님의 주변을 맴돌며 꼬리를 친다)",
				"킁킁... (선장님의 장화에서 묻은 바닷물 냄새를 맡는다)"
			]
		},
		{
			"type": "guard",
			"name": "순찰 경비병",
			"tex_id": 6,
			"row_offset": 10,
			"has_dirs": false,
			"is_dog": false,
			"dialogues": [
				"항내 치안은 평화롭다. 시민들에게 피해주지 않도록 조심하게.",
				"해적들이 항구 근해에 출몰한다는 소문이 있으니 무장을 철저히 하라."
			]
		}
	]

	for i in range(chosen_positions.size()):
		var pos: Vector2i = chosen_positions[i]
		var t: Dictionary = templates[i % templates.size()]
		var tex: Texture2D = GameData.char_sprite_textures.get(t["tex_id"])
		if tex == null:
			tex = GameData.char_sprite_textures.get(6)

		npcs.append({
			"id": i,
			"x": pos.x,
			"y": pos.y,
			"dir": rng.randi() % 4,
			"type": t["type"],
			"name": t["name"],
			"tex": tex,
			"row_offset": t["row_offset"],
			"has_dirs": t["has_dirs"],
			"is_dog": t["is_dog"],
			"anim_frame": rng.randi() % 2,
			"wander_timer": rng.randf_range(1.0, 3.0),
			"pause_timer": 0.0,
			"dialogues": t["dialogues"]
		})


func _process(delta: float) -> void:
	if is_modal_open:
		return

	# Update Living Town NPCs
	var npc_moved := false
	for npc in npcs:
		if npc["pause_timer"] > 0.0:
			npc["pause_timer"] -= delta
			continue

		npc["wander_timer"] -= delta
		if npc["wander_timer"] <= 0.0:
			var step_chance := 0.75 if npc["is_dog"] else 0.5
			if randf() < step_chance:
				var move_dir: int = randi() % 4
				var dx := 0
				var dy := 0
				match move_dir:
					0: dy = -1
					1: dx = 1
					2: dy = 1
					3: dx = -1

				var nx: int = npc["x"] + dx
				var ny: int = npc["y"] + dy

				if _is_tile_walkable(nx, ny) and (nx != player_x or ny != player_y) and _find_building_at_door(nx, ny).is_empty():
					# Check collision with other NPCs
					var blocked := false
					for other in npcs:
						if other["id"] != npc["id"] and other["x"] == nx and other["y"] == ny:
							blocked = true
							break
					if not blocked:
						npc["x"] = nx
						npc["y"] = ny
						npc["dir"] = move_dir
						npc["anim_frame"] = 1 - npc["anim_frame"]
						npc_moved = true

			var next_delay: float = randf_range(0.6, 1.5) if npc["is_dog"] else randf_range(1.5, 3.5)
			npc["wander_timer"] = next_delay

	if move_cooldown > 0.0:
		move_cooldown -= delta
		if npc_moved:
			queue_redraw()
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
	elif npc_moved:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_modal_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_Z]:
			# 1. Check for nearby building door
			var b := _find_nearby_building(player_x, player_y)
			if not b.is_empty():
				building_entered.emit(b)
				return

			# 2. Check for adjacent NPC interaction
			var adj_npc := _find_adjacent_npc(player_x, player_y)
			if not adj_npc.is_empty():
				_face_npc_toward(adj_npc, player_x, player_y)
				adj_npc["pause_timer"] = 4.0
				queue_redraw()
				npc_interacted.emit(adj_npc)
				return

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam_x := clampi(player_x - VIEW_TILES_X / 2, 0, MAP_W - VIEW_TILES_X)
		var cam_y := clampi(player_y - VIEW_TILES_Y / 2, 0, MAP_H - VIEW_TILES_Y)
		var click_tx := cam_x + int(event.position.x / 16.0)
		var click_ty := cam_y + int(event.position.y / 16.0)

		# Check if clicked on or near an NPC
		for npc in npcs:
			if abs(npc["x"] - click_tx) <= 1 and abs(npc["y"] - click_ty) <= 1:
				if abs(player_x - npc["x"]) + abs(player_y - npc["y"]) <= 4:
					_face_npc_toward(npc, player_x, player_y)
					npc["pause_timer"] = 4.0
					queue_redraw()
					npc_interacted.emit(npc)
					return


func _find_adjacent_npc(px: int, py: int) -> Dictionary:
	# First check directly in front of the player
	var fdx := 0
	var fdy := 0
	match player_dir:
		0: fdy = -1
		1: fdx = 1
		2: fdy = 1
		3: fdx = -1

	for npc in npcs:
		if npc["x"] == px + fdx and npc["y"] == py + fdy:
			return npc

	# Fallback: check 4-neighborhood
	for npc in npcs:
		if abs(npc["x"] - px) + abs(npc["y"] - py) == 1:
			return npc

	return {}


func _face_npc_toward(npc: Dictionary, target_x: int, target_y: int) -> void:
	if not npc.get("has_dirs", false):
		return
	var dx: int = target_x - int(npc["x"])
	var dy: int = target_y - int(npc["y"])
	if abs(dx) > abs(dy):
		npc["dir"] = 1 if dx > 0 else 3
	else:
		npc["dir"] = 2 if dy > 0 else 0


func _try_step(dx: int, dy: int) -> void:
	var nx := clampi(player_x + dx, 1, MAP_W - 2)
	var ny := clampi(player_y + dy, 1, MAP_H - 2)
	anim_frame = 1 - anim_frame

	# Check collision with NPCs
	for npc in npcs:
		if npc["x"] == nx and npc["y"] == ny:
			queue_redraw()
			return

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

	# 3. Y-Sorted Entity Rendering (Player + Living Town NPCs):
	# Row 0: North (Up), Row 1: East (Right), Row 2: South (Down), Row 3: West (Left)
	var entities: Array[Dictionary] = []

	# Player Character
	var char_tex: Texture2D = GameData.char_sprite_textures.get(GameData.protagonist_id)
	if char_tex != null:
		entities.append({
			"y": player_y,
			"screen_x": (player_x - cam_x) * 16 - 8,
			"screen_y": (player_y - cam_y) * 16 - 16,
			"tex": char_tex,
			"src_rect": Rect2(anim_frame * 32, player_dir * 32, 32, 32)
		})

	# Wandering Port NPCs
	for npc in npcs:
		var nx: int = npc["x"]
		var ny: int = npc["y"]
		var sx := (nx - cam_x) * 16 - 8
		var sy := (ny - cam_y) * 16 - 16
		if sx >= -32 and sx <= VIEW_TILES_X * 16 and sy >= -32 and sy <= VIEW_TILES_Y * 16:
			var src_y: int = npc["row_offset"] * 32
			if npc["has_dirs"]:
				src_y += int(npc["dir"]) * 32
			var src_x: int = int(npc["anim_frame"]) * 32
			entities.append({
				"y": ny,
				"screen_x": sx,
				"screen_y": sy,
				"tex": npc["tex"],
				"src_rect": Rect2(src_x, src_y, 32, 32)
			})

	# Sort by Y-coordinate for proper depth overlap
	entities.sort_custom(func(a, b): return a["y"] < b["y"])

	for ent in entities:
		draw_texture_rect_region(ent["tex"], Rect2(ent["screen_x"], ent["screen_y"], 32, 32), ent["src_rect"])

