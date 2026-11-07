extends Node
## Uncharted Waters 2 (대항해시대 2) - Global Game Data & State Singleton
## Loads extracted JSON tables and binary map archives from res://data/ and res://assets/

signal state_changed
signal log_message(msg: String)

const WORLD_W: int = 2160
const WORLD_H: int = 1080
const PORT_W: int = 96
const PORT_H: int = 96

# Static Databases
var ports: Array = []
var discoveries: Array = []
var characters: Array = []
var ships: Array = []
var items: Array = []
var scenarios: Dictionary = {}
var system_messages: Array = []
var monsters: Array = []
var palettes: Dictionary = {}
var hangul_font_map: Dictionary = {}

# Binary Map Buffers
var worldmap_grid: PackedByteArray = PackedByteArray()
var portmaps_bundle: PackedByteArray = PackedByteArray()
var windcur_data: PackedByteArray = PackedByteArray()

# Cached Textures, Graphics & Audio
var kao_large_atlas: Texture2D
var kao_small_atlas: Texture2D
var ship_sprites_tex: Texture2D
var hangul_font_tex: Texture2D
var korean_font: FontFile
var char_sprite_textures: Dictionary = {}
var port_tileset_textures: Dictionary = {}
var worldmap_tileset_textures: Dictionary = {}
var building_interior_textures: Dictionary = {}
var audio_streams: Dictionary = {}
var current_bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var is_audio_muted: bool = false
var current_bgm_key: String = ""

# Active Player & Fleet State
var protagonist_id: int = 0  # 0: 조안 페레로, 1: 카탈리나, 2: 오토, 3: 에르네스트, 4: 피에트로, 5: 알 베자스
var current_port_id: int = 0 # 0: 리스본
var world_tile_x: int = 120
var world_tile_y: int = 358
var ship_heading: int = 4    # 0:N, 1:NE, 2:E, 3:SE, 4:S, 5:SW, 6:W, 7:NW

var gold_ingots: int = 0
var gold_coins: int = 1000
var bank_deposit: int = 0
var bank_debt: int = 0

var year: int = 1522
var month: int = 5
var day: int = 17
var hour_of_day: int = 10    # 0..23

var fleet_ships: Array = [
	{
		"name": "헤르메스",
		"type_id": 2, # 경카라벨
		"hull": 120,
		"max_hull": 120,
		"crew": 30,
		"max_crew": 40,
		"food": 40,
		"water": 40,
		"cargo": {},
		"capacity": 100
	}
]

var discovered_ids: Array[int] = []
var owned_item_ids: Array[int] = [24] # 기본 망원경(ID 24) 보유
var companions: Array[int] = [0]
var scenario_chapter: int = 0
var scenario_subsection: int = 0
var scenario_flags: Dictionary = {}
var completed_triggers: Dictionary = {}
var ai_fleets: Array = []
var is_storm_active: bool = false
var sailing_days_at_sea: int = 0
var adventure_fame: int = 0
var piracy_fame: int = 0
var trade_fame: int = 0
var royal_rank: int = 0
var active_guild_quest: Dictionary = {}
var port_investments: Dictionary = {}
var royal_mission: Dictionary = {}
var waitress_affection: Dictionary = {}

const ROYAL_TITLES: Array = [
	"평민", "견습기사", "기사", "준남작", "남작", "자작", "백작", "후작", "공작"
]

const FIGUREHEAD_TYPES: Array = [
	{"name": "없음", "price": 0, "protection": 0},
	{"name": "돌고래상", "price": 500, "protection": 20},
	{"name": "성모상", "price": 1200, "protection": 45},
	{"name": "천사상", "price": 2500, "protection": 70},
	{"name": "용상", "price": 4000, "protection": 85},
	{"name": "여신상", "price": 8000, "protection": 99}
]

const CANNON_TYPES: Array = [
	{"name": "경 카로네이드", "power": 8, "range": 1, "price_per_gun": 15},
	{"name": "세이커포", "power": 12, "range": 2, "price_per_gun": 25},
	{"name": "데미 캘버린", "power": 16, "range": 2, "price_per_gun": 40},
	{"name": "컬버린포", "power": 22, "range": 3, "price_per_gun": 65},
	{"name": "캐넌포", "power": 30, "range": 2, "price_per_gun": 90},
	{"name": "중 캐넌포", "power": 40, "range": 3, "price_per_gun": 140}
]

# Standard Trade Goods for Market Simulation
const TRADE_GOODS: Array = [
	{"id": "cloves", "name": "정향", "category": "향신료", "base_price": 120},
	{"id": "cinnamon", "name": "계피", "category": "향신료", "base_price": 95},
	{"id": "pepper", "name": "후추", "category": "향신료", "base_price": 80},
	{"id": "nutmeg", "name": "육두구", "category": "향신료", "base_price": 130},
	{"id": "silk", "name": "생사", "category": "섬유", "base_price": 180},
	{"id": "velvet", "name": "벨벳", "category": "섬유", "base_price": 165},
	{"id": "cotton", "name": "면원단", "category": "섬유", "base_price": 35},
	{"id": "wool", "name": "양모", "category": "섬유", "base_price": 40},
	{"id": "wine", "name": "포도주", "category": "기호품", "base_price": 32},
	{"id": "olive_oil", "name": "올리브유", "category": "식료품", "base_price": 24},
	{"id": "sugar", "name": "설탕", "category": "식료품", "base_price": 45},
	{"id": "cheese", "name": "치즈", "category": "식료품", "base_price": 20},
	{"id": "grain", "name": "곡물", "category": "식료품", "base_price": 12},
	{"id": "porcelain", "name": "도자기", "category": "공예품", "base_price": 140},
	{"id": "glassware", "name": "유리제품", "category": "공예품", "base_price": 110},
	{"id": "coral", "name": "산호", "category": "보석", "base_price": 210},
	{"id": "ivory", "name": "상아", "category": "보석", "base_price": 240},
	{"id": "gold", "name": "금", "category": "귀금속", "base_price": 480},
	{"id": "silver", "name": "은", "category": "귀금속", "base_price": 220},
	{"id": "iron_ore", "name": "철광석", "category": "광물", "base_price": 48},
	{"id": "firearms", "name": "총포", "category": "무기", "base_price": 150},
]

# Starting Protagonists Setup (from MAIN.EXE scenario setup)
const PROTAGONIST_PRESETS: Array = [
	{
		"char_id": 0,
		"name": "조안 페레로",
		"title": "포르투갈의 젊은 모험가",
		"nation": "포르투갈",
		"start_port_id": 0, # 리스본
		"gold": 1000,
		"ship_name": "헤르메스",
		"ship_type_id": 5, # 카라벨 라티나
		"desc": "레온 페레로 공작의 아들. 아버지의 명에 따라 전설의 땅 프레스터 존의 왕국과 미지의 세계를 찾아 동료 로코 알렘켈과 함께 리스본에서 첫 출항에 나선다."
	},
	{
		"char_id": 1,
		"name": "카탈리나 에란초",
		"title": "복수를 맹세한 여해적",
		"nation": "에스파냐 (해적)",
		"start_port_id": 1, # 세빌리아
		"gold": 800,
		"ship_name": "산타 루치아",
		"ship_type_id": 9, # 카락
		"desc": "전 에스파냐 해군 장교. 오빠와 약혼자의 원수를 갚기 위해 해군 군함을 탈취하여 붉은 머리의 여해적으로 바다에 뛰어든다."
	},
	{
		"char_id": 2,
		"name": "오토 스피노라",
		"title": "잉글랜드 사략함대 지휘관",
		"nation": "영국",
		"start_port_id": 29, # 런던
		"gold": 1200,
		"ship_name": "인테구럴",
		"ship_type_id": 6, # 카라벨 레돈다
		"desc": "영국 국왕 헨리 8세의 밀명을 받은 기사. 무적함대 에스파냐의 해상 패권을 무너뜨리기 위해 런던에서 출항한다."
	},
	{
		"char_id": 3,
		"name": "에르네스트 로페스",
		"title": "완벽한 세계지도를 꿈꾸는 지리학자",
		"nation": "네덜란드",
		"start_port_id": 33, # 암스테르담
		"gold": 2000,
		"ship_name": "바스호",
		"ship_type_id": 12, # 핀네스
		"desc": "암스테르담 대학의 젊은 지리학 교수. 절친한 친구 메르카토르의 부탁을 받아 세계 전체의 정확한 해도를 작성하기 위해 항해에 나선다."
	},
	{
		"char_id": 4,
		"name": "피에트로 콘티",
		"title": "황금과 비보를 쫓는 모험가",
		"nation": "이탈리아",
		"start_port_id": 8, # 제노바
		"gold": 500,
		"ship_name": "세이렌",
		"ship_type_id": 5, # 카라벨 라티나
		"desc": "몰락한 제노바 상인 가문의 후계자. 가문의 막대한 빚을 갚고 세계 곳곳에 숨겨진 진귀한 보물과 발견물을 찾기 위해 모험을 떠난다."
	},
	{
		"char_id": 5,
		"name": "알 베자스",
		"title": "대상인을 꿈꾸는 오스만의 소년",
		"nation": "오스만 제국",
		"start_port_id": 2, # 이스탄불
		"gold": 300,
		"ship_name": "에르투룰",
		"ship_type_id": 1, # 한자 코그
		"desc": "이스탄불 빈민가에서 자란 야심찬 청년. 맨주먹과 작은 배 한 척으로 시작해 세계 제일의 거상이자 잃어버린 여동생을 찾기 위해 바다로 나간다."
	}
]


func _ready() -> void:
	_load_all_data()


func _load_all_data() -> void:
	ports = _load_json("res://data/ports.json")
	discoveries = _load_json("res://data/discoveries.json")
	characters = _load_json("res://data/characters.json")
	ships = _load_json("res://data/ships.json")
	items = _load_json("res://data/items.json")
	scenarios = _load_json("res://data/scenarios.json")
	system_messages = _load_json("res://data/messages.json")
	monsters = _load_json("res://data/monsters.json")
	palettes = _load_json("res://data/palettes.json")
	hangul_font_map = _load_json("res://data/hangul_font_map.json")

	worldmap_grid = FileAccess.get_file_as_bytes("res://data/worldmap_grid.bin")
	portmaps_bundle = FileAccess.get_file_as_bytes("res://data/portmaps_bundle.bin")
	windcur_data = FileAccess.get_file_as_bytes("res://data/windcur.bin")

	kao_large_atlas = _load_png_texture("res://assets/portraits/kao_large_atlas.png")
	kao_small_atlas = _load_png_texture("res://assets/portraits/kao_small_atlas.png")
	ship_sprites_tex = _load_png_texture("res://assets/sprites/worldmap_ships.png")
	hangul_font_tex = _load_png_texture("res://assets/fonts/all_font_16p_atlas.png")

	if ResourceLoader.exists("res://assets/fonts/korean_font.ttf"):
		korean_font = load("res://assets/fonts/korean_font.ttf") as FontFile
	elif FileAccess.file_exists("res://assets/fonts/korean_font.ttf"):
		korean_font = FontFile.new()
		korean_font.data = FileAccess.get_file_as_bytes("res://assets/fonts/korean_font.ttf")
	if korean_font != null:
		korean_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		korean_font.hinting = TextServer.HINTING_NORMAL
		korean_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	for i in range(7):
		char_sprite_textures[i] = _load_png_texture("res://assets/sprites/char_%d.png" % i)
		for tod in ["day", "dusk", "night"]:
			port_tileset_textures["%d_%s" % [i, tod]] = _load_png_texture(
				"res://assets/tilesets/port_tileset_%d_%s.png" % [i, tod]
			)

	for tod in ["day", "dawn", "dusk", "night", "storm"]:
		worldmap_tileset_textures[tod] = _load_png_texture(
			"res://assets/tilesets/worldmap_tiles_%s.png" % tod
		)

	# Load Building Interior Illustrations
	var interior_names := [
		"market", "tavern", "shipyard", "harbor", "inn", "palace",
		"guild", "mansion", "bank", "item_shop", "church", "fortune"
	]
	for iname in interior_names:
		var tex := _load_png_texture("res://assets/graphics/interior_%s.png" % iname)
		if tex != null:
			building_interior_textures[iname] = tex

	# Initialize Audio Players & CD Orchestra OST Soundtrack
	current_bgm_player = AudioStreamPlayer.new()
	add_child(current_bgm_player)
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)

	var bgm_names := [
		"title", "port", "sailing", "tavern", "battle", "palace",
		"storm", "inn", "port_arabia", "port_india", "port_eastasia", "ending"
	]
	for b_name in bgm_names:
		var mp3_path := "res://assets/audio/bgm_%s.mp3" % b_name
		if FileAccess.file_exists(mp3_path):
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(mp3_path)
			mp3.loop = true
			audio_streams["bgm_" + b_name] = mp3

	for s_name in ["cannon", "sword"]:
		var wav_path := "res://assets/audio/sfx_%s.wav" % s_name
		if FileAccess.file_exists(wav_path):
			var wav_bytes := FileAccess.get_file_as_bytes(wav_path)
			var wav := AudioStreamWAV.new()
			wav.data = wav_bytes.slice(44)
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = 22050
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
			audio_streams["sfx_" + s_name] = wav

	if FileAccess.file_exists("res://assets/audio/sfx_fanfare.mp3"):
		var fanfare := AudioStreamMP3.new()
		fanfare.data = FileAccess.get_file_as_bytes("res://assets/audio/sfx_fanfare.mp3")
		fanfare.loop = false
		audio_streams["sfx_fanfare"] = fanfare


func play_bgm(bgm_key: String) -> void:
	if is_audio_muted or current_bgm_player == null:
		return
	current_bgm_key = bgm_key
	var stream: AudioStream = audio_streams.get("bgm_" + bgm_key)
	if stream != null and current_bgm_player.stream != stream:
		current_bgm_player.stop()
		current_bgm_player.stream = stream
		current_bgm_player.play()


func stop_bgm() -> void:
	if current_bgm_player != null:
		current_bgm_player.stop()


func play_port_bgm(port_id: int) -> void:
	var p := get_port(port_id)
	var chip_no: int = int(p.get("chip_no", 0))
	match chip_no:
		3:
			play_bgm("port_arabia")
		4:
			play_bgm("port_india")
		5, 6:
			play_bgm("port_eastasia")
		_:
			play_bgm("port")


func play_sfx(sfx_key: String) -> void:
	if is_audio_muted or sfx_player == null:
		return
	var stream: AudioStream = audio_streams.get("sfx_" + sfx_key)
	if stream != null:
		sfx_player.stream = stream
		sfx_player.play()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON file: " + path)
		return []
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text)


func _load_png_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Empty PNG file: " + path)
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK or img.is_empty():
		push_error("Failed to load PNG buffer: " + path)
		return null
	return ImageTexture.create_from_image(img)


func start_new_game(protag_index: int) -> void:
	protagonist_id = clampi(protag_index, 0, PROTAGONIST_PRESETS.size() - 1)
	var preset: Dictionary = PROTAGONIST_PRESETS[protagonist_id]
	current_port_id = preset["start_port_id"]
	gold_coins = preset["gold"]
	gold_ingots = 0
	bank_deposit = 0
	bank_debt = 0
	year = 1522
	month = 5
	day = 17
	hour_of_day = 10

	var p_data := get_port(current_port_id)
	world_tile_x = int(p_data.get("world_x", 120))
	world_tile_y = int(p_data.get("world_y", 358))

	var ship_type := get_ship_type(preset["ship_type_id"])
	var max_h: int = int(ship_type.get("max_hull", 100))
	var max_c: int = int(ship_type.get("max_crew", 40))
	var cap: int = int(ship_type.get("capacity", 120))

	fleet_ships = [
		{
			"name": preset["ship_name"],
			"type_id": preset["ship_type_id"],
			"type_name": ship_type.get("name", "카라벨"),
			"hull": max_h,
			"max_hull": max_h,
			"crew": maxi(15, max_c / 2),
			"max_crew": max_c,
			"food": 35,
			"water": 35,
			"cargo": {},
			"capacity": cap
		}
	]
	companions = [protagonist_id]
	if protagonist_id == 0:
		companions.append(69) # 로코 알렘켈 (ID 69 = 0x45)
	scenario_chapter = 0
	scenario_subsection = 0
	scenario_flags.clear()
	completed_triggers.clear()
	is_storm_active = false
	sailing_days_at_sea = 0
	adventure_fame = 100
	piracy_fame = 100
	trade_fame = 100
	royal_rank = 0
	active_guild_quest.clear()
	port_investments.clear()
	_spawn_initial_ai_fleets()
	state_changed.emit()


func _spawn_initial_ai_fleets() -> void:
	## Spawns NPC fleets from MAIN.EXE characters[6..68] across major sea regions and near the player's starting port
	ai_fleets.clear()
	var start_p := get_port(current_port_id)
	var sx: int = int(start_p.get("world_x", 120))
	var sy: int = int(start_p.get("world_y", 358))

	for i in range(6, mini(69, characters.size())):
		var c: Dictionary = characters[i]
		var pid: int = int(c.get("initial_port_id", i % 40)) % 100
		var p := get_port(pid)
		var fx: int = int(p.get("world_x", sx))
		var fy: int = int(p.get("world_y", sy))
		# Place the first 4 fleets near the protagonist's starting waters so they are immediately visible!
		if i < 10:
			fx = sx + ((i - 6) * 3 - 4)
			fy = sy + ((i % 3) * 2 - 2)
		# Move to nearest sailable water tile
		for dy in range(-4, 5):
			var found := false
			for dx in range(-4, 5):
				var tx := posmod(fx + dx, WORLD_W)
				var ty := clampi(fy + dy, 2, WORLD_H - 3)
				if is_world_tile_sailable(get_world_tile(tx, ty)) and find_port_at_world_pos(tx, ty, 0) == -1:
					fx = tx
					fy = ty
					found = true
					break
			if found:
				break

		var is_pirate := (i >= 58) or (int(c.get("nation_id", 0)) == 6)
		var st_id := clampi(4 + (i % 14), 1, 20)
		var st := get_ship_type(st_id)
		ai_fleets.append({
			"fleet_id": i - 6,
			"captain_id": i,
			"captain_name": c.get("full_name", "함대#%d" % i),
			"portrait_id": int(c.get("portrait_id", 61)),
			"nation_id": int(c.get("nation_id", 0)),
			"nation_name": c.get("nation_name", "포르투갈"),
			"role": "해적함대" if is_pirate else ("초계함대" if (i % 2 == 0) else "상선대"),
			"is_hostile": is_pirate,
			"world_x": fx,
			"world_y": fy,
			"heading": i % 8,
			"ship_name": "%s 기함" % c.get("given_name", "갤리온"),
			"ship_type_id": st_id,
			"ship_type_name": st.get("name", "카라벨"),
			"hull": int(st.get("max_hull", 120)),
			"max_hull": int(st.get("max_hull", 120)),
			"crew": maxi(25, int(st.get("max_crew", 60)) * 2 / 3),
			"max_crew": int(st.get("max_crew", 60)),
			"guns": maxi(10, int(st.get("max_guns", 20))),
			"swordplay": int(c.get("stats", {}).get("swordplay", 70)),
			"gold": 400 + (i * 45)
		})


func step_ai_fleets() -> void:
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)
	]
	for fl in ai_fleets:
		var h: int = int(fl["heading"]) % 8
		var v := dirs[h]
		var nx := posmod(int(fl["world_x"]) + v.x, WORLD_W)
		var ny := clampi(int(fl["world_y"]) + v.y, 2, WORLD_H - 3)
		if is_world_tile_sailable(get_world_tile(nx, ny)) and find_port_at_world_pos(nx, ny, 0) == -1:
			fl["world_x"] = nx
			fl["world_y"] = ny
			if (int(fl["fleet_id"]) + hour_of_day) % 5 == 0:
				fl["heading"] = (h + 1) % 8
		else:
			fl["heading"] = (h + 3) % 8


func find_ai_fleet_near_world_pos(wx: int, wy: int, radius: int = 2) -> Dictionary:
	var wrapped_x := posmod(wx, WORLD_W)
	for fl in ai_fleets:
		if int(fl["hull"]) <= 0 or int(fl["crew"]) <= 0:
			continue
		var fx: int = int(fl["world_x"])
		var fy: int = int(fl["world_y"])
		if abs(fx - wrapped_x) <= radius and abs(fy - wy) <= radius:
			return fl
	return {}


func find_monster_near_world_pos(wx: int, wy: int, radius: int = 3) -> Dictionary:
	var wrapped_x := posmod(wx, WORLD_W)
	for m in monsters:
		var mx: int = int(m["world_x"])
		var my: int = int(m["world_y"])
		if abs(mx - wrapped_x) <= radius and abs(my - wy) <= radius:
			return m
	return {}


func get_port(port_id: int) -> Dictionary:
	if port_id >= 0 and port_id < ports.size():
		return ports[port_id]
	return ports[0]


func get_port_map_bytes(port_id: int) -> PackedByteArray:
	var p := get_port(port_id)
	var pm_idx: int = int(p.get("portmap_index", 0))
	var start: int = pm_idx * 9216
	if start + 9216 <= portmaps_bundle.size():
		return portmaps_bundle.slice(start, start + 9216)
	return PackedByteArray()


func get_world_tile(wx: int, wy: int) -> int:
	if worldmap_grid.is_empty():
		return 0
	var wrapped_x := posmod(wx, WORLD_W)
	var clamped_y := clampi(wy, 0, WORLD_H - 1)
	return worldmap_grid[clamped_y * WORLD_W + wrapped_x]


func is_world_tile_sailable(tile_id: int) -> bool:
	# Reverse-engineered from MAIN.EXE 0x39b93..0x39bc3:
	# Water tiles are 0x00, 0x41, 0x49, 0x51, 0x59, and port/harbor tiles 0x74..0x7f
	if tile_id == 0x00 or tile_id == 0x41 or tile_id == 0x49 or tile_id == 0x51 or tile_id == 0x59:
		return true
	if tile_id >= 0x74 and tile_id < 0x80:
		return true
	return false


func find_port_at_world_pos(wx: int, wy: int, radius: int = 1) -> int:
	var wrapped_x := posmod(wx, WORLD_W)
	for p in ports:
		var px: int = int(p["world_x"])
		var py: int = int(p["world_y"])
		if abs(px - wrapped_x) <= radius and abs(py - wy) <= radius:
			return int(p["id"])
	return -1


func find_discovery_near_world_pos(wx: int, wy: int, radius: int = 4) -> Dictionary:
	var wrapped_x := posmod(wx, WORLD_W)
	for d in discoveries:
		var dx: int = int(d["world_x"])
		var dy: int = int(d["world_y"])
		if abs(dx - wrapped_x) <= radius and abs(dy - wy) <= radius:
			return d
	return {}


func get_character(char_id: int) -> Dictionary:
	if char_id >= 0 and char_id < characters.size():
		return characters[char_id]
	return characters[0]


func get_ship_type(type_id: int) -> Dictionary:
	if type_id >= 0 and type_id < ships.size():
		return ships[type_id]
	return ships[0]


func get_portrait_atlas_texture(kao_id: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	if kao_id < 128:
		atlas.atlas = kao_large_atlas
		var col := kao_id % 16
		var row := kao_id / 16
		atlas.region = Rect2(col * 64, row * 80, 64, 80)
	else:
		var idx := (kao_id - 128) % 128
		atlas.atlas = kao_small_atlas
		var col := idx % 16
		var row := idx / 16
		atlas.region = Rect2(col * 48, row * 48, 48, 48)
	return atlas


func get_time_of_day_key() -> String:
	if is_storm_active:
		return "storm"
	if hour_of_day >= 5 and hour_of_day < 8:
		return "dawn"
	elif hour_of_day >= 8 and hour_of_day < 17:
		return "day"
	elif hour_of_day >= 17 and hour_of_day < 20:
		return "dusk"
	else:
		return "night"


func get_port_time_of_day_key() -> String:
	var tod := get_time_of_day_key()
	if tod == "dawn":
		return "dusk"
	return tod


func advance_hours(hours: int) -> void:
	hour_of_day += hours
	while hour_of_day >= 24:
		hour_of_day -= 24
		advance_days(1)
	state_changed.emit()


func advance_days(days: int) -> void:
	for _i in range(days):
		day += 1
		if day > 30:
			day = 1
			month += 1
			if month > 12:
				month = 1
				year += 1
	state_changed.emit()


func get_wind_and_current(wx: int, wy: int) -> Dictionary:
	# Sample regional wind & current from WINDCUR.DAT based on coordinates and season
	var is_winter := (month >= 11 or month <= 3)
	var gx := clampi(posmod(wx, WORLD_W) / 24, 0, 89)
	var gy := clampi(wy / 24, 0, 44)
	var cell_idx := gy * 90 + gx
	var wind_dir := (cell_idx + (3 if is_winter else 0)) % 8
	var wind_spd := 3 + ((cell_idx * 7) % 5)
	var cur_dir := (cell_idx + 2) % 8
	var cur_spd := 1 + (cell_idx % 3)
	if windcur_data.size() > cell_idx:
		var raw_b := windcur_data[cell_idx % windcur_data.size()]
		wind_dir = raw_b & 0x07
		wind_spd = 1 + ((raw_b >> 3) & 0x07)
		cur_dir = (raw_b >> 5) & 0x07
		cur_spd = 1 + ((raw_b >> 6) & 0x03)
	return {
		"wind_dir": wind_dir,
		"wind_speed": wind_spd,
		"current_dir": cur_dir,
		"current_speed": cur_spd
	}


func get_port_market_goods(port_id: int) -> Array:
	# Deterministic regional market inventory & pricing for each port
	var result: Array = []
	var p := get_port(port_id)
	var chip_no: int = int(p.get("chip_no", 0))
	for i in range(6):
		var g_idx := (port_id * 3 + i * 5 + chip_no * 2) % TRADE_GOODS.size()
		var good: Dictionary = TRADE_GOODS[g_idx].duplicate()
		var price_mod := 0.75 + float((port_id * 7 + g_idx * 13) % 55) / 100.0
		good["buy_price"] = maxi(5, int(round(good["base_price"] * price_mod)))
		good["sell_price"] = maxi(3, int(round(good["buy_price"] * 0.85)))
		result.append(good)
	return result


# ==============================================================================
# Scenario & Event Engine (Reverse-Engineered from SNR0..6.DAT + SNR0..6.MES)
# ==============================================================================
func get_active_scenario() -> Dictionary:
	var snr_key := str(protagonist_id + 1)
	if scenarios.has(snr_key):
		return scenarios[snr_key]
	return {}


func format_scenario_text(raw_text: String) -> String:
	var c := get_character(protagonist_id)
	var given_name: String = c.get("given_name", "조안")
	var surname: String = c.get("surname", "페레로")
	if surname.is_empty():
		surname = given_name
	var txt := raw_text.replace("$n", given_name).replace("$s", surname)
	# Highlight speaker header §Speaker§ in gold BBCode
	var first_sec := txt.find("§")
	if first_sec != -1:
		var second_sec := txt.find("§", first_sec + 1)
		if second_sec != -1:
			var spk := txt.substr(first_sec + 1, second_sec - first_sec - 1)
			txt = "[color=#ffd866][b]【%s】[/b][/color]" % spk + txt.substr(second_sec + 1)
	return txt


func find_matching_scenario_trigger(port_id: int, building_slot: int) -> Dictionary:
	var snr := get_active_scenario()
	if snr.is_empty():
		return {}
	var chaps: Array = snr.get("chapters", [])
	if scenario_chapter < 0 or scenario_chapter >= chaps.size():
		return {}
	var chap: Dictionary = chaps[scenario_chapter]
	var subs: Array = chap.get("subsections", [])
	if scenario_subsection < 0 or scenario_subsection >= subs.size():
		return {}
	var sub: Dictionary = subs[scenario_subsection]
	var trigs: Array = sub.get("triggers", [])
	var home_port_id: int = int(PROTAGONIST_PRESETS[protagonist_id]["start_port_id"])

	# 1. Exact port_id + building_slot match first, then 0xA0/0xA3 wildcard port
	for pass_idx in range(2):
		for t in trigs:
			var t_pid: int = int(t["port_id"])
			var t_slot: int = int(t["building_slot"])
			var slot_matches := (t_slot == building_slot) or (t_slot == 0x15 and building_slot == 5 and (hour_of_day >= 20 or hour_of_day < 5))
			if not slot_matches:
				continue
			if pass_idx == 0 and t_pid == port_id:
				return t
			elif pass_idx == 1 and ((t_pid == 0xA0 and port_id == home_port_id and t_slot >= 3) or t_pid == 0xA3):
				return t
	return {}


func find_departure_scenario_trigger(port_id: int) -> Dictionary:
	var snr := get_active_scenario()
	if snr.is_empty():
		return {}
	var chaps: Array = snr.get("chapters", [])
	if scenario_chapter < 0 or scenario_chapter >= chaps.size():
		return {}
	var subs: Array = chaps[scenario_chapter].get("subsections", [])
	if scenario_subsection < 0 or scenario_subsection >= subs.size():
		return {}
	var trigs: Array = subs[scenario_subsection].get("triggers", [])
	var home_port_id: int = int(PROTAGONIST_PRESETS[protagonist_id]["start_port_id"])
	if port_id != home_port_id:
		return {}
	for t in trigs:
		if int(t["port_id"]) == 0xA0 and int(t["building_slot"]) == 0x01:
			return t
	return {}


func execute_scenario_trigger(trig: Dictionary, choice_overrides: Dictionary = {}) -> Dictionary:
	## Executes the actual SNDT bytecode for `trig` inside the current subsection's bytecode buffer.
	## Evaluates flag conditions (0xAC jump if nonzero, 0xAD jump if zero), time-of-day (0x0F 01 07 + 0x8E/0x8F),
	## choice prompts (0xC9, 0xE9), and applies rewards (0xFA ship, 0xFB companion, 0xDC+0x1D item, 0xE6/0xE7 gold),
	## and chapter/subsection advances (0xF0, 0xF1).
	var snr := get_active_scenario()
	if snr.is_empty() or trig.is_empty():
		return {"executed": false, "dialogues": [], "rewards": [], "choices": []}
	var lines: Array = snr.get("lines", [])
	var chaps: Array = snr.get("chapters", [])
	if scenario_chapter < 0 or scenario_chapter >= chaps.size():
		return {"executed": false, "dialogues": [], "rewards": [], "choices": []}
	var subs: Array = chaps[scenario_chapter].get("subsections", [])
	if scenario_subsection < 0 or scenario_subsection >= subs.size():
		return {"executed": false, "dialogues": [], "rewards": [], "choices": []}
	var sub: Dictionary = subs[scenario_subsection]
	var hex_str: String = str(sub.get("sub_bytes_hex", ""))
	if hex_str.is_empty():
		return {"executed": false, "dialogues": [], "rewards": [], "choices": []}

	var sub_bytes := hex_str.hex_decode()
	var pc: int = int(trig.get("rel_offset", 0))
	var regs: Dictionary = {}
	var last_dc: Array = []
	var out_dialogues: Array = []
	var out_rewards: Array = []
	var out_choices: Array = []
	var cur_speaker: int = 0
	var steps: int = 0
	var blocked_Standard_menu: bool = false
	var hour_3x: int = hour_of_day * 3 # In UW2, time-of-day var 7 is 0..71 (hour * 3; 22:00 = 66 = 0x42)

	while pc >= 0 and pc < sub_bytes.size() and steps < 600:
		steps += 1
		var op: int = sub_bytes[pc]
		if op == 0xF2:
			break
		elif op == 0xF8:
			blocked_Standard_menu = true
			pc += 1
			break
		elif op == 0xF0:
			# Advance to next subsection
			if scenario_subsection + 1 < subs.size():
				scenario_subsection += 1
			elif scenario_chapter + 1 < chaps.size():
				scenario_chapter += 1
				scenario_subsection = 0
			out_rewards.append("시나리오 다음 절(Sub #%d)로 진행" % scenario_subsection)
			pc += 1
		elif op == 0xF1:
			# Advance to next chapter
			if scenario_chapter + 1 < chaps.size():
				scenario_chapter += 1
				scenario_subsection = 0
			scenario_flags.clear()
			out_rewards.append("시나리오 다음 장(Chapter #%d)으로 진행!" % scenario_chapter)
			pc += 1
		elif op in [0xC7, 0xC4, 0xC3]:
			pc += 1
		elif op == 0xC0 and pc + 1 < sub_bytes.size():
			if sub_bytes[pc + 1] == 0x00:
				cur_speaker = 0
			pc += 2
		elif op == 0xCC and pc + 2 < sub_bytes.size():
			cur_speaker = (sub_bytes[pc + 1] << 8) | sub_bytes[pc + 2]
			pc += 3
		elif op == 0xC8 and pc + 2 < sub_bytes.size():
			var mid: int = (sub_bytes[pc + 1] << 8) | sub_bytes[pc + 2]
			if mid >= 0 and mid < lines.size():
				out_dialogues.append({
					"msg_id": mid,
					"speaker_code": cur_speaker,
					"text": str(lines[mid])
				})
			pc += 3
		elif op == 0x2C and pc + 2 < sub_bytes.size():
			var f_idx: int = sub_bytes[pc + 1]
			var f_val: int = sub_bytes[pc + 2]
			scenario_flags[f_idx] = f_val
			pc += 3
		elif op == 0xAC and pc + 3 < sub_bytes.size():
			# Jump if scenario_flag[f] != 0
			var f_idx: int = sub_bytes[pc + 1]
			var dst: int = (sub_bytes[pc + 2] << 8) | sub_bytes[pc + 3]
			if int(scenario_flags.get(f_idx, 0)) != 0:
				pc = dst
			else:
				pc += 4
		elif op == 0xAD and pc + 3 < sub_bytes.size():
			# Jump if scenario_flag[f] == 0
			var f_idx: int = sub_bytes[pc + 1]
			var dst: int = (sub_bytes[pc + 2] << 8) | sub_bytes[pc + 3]
			if int(scenario_flags.get(f_idx, 0)) == 0:
				pc = dst
			else:
				pc += 4
		elif op == 0xFE and pc + 2 < sub_bytes.size():
			pc = (sub_bytes[pc + 1] << 8) | sub_bytes[pc + 2]
		elif op == 0x0C and pc + 3 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var imm16: int = (sub_bytes[pc + 2] << 8) | sub_bytes[pc + 3]
			regs[reg_id] = imm16
			pc += 4
		elif op == 0x0F and pc + 2 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var var_id: int = sub_bytes[pc + 2]
			if var_id == 0x07:
				regs[reg_id] = hour_3x
			elif var_id == 0x05:
				regs[reg_id] = current_port_id
			else:
				regs[reg_id] = 0
			pc += 3
		elif op == 0x8E and pc + 4 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var cmp_val: int = sub_bytes[pc + 2]
			var dst: int = (sub_bytes[pc + 3] << 8) | sub_bytes[pc + 4]
			if int(regs.get(reg_id, 0)) < cmp_val:
				pc = dst
			else:
				pc += 5
		elif op == 0x8F and pc + 4 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var cmp_val: int = sub_bytes[pc + 2]
			var dst: int = (sub_bytes[pc + 3] << 8) | sub_bytes[pc + 4]
			if int(regs.get(reg_id, 0)) > cmp_val:
				pc = dst
			else:
				pc += 5
		elif op in [0x8C, 0x8D, 0x80, 0x82] and pc + 4 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var cmp_val: int = sub_bytes[pc + 2]
			var dst: int = (sub_bytes[pc + 3] << 8) | sub_bytes[pc + 4]
			var rval: int = int(regs.get(reg_id, 0))
			var take_jump: bool = (rval != cmp_val) if op == 0x8C else (rval == cmp_val)
			if take_jump:
				pc = dst
			else:
				pc += 5
		elif op == 0xC9 and pc + 3 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var mid: int = (sub_bytes[pc + 2] << 8) | sub_bytes[pc + 3]
			var opt_str: String = str(lines[mid]) if (mid >= 0 and mid < lines.size()) else ""
			var opts := opt_str.split("\n", false)
			var chosen: int = int(choice_overrides.get(reg_id, 0))
			regs[reg_id] = chosen
			out_choices.append({"reg": reg_id, "options": opts, "selected": chosen})
			pc += 4
		elif op == 0xE9 and pc + 1 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var chosen: int = int(choice_overrides.get(reg_id, 0))
			regs[reg_id] = chosen
			out_choices.append({"reg": reg_id, "options": ["예", "아니오"], "selected": chosen})
			pc += 2
		elif op == 0xFA and pc + 3 < sub_bytes.size():
			var stype_id: int = sub_bytes[pc + 1]
			var name_mid: int = (sub_bytes[pc + 2] << 8) | sub_bytes[pc + 3]
			var sname: String = str(lines[name_mid]).strip_edges() if (name_mid >= 0 and name_mid < lines.size()) else "신조함"
			var st := get_ship_type(stype_id)
			var max_h: int = int(st.get("max_hull", 100))
			var max_c: int = int(st.get("max_crew", 40))
			var cap: int = int(st.get("capacity", 100))
			var new_ship := {
				"name": sname,
				"type_id": stype_id,
				"type_name": st.get("name", "카라벨"),
				"hull": max_h,
				"max_hull": max_h,
				"crew": maxi(15, max_c / 2),
				"max_crew": max_c,
				"food": 40,
				"water": 40,
				"cargo": {},
				"capacity": cap
			}
			if fleet_ships.is_empty():
				fleet_ships.append(new_ship)
			else:
				fleet_ships[0] = new_ship
			out_rewards.append("선박 획득: 『%s』 (%s)" % [sname, st.get("name", "")])
			pc += 4
		elif op == 0xFB and pc + 1 < sub_bytes.size():
			var comp_id: int = sub_bytes[pc + 1]
			if not companions.has(comp_id):
				companions.append(comp_id)
			var comp_name: String = get_character(comp_id).get("full_name", "항해사#%d" % comp_id)
			out_rewards.append("동료 합류: %s" % comp_name)
			pc += 2
		elif op in [0xE6, 0xE7] and pc + 1 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var amt: int = int(regs.get(reg_id, 1000))
			if amt <= 0:
				amt = 1000
			if op == 0xE6:
				gold_coins += amt
				out_rewards.append("금화 획득: +%d 닢" % amt)
			else:
				gold_coins = maxi(0, gold_coins - amt)
				out_rewards.append("금화 지불: -%d 닢" % amt)
			pc += 2
		elif op == 0xDC and pc + 4 < sub_bytes.size():
			last_dc = [sub_bytes[pc + 1], sub_bytes[pc + 2], sub_bytes[pc + 3], sub_bytes[pc + 4]]
			pc += 5
		elif op == 0x1D and pc + 2 < sub_bytes.size():
			var val: int = sub_bytes[pc + 2]
			if last_dc.size() == 4 and last_dc[1] == 0x06 and last_dc[3] == 0x3F:
				if not owned_item_ids.has(val):
					owned_item_ids.append(val)
				var iname: String = items[val]["name"] if (val >= 0 and val < items.size()) else ("아이템#%d" % val)
				out_rewards.append("아이템 획득: %s" % iname)
			pc += 3
		elif op == 0x1C and pc + 3 < sub_bytes.size():
			pc += 4
		elif op == 0xEB and pc + 3 < sub_bytes.size():
			var reg_id: int = sub_bytes[pc + 1]
			var hi: int = sub_bytes[pc + 3]
			regs[reg_id] = (day + hour_of_day) % maxi(1, hi)
			pc += 4
		elif op in [0xF9, 0x04, 0x05, 0x10, 0x11, 0x14, 0x18, 0x1F, 0x40, 0x4C, 0x4E, 0x4F, 0x6C, 0x6D]:
			pc += 3
		elif op in [0xCA, 0xEA, 0xD1, 0xD4]:
			pc += 2
		elif op == 0xCB and pc + 5 < sub_bytes.size():
			pc += 6
		else:
			pc += 1

	state_changed.emit()
	return {
		"executed": not out_dialogues.is_empty() or not out_rewards.is_empty(),
		"dialogues": out_dialogues,
		"rewards": out_rewards,
		"choices": out_choices,
		"blocked_standard_menu": blocked_Standard_menu
	}


# ==============================================================================
# Port Investments (상업 / 공업 투자 시스템)
# ==============================================================================
func get_port_investment(port_id: int) -> Dictionary:
	if not port_investments.has(port_id):
		port_investments[port_id] = {
			"commercial": 300,
			"industrial": 300,
			"invested_gold": 0
		}
	return port_investments[port_id]


func invest_port(port_id: int, invest_type: String, amount: int) -> Dictionary:
	if gold_coins < amount:
		return {"success": false, "reason": "금화가 부족합니다."}
	gold_coins -= amount
	var inv: Dictionary = get_port_investment(port_id)
	var gain := maxi(5, amount / 50)
	if invest_type == "commercial":
		inv["commercial"] = mini(1000, int(inv["commercial"]) + gain)
		trade_fame += gain * 2
	else:
		inv["industrial"] = mini(1000, int(inv["industrial"]) + gain)
		adventure_fame += gain * 2
	inv["invested_gold"] = int(inv.get("invested_gold", 0)) + amount
	state_changed.emit()
	return {
		"success": true,
		"type": invest_type,
		"gain": gain,
		"current_commercial": inv["commercial"],
		"current_industrial": inv["industrial"]
	}


# ==============================================================================
# Guild Quests (조합 업무알선: 배송, 교역품조달, 빚독촉, 해적퇴치)
# ==============================================================================
func generate_guild_quest(from_port_id: int) -> Dictionary:
	var q_types := ["delivery", "procure", "debt", "pirate"]
	var q_type: String = q_types[(from_port_id + day + month) % q_types.size()]
	var target_port_id := (from_port_id + 7) % mini(ports.size(), 40)
	if target_port_id == from_port_id:
		target_port_id = (from_port_id + 1) % ports.size()
	var t_port := get_port(target_port_id)
	var t_pname: String = t_port.get("name", "지중해 항구")

	match q_type:
		"delivery":
			var reward := 800 + ((from_port_id * 31) % 600)
			return {
				"type": "delivery",
				"title": "길드 비밀문서 및 특수 화물 배송",
				"desc": "목적지 [b]%s[/b]의 조합으로 중요한 문서를 안전하게 배송해 주십시오." % t_pname,
				"target_port_id": target_port_id,
				"target_port_name": t_pname,
				"reward_gold": reward,
				"fame_type": "adventure",
				"fame_reward": 150,
				"limit_days": 45,
				"start_day": day,
				"start_month": month,
				"start_year": year
			}
		"procure":
			var good_idx := (from_port_id * 3) % TRADE_GOODS.size()
			var good: Dictionary = TRADE_GOODS[good_idx]
			var req_qty := 10
			var reward := (int(good["base_price"]) * req_qty * 2) + 400
			return {
				"type": "procure",
				"title": "긴급 교역품 조달 의뢰",
				"desc": "길드 고객이 [b]%s[/b] %d개를 급히 구하고 있습니다. 조달해 주십시오." % [good["name"], req_qty],
				"target_port_id": from_port_id,
				"target_port_name": get_port(from_port_id).get("name", "현재 항구"),
				"req_item": good["name"],
				"req_qty": req_qty,
				"reward_gold": reward,
				"fame_type": "trade",
				"fame_reward": 200,
				"limit_days": 60,
				"start_day": day,
				"start_month": month,
				"start_year": year
			}
		"debt":
			var debtor_names := ["페드로", "미겔", "곤잘레스", "하산", "조반니", "루카스"]
			var d_name: String = debtor_names[(from_port_id * 5) % debtor_names.size()]
			var debt_amt := 2000
			var fee := 700
			return {
				"type": "debt",
				"title": "악질 채무자 빚 독촉 의뢰",
				"desc": "[b]%s[/b]의 주점에 숨어 있는 채무자 '%s'에게서 빚 %d닢을 회수해 주십시오." % [t_pname, d_name, debt_amt],
				"target_port_id": target_port_id,
				"target_port_name": t_pname,
				"debtor_name": d_name,
				"debt_amount": debt_amt,
				"reward_gold": fee,
				"fame_type": "trade",
				"fame_reward": 180,
				"limit_days": 40,
				"collected": false,
				"start_day": day,
				"start_month": month,
				"start_year": year
			}
		"pirate":
			var pirate_captains := ["붉은 수염 하이레딘", "검은 수염 티치", "해적왕 드레이크", "애꾸눈 발바로사"]
			var p_cap: String = pirate_captains[(from_port_id * 7) % pirate_captains.size()]
			var bounty := 3500 + ((from_port_id * 97) % 1500)
			return {
				"type": "pirate",
				"title": "악명 높은 해적 토벌 현상금 수배",
				"desc": "[b]%s[/b] 인근 해역을 노략질하는 현상수배범 '%s'의 함대를 나포하거나 격침하십시오!" % [t_pname, p_cap],
				"target_port_id": target_port_id,
				"target_port_name": t_pname,
				"pirate_name": p_cap,
				"reward_gold": bounty,
				"fame_type": "piracy",
				"fame_reward": 400,
				"limit_days": 90,
				"defeated": false,
				"start_day": day,
				"start_month": month,
				"start_year": year
			}
	return {}


func accept_guild_quest(q: Dictionary) -> void:
	active_guild_quest = q.duplicate(true)
	state_changed.emit()


func check_guild_quest_completion(port_id: int) -> Dictionary:
	if active_guild_quest.is_empty():
		return {"can_complete": false, "reason": "수행 중인 조합 의뢰가 없습니다."}
	var q: Dictionary = active_guild_quest
	var q_type: String = str(q.get("type", ""))

	match q_type:
		"delivery":
			if port_id == int(q.get("target_port_id", -1)):
				var rew_g: int = int(q.get("reward_gold", 0))
				var rew_f: int = int(q.get("fame_reward", 0))
				gold_coins += rew_g
				adventure_fame += rew_f
				active_guild_quest.clear()
				state_changed.emit()
				return {"can_complete": true, "reward_gold": rew_g, "fame": rew_f, "msg": "배송을 완료하여 보수 %d닢과 모험 명성을 획득했습니다!" % rew_g}
			else:
				return {"can_complete": false, "reason": "이곳은 목적지 [%s]이(가) 아닙니다." % q.get("target_port_name", "")}
		"procure":
			var req_item: String = str(q.get("req_item", ""))
			var req_qty: int = int(q.get("req_qty", 0))
			var cargo: Dictionary = fleet_ships[0]["cargo"] if not fleet_ships.is_empty() else {}
			var owned: int = int(cargo.get(req_item, 0))
			if owned >= req_qty:
				cargo[req_item] = owned - req_qty
				if cargo[req_item] <= 0:
					cargo.erase(req_item)
				var rew_g: int = int(q.get("reward_gold", 0))
				var rew_f: int = int(q.get("fame_reward", 0))
				gold_coins += rew_g
				trade_fame += rew_f
				active_guild_quest.clear()
				state_changed.emit()
				return {"can_complete": true, "reward_gold": rew_g, "fame": rew_f, "msg": "교역품 [%s] %d개를 납품하여 보수 %d닢과 상업 명성을 획득했습니다!" % [req_item, req_qty, rew_g]}
			else:
				return {"can_complete": false, "reason": "적재함에 [%s]이(가) %d개 필요합니다 (현재 보유: %d개)." % [req_item, req_qty, owned]}
		"debt":
			if port_id == int(q.get("target_port_id", -1)) and not bool(q.get("collected", false)):
				# Collect from debtor at target tavern
				q["collected"] = true
				state_changed.emit()
				return {"can_complete": false, "debt_collected": true, "msg": "채무자 [%s]에게서 빚 %d닢을 성공적으로 회수했습니다! 의뢰를 발주한 조합으로 돌아가 보고하십시오." % [q.get("debtor_name", ""), int(q.get("debt_amount", 0))]}
			elif bool(q.get("collected", false)):
				var rew_g: int = int(q.get("reward_gold", 0))
				var rew_f: int = int(q.get("fame_reward", 0))
				gold_coins += rew_g
				trade_fame += rew_f
				active_guild_quest.clear()
				state_changed.emit()
				return {"can_complete": true, "reward_gold": rew_g, "fame": rew_f, "msg": "회수한 빚을 조합에 전달하고 수수료 %d닢과 상업 명성을 받았습니다!" % rew_g}
			else:
				return {"can_complete": false, "reason": "아직 채무자에게서 돈을 회수하지 못했습니다."}
		"pirate":
			if bool(q.get("defeated", false)) or randf() < 0.4:
				var rew_g: int = int(q.get("reward_gold", 0))
				var rew_f: int = int(q.get("fame_reward", 0))
				gold_coins += rew_g
				piracy_fame += rew_f
				active_guild_quest.clear()
				state_changed.emit()
				return {"can_complete": true, "reward_gold": rew_g, "fame": rew_f, "msg": "수배된 해적을 소탕하여 현상금 %d닢과 해적 명성을 획득했습니다!" % rew_g}
			else:
				return {"can_complete": false, "reason": "아직 수배된 해적 함대를 소탕하지 못했습니다."}

	return {"can_complete": false, "reason": "의뢰 조건을 만족하지 못했습니다."}


# ==============================================================================
# Royal Palace & Titles (왕궁 작위 체계 및 칙명)
# ==============================================================================
func check_royal_promotion() -> Dictionary:
	var total_fame := adventure_fame + trade_fame + piracy_fame
	var thresholds := [0, 1000, 3000, 6000, 12000, 20000, 35000, 55000, 80000]
	var new_rank := royal_rank
	for r in range(ROYAL_TITLES.size() - 1, -1, -1):
		if total_fame >= thresholds[r]:
			new_rank = r
			break
	if new_rank > royal_rank:
		var old_title: String = ROYAL_TITLES[royal_rank]
		royal_rank = new_rank
		var new_title: String = ROYAL_TITLES[royal_rank]
		state_changed.emit()
		return {
			"promoted": true,
			"rank": royal_rank,
			"old_title": old_title,
			"new_title": new_title,
			"msg": "축하합니다! 국왕 폐하께서 그대의 위대한 공적을 치하하여 작위를 [b]「%s」[/b](으)로 승급하셨습니다!" % new_title
		}
	return {"promoted": false, "rank": royal_rank, "title": ROYAL_TITLES[royal_rank]}


func generate_royal_mission() -> Dictionary:
	var target_port := get_port((current_port_id + 11) % ports.size())
	var pname: String = target_port.get("name", "원격 항구")
	royal_mission = {
		"title": "국왕 폐하의 비밀 칙명",
		"desc": "우호국과의 동맹 조약을 위해 [b]%s[/b]의 총독에게 친서를 전달하고 오라." % pname,
		"target_port_id": int(target_port.get("id", 1)),
		"target_port_name": pname,
		"reward_gold": 10000,
		"fame_reward": 1000
	}
	state_changed.emit()
	return royal_mission


func complete_royal_mission(port_id: int) -> Dictionary:
	if royal_mission.is_empty():
		return {"success": false, "reason": "하달받은 칙명이 없습니다."}
	if port_id == int(royal_mission.get("target_port_id", -1)):
		var r_gold: int = int(royal_mission.get("reward_gold", 5000))
		var r_fame: int = int(royal_mission.get("fame_reward", 800))
		gold_coins += r_gold
		adventure_fame += r_fame
		royal_mission.clear()
		check_royal_promotion()
		state_changed.emit()
		return {"success": true, "reward_gold": r_gold, "fame": r_fame, "msg": "칙명을 완수하여 국왕 폐하의 하사금 %d닢을 수령했습니다!" % r_gold}
	return {"success": false, "reason": "이곳은 칙명 목적지 [%s]이(가) 아닙니다." % royal_mission.get("target_port_name", "")}


# ==============================================================================
# Shipyard Remodeling (선박 개조: 선수상, 대포, 적재비율)
# ==============================================================================
func install_figurehead(fig_idx: int) -> Dictionary:
	if fig_idx < 0 or fig_idx >= FIGUREHEAD_TYPES.size():
		return {"success": false, "reason": "존재하지 않는 선수상입니다."}
	var fig: Dictionary = FIGUREHEAD_TYPES[fig_idx]
	var price: int = int(fig["price"])
	if gold_coins < price:
		return {"success": false, "reason": "선수상을 구매할 금화가 부족합니다."}
	gold_coins -= price
	if not fleet_ships.is_empty():
		fleet_ships[0]["figurehead"] = fig["name"]
		fleet_ships[0]["disaster_protection"] = fig["protection"]
	state_changed.emit()
	return {"success": true, "name": fig["name"], "protection": fig["protection"]}


func install_cannons(cannon_idx: int, count: int) -> Dictionary:
	if cannon_idx < 0 or cannon_idx >= CANNON_TYPES.size():
		return {"success": false, "reason": "존재하지 않는 대포 종류입니다."}
	var can: Dictionary = CANNON_TYPES[cannon_idx]
	var total_cost: int = int(can["price_per_gun"]) * count
	if gold_coins < total_cost:
		return {"success": false, "reason": "대포를 구매할 금화가 부족합니다."}
	gold_coins -= total_cost
	if not fleet_ships.is_empty():
		fleet_ships[0]["cannon_type"] = can["name"]
		fleet_ships[0]["cannon_power"] = can["power"]
		fleet_ships[0]["cannons"] = count
	state_changed.emit()
	return {"success": true, "name": can["name"], "count": count, "power": can["power"]}


# ==============================================================================
# Tavern Companions, Waitress, & Blackjack Mini-Game
# ==============================================================================
func get_hireable_companions(port_id: int) -> Array:
	var result: Array = []
	for i in range(7, mini(35, characters.size())):
		if not companions.has(i) and ((i + port_id) % 3 == 0):
			result.append(characters[i])
	return result


func hire_companion(char_id: int, wage: int = 300) -> bool:
	if gold_coins < wage or companions.has(char_id):
		return false
	gold_coins -= wage
	companions.append(char_id)
	state_changed.emit()
	return true


func interact_waitress(port_id: int, gift_cost: int = 0) -> Dictionary:
	var cur_aff: int = int(waitress_affection.get(port_id, 0))
	if gift_cost > 0:
		if gold_coins < gift_cost:
			return {"success": false, "reason": "선물을 살 금화가 부족합니다."}
		gold_coins -= gift_cost
		cur_aff += gift_cost / 10
		waitress_affection[port_id] = cur_aff
	
	var hint := ""
	if cur_aff >= 50:
		var disc: Dictionary = discoveries[(port_id * 5) % discoveries.size()]
		hint = "여급이 귓속말로 속삭입니다: \"선장님께만 알려드리는 건데요... 좌표 (%d, %d) 바다 어딘가에 '%s'이(가) 숨겨져 있대요!\"" % [
			int(disc["world_x"]), int(disc["world_y"]), disc["name"]
		]
	else:
		hint = "여급: \"선장님, 바다 이야기는 언제 들어도 흥미진진해요! 종종 들러주세요.\""
	state_changed.emit()
	return {"success": true, "affection": cur_aff, "hint": hint}


func play_blackjack(bet_amount: int) -> Dictionary:
	if gold_coins < bet_amount:
		return {"success": false, "reason": "베팅할 금화가 부족합니다."}
	gold_coins -= bet_amount
	# Draw cards (1..10)
	var p_cards := [randi_range(2, 10), randi_range(2, 11)]
	var d_cards := [randi_range(2, 10), randi_range(2, 11)]
	var p_sum: int = p_cards[0] + p_cards[1]
	var d_sum: int = d_cards[0] + d_cards[1]
	
	if p_sum < 16 and randf() > 0.4:
		var extra := randi_range(1, 10)
		p_cards.append(extra)
		p_sum += extra
	if d_sum < 17:
		var extra := randi_range(1, 10)
		d_cards.append(extra)
		d_sum += extra

	var won := false
	var tie := false
	if p_sum > 21:
		won = false
	elif d_sum > 21 or p_sum > d_sum:
		won = true
	elif p_sum == d_sum:
		tie = true

	var payout := 0
	var outcome_msg := ""
	if won:
		payout = bet_amount * 2
		gold_coins += payout
		outcome_msg = "승리! 딜러(%d)를 이기고 판돈의 2배인 %d닢을 획득했습니다!" % [d_sum, payout]
	elif tie:
		payout = bet_amount
		gold_coins += payout
		outcome_msg = "무승부! 점수(%d)가 같아 판돈 %d닢을 돌려받았습니다." % [p_sum, payout]
	else:
		outcome_msg = "패배! 딜러(%d)가 선장님(%d)보다 높습니다. %d닢을 잃었습니다." % [d_sum, p_sum, bet_amount]

	state_changed.emit()
	return {
		"success": true,
		"player_sum": p_sum,
		"dealer_sum": d_sum,
		"player_cards": p_cards,
		"dealer_cards": d_cards,
		"won": won,
		"payout": payout,
		"msg": outcome_msg
	}


# ==============================================================================
# Night Secret Shop (심야 02:00 ~ 03:00 암시장)
# ==============================================================================
func is_secret_shop_open() -> bool:
	return hour_of_day == 2


func get_secret_shop_items() -> Array:
	var rare_items: Array = []
	for it in items:
		var price: int = int(it.get("price", 0))
		var it_id: int = int(it.get("id", 0))
		if price >= 5000 or it_id in [1, 2, 4, 11, 15, 23, 27, 30, 40, 52]:
			rare_items.append(it)
	return rare_items


# ==============================================================================
# Save & Load System (JSON serialization to user://save_*.json)
# ==============================================================================
func get_save_path(slot: int) -> String:
	return "user://save_%d.json" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(get_save_path(slot))


func get_save_info(slot: int) -> Dictionary:
	var path := get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json_str := file.get_as_text()
	var parsed: Variant = JSON.parse_string(json_str)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func save_game(slot: int) -> bool:
	var path := get_save_path(slot)
	var save_dict: Dictionary = {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"protagonist_id": protagonist_id,
		"current_port_id": current_port_id,
		"world_tile_x": world_tile_x,
		"world_tile_y": world_tile_y,
		"ship_heading": ship_heading,
		"year": year,
		"month": month,
		"day": day,
		"hour_of_day": hour_of_day,
		"gold_coins": gold_coins,
		"bank_deposit": bank_deposit,
		"fleet_ships": fleet_ships,
		"companions": companions,
		"discovered_ids": discovered_ids,
		"owned_item_ids": owned_item_ids,
		"scenario_chapter": scenario_chapter,
		"scenario_subsection": scenario_subsection,
		"scenario_flags": scenario_flags,
		"adventure_fame": adventure_fame,
		"trade_fame": trade_fame,
		"piracy_fame": piracy_fame,
		"royal_rank": royal_rank,
		"active_guild_quest": active_guild_quest,
		"royal_mission": royal_mission,
		"port_investments": port_investments,
		"waitress_affection": waitress_affection
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(save_dict, "\t"))
	return true


func load_game(slot: int) -> bool:
	var data := get_save_info(slot)
	if data.is_empty():
		return false
	protagonist_id = int(data.get("protagonist_id", 0))
	current_port_id = int(data.get("current_port_id", 0))
	world_tile_x = int(data.get("world_tile_x", 120))
	world_tile_y = int(data.get("world_tile_y", 358))
	ship_heading = int(data.get("ship_heading", 4))
	year = int(data.get("year", 1522))
	month = int(data.get("month", 5))
	day = int(data.get("day", 17))
	hour_of_day = int(data.get("hour_of_day", 10))
	gold_coins = int(data.get("gold_coins", 1000))
	bank_deposit = int(data.get("bank_deposit", 0))
	fleet_ships = data.get("fleet_ships", fleet_ships)
	companions.assign(data.get("companions", [0]))
	discovered_ids.assign(data.get("discovered_ids", []))
	owned_item_ids.assign(data.get("owned_item_ids", []))
	scenario_chapter = int(data.get("scenario_chapter", 0))
	scenario_subsection = int(data.get("scenario_subsection", 0))
	scenario_flags = data.get("scenario_flags", {})
	adventure_fame = int(data.get("adventure_fame", 0))
	trade_fame = int(data.get("trade_fame", 0))
	piracy_fame = int(data.get("piracy_fame", 0))
	royal_rank = int(data.get("royal_rank", 0))
	active_guild_quest = data.get("active_guild_quest", {})
	royal_mission = data.get("royal_mission", {})
	port_investments = data.get("port_investments", {})
	waitress_affection = data.get("waitress_affection", {})
	state_changed.emit()
	return true



