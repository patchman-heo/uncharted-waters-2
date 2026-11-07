extends Control
## Uncharted Waters 2 (대항해시대 2) - Main Game Controller & Authentic Koei UI Layout
## Manages protagonist selection, Port Exploration View (448x336 left viewport),
## World Map Sailing View, Right-hand Koei Status Panel, Bottom Message Log, and Building Modal Dialogs.

const PortViewScript = preload("res://scripts/port_view.gd")
const WorldMapScript = preload("res://scripts/world_map.gd")

enum GameMode { TITLE_SELECT, PORT, WORLD_MAP }

var current_mode: GameMode = GameMode.TITLE_SELECT
var port_view: Node2D
var world_map_view: Node2D

# UI References
var viewport_frame: Control
var status_panel: PanelContainer
var protag_portrait_rect: TextureRect
var location_label: Label
var date_label: Label
var gold_label: Label
var fleet_label: Label
var wind_label: Label
var bottom_log_label: RichTextLabel
var modal_layer: PanelContainer
var modal_interior_rect: TextureRect
var modal_portrait: TextureRect
var modal_title: Label
var modal_body: RichTextLabel
var modal_prompt_label: Label
var modal_buttons_box: VBoxContainer
var title_overlay: PanelContainer
var typewriter_active: bool = false
var typewriter_elapsed: float = 0.0
var typewriter_speed: float = 0.02
var log_typewriter_active: bool = false
var log_typewriter_elapsed: float = 0.0

# Active Naval Battle & 1:1 Captain Duel State
var active_battle_enemy: Dictionary = {}
var battle_distance: int = 3 # 3: 원거리(포격), 2: 중거리(포격/접근), 1: 근거리(포격/육박돌격), 0: 백병전/일기토
var battle_turn: int = 1
var battle_log: String = ""
var duel_player_hp: int = 100
var duel_enemy_hp: int = 100
var duel_round: int = 1
var duel_is_player_attacking: bool = true
var duel_log: String = ""


func _ready() -> void:
	_build_ui()
	GameData.state_changed.connect(_refresh_hud)
	_show_title_screen()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if GameData.korean_font != null:
		var custom_theme := Theme.new()
		custom_theme.default_font = GameData.korean_font
		custom_theme.default_font_size = 12
		theme = custom_theme

	# Background base (classic DOS dark blue/black border)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.16, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 1. Left Map Viewport Container (448 x 336 at (8, 8))
	var map_border := Panel.new()
	map_border.position = Vector2(6, 6)
	map_border.size = Vector2(452, 340)
	add_child(map_border)

	viewport_frame = Control.new()
	viewport_frame.position = Vector2(8, 8)
	viewport_frame.size = Vector2(448, 336)
	viewport_frame.clip_contents = true
	add_child(viewport_frame)

	port_view = PortViewScript.new()
	port_view.building_entered.connect(_on_building_entered)
	port_view.npc_interacted.connect(_on_npc_interacted)
	viewport_frame.add_child(port_view)

	world_map_view = WorldMapScript.new()
	world_map_view.visible = false
	world_map_view.port_docked.connect(_on_port_docked)
	world_map_view.discovery_found.connect(_on_discovery_found)
	world_map_view.fleet_encountered.connect(_on_fleet_encountered)
	world_map_view.sea_hazard_triggered.connect(_on_sea_hazard_triggered)
	world_map_view.status_message.connect(_set_log_text)
	viewport_frame.add_child(world_map_view)

	# 2. Right Status Panel (x=464..634, y=6..346)
	status_panel = PanelContainer.new()
	status_panel.position = Vector2(464, 6)
	status_panel.size = Vector2(170, 340)
	add_child(status_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	status_panel.add_child(vbox)

	var top_hbox := HBoxContainer.new()
	vbox.add_child(top_hbox)

	protag_portrait_rect = TextureRect.new()
	protag_portrait_rect.custom_minimum_size = Vector2(64, 80)
	protag_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top_hbox.add_child(protag_portrait_rect)

	var meta_vbox := VBoxContainer.new()
	top_hbox.add_child(meta_vbox)

	location_label = Label.new()
	location_label.add_theme_font_size_override("font_size", 13)
	location_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	meta_vbox.add_child(location_label)

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(date_label)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 11)
	gold_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	vbox.add_child(gold_label)

	fleet_label = Label.new()
	fleet_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(fleet_label)

	wind_label = Label.new()
	wind_label.add_theme_font_size_override("font_size", 11)
	wind_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vbox.add_child(wind_label)

	# Quick Action Buttons on Right Panel
	var btn_grid := GridContainer.new()
	btn_grid.columns = 2
	vbox.add_child(btn_grid)

	_add_quick_btn(btn_grid, "인물정보", _show_character_sheet)
	_add_quick_btn(btn_grid, "함대/화물", _show_fleet_sheet)
	_add_quick_btn(btn_grid, "발견물도감", _show_discoveries_book)
	_add_quick_btn(btn_grid, "시나리오", _show_scenario_viewer)
	_add_quick_btn(btn_grid, "저장하기", _show_save_menu)
	_add_quick_btn(btn_grid, "불러오기", _show_load_menu)
	_add_quick_btn(btn_grid, "항구이동", _show_fast_travel_menu)
	_add_quick_btn(btn_grid, "주인공선택", _show_title_screen)

	# 3. Bottom Message Bar (x=6..634, y=350..394)
	var bottom_panel := PanelContainer.new()
	bottom_panel.position = Vector2(6, 350)
	bottom_panel.size = Vector2(628, 44)
	add_child(bottom_panel)

	bottom_log_label = RichTextLabel.new()
	bottom_log_label.bbcode_enabled = true
	bottom_log_label.scroll_active = false
	bottom_log_label.add_theme_font_size_override("normal_font_size", 12)
	bottom_panel.add_child(bottom_log_label)

	# 4. Modal Dialog Overlay (For Buildings, Market, Shipyard, Tavern, Discoveries)
	modal_layer = PanelContainer.new()
	modal_layer.position = Vector2(16, 16)
	modal_layer.size = Vector2(428, 320)
	modal_layer.visible = false
	add_child(modal_layer)

	var modal_hbox := HBoxContainer.new()
	modal_hbox.add_theme_constant_override("separation", 12)
	modal_layer.add_child(modal_hbox)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(136, 280)
	left_col.add_theme_constant_override("separation", 6)
	modal_hbox.add_child(left_col)

	modal_interior_rect = TextureRect.new()
	modal_interior_rect.custom_minimum_size = Vector2(136, 112)
	modal_interior_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	modal_interior_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	modal_interior_rect.visible = false
	left_col.add_child(modal_interior_rect)

	modal_portrait = TextureRect.new()
	modal_portrait.custom_minimum_size = Vector2(64, 80)
	modal_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	modal_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	modal_portrait.visible = true
	left_col.add_child(modal_portrait)

	modal_buttons_box = VBoxContainer.new()
	modal_buttons_box.custom_minimum_size = Vector2(136, 140)
	modal_buttons_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(modal_buttons_box)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_hbox.add_child(right_col)

	modal_title = Label.new()
	modal_title.add_theme_font_size_override("font_size", 14)
	modal_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	right_col.add_child(modal_title)

	modal_body = RichTextLabel.new()
	modal_body.bbcode_enabled = true
	modal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_font_size_override("normal_font_size", 12)
	right_col.add_child(modal_body)

	modal_prompt_label = Label.new()
	modal_prompt_label.text = "▼ [Enter / Space / 클릭]"
	modal_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	modal_prompt_label.add_theme_font_size_override("font_size", 11)
	modal_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	modal_prompt_label.visible = false
	right_col.add_child(modal_prompt_label)

	# 5. Title / Protagonist Selection Screen Overlay
	title_overlay = PanelContainer.new()
	title_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_overlay.visible = false
	add_child(title_overlay)


func _add_quick_btn(parent: Node, label_text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(76, 24)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(callback)
	parent.add_child(btn)


# ==============================================================================
# Title & Protagonist Selection Screen
# ==============================================================================
func _show_title_screen() -> void:
	_close_modal()
	current_mode = GameMode.TITLE_SELECT
	port_view.is_modal_open = true
	world_map_view.is_modal_open = true
	title_overlay.visible = true
	GameData.play_bgm("title")

	for c in title_overlay.get_children():
		c.queue_free()

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	title_overlay.add_child(root_vbox)

	var header := Label.new()
	header.text = "대항해시대 II (Uncharted Waters II - DOS 한글판 리버스 엔지니어링 Godot 4 이식판)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	root_vbox.add_child(header)

	var sub := Label.new()
	sub.text = "출항할 주인공을 선택하십시오 (원본 MAIN.EXE / KAO.LZW / CHAR.LZW / PORTMAP.LZW / WORLDMAP.LZW 데이터 연동)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	root_vbox.add_child(sub)

	var has_any_save := false
	for s in range(1, 4):
		if GameData.has_save(s):
			has_any_save = true
			break
	if has_any_save:
		var load_row := HBoxContainer.new()
		load_row.alignment = BoxContainer.ALIGNMENT_CENTER
		root_vbox.add_child(load_row)
		var load_btn := Button.new()
		load_btn.text = "★ 저장된 항해 일지 불러오기 (이어하기) ★"
		load_btn.custom_minimum_size = Vector2(260, 28)
		load_btn.add_theme_font_size_override("font_size", 12)
		load_btn.pressed.connect(_show_load_menu)
		load_row.add_child(load_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	root_vbox.add_child(grid)

	for i in range(GameData.PROTAGONIST_PRESETS.size()):
		var preset: Dictionary = GameData.PROTAGONIST_PRESETS[i]
		var char_rec := GameData.get_character(int(preset["char_id"]))
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(304, 102)
		grid.add_child(card)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		card.add_child(hbox)

		var face := TextureRect.new()
		face.texture = GameData.get_portrait_atlas_texture(int(char_rec.get("portrait_id", i)))
		face.custom_minimum_size = Vector2(64, 80)
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(face)

		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_v)

		var name_lbl := Label.new()
		name_lbl.text = "%s (%s)" % [preset["name"], preset["nation"]]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		info_v.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = preset["desc"]
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 10)
		info_v.add_child(desc_lbl)

		var start_btn := Button.new()
		start_btn.text = "%s로 출항 시작 (%s)" % [preset["name"], GameData.get_port(preset["start_port_id"]).get("name", "")]
		start_btn.add_theme_font_size_override("font_size", 11)
		start_btn.pressed.connect(_on_select_protagonist.bind(i))
		info_v.add_child(start_btn)


func _on_select_protagonist(idx: int) -> void:
	title_overlay.visible = false
	GameData.start_new_game(idx)
	_enter_port(GameData.current_port_id)


# ==============================================================================
# Mode Switching (Port <-> World Map)
# ==============================================================================
func _enter_port(pid: int) -> void:
	_close_modal()
	GameData.current_port_id = pid
	current_mode = GameMode.PORT
	port_view.visible = true
	world_map_view.visible = false
	port_view.is_modal_open = false
	world_map_view.is_modal_open = true
	port_view.setup_port(pid)
	GameData.play_port_bgm(pid)
	var p := GameData.get_port(pid)
	_set_log_text("[color=#ffd866][%s][/color] 항구에 입항했습니다. 방향키(WASD/화살표)로 이동하고 건물 입구로 들어가거나 [Enter/Space]를 누르십시오." % p.get("name", ""))
	_refresh_hud()


func _sail_out_to_world_map(from_port_id: int) -> void:
	# Check if there is an active departure trigger (0xA0, 0x01) in the current subsection
	var dep_trig := GameData.find_departure_scenario_trigger(from_port_id)
	if not dep_trig.is_empty():
		var res := GameData.execute_scenario_trigger(dep_trig)
		var post_trig := GameData.find_matching_scenario_trigger(from_port_id, 3) # Harbor slot 3
		if not post_trig.is_empty():
			var post_res := GameData.execute_scenario_trigger(post_trig)
			if post_res.get("executed", false):
				_show_scenario_result_modal(post_trig, post_res, {"id": "harbor", "slot": 3, "name_kr": "항구(부두)"}, true)
				return
		elif res.get("executed", false) and not res.get("dialogues", []).is_empty():
			_show_scenario_result_modal(dep_trig, res, {"id": "harbor", "slot": 3, "name_kr": "항구(부두)"}, true)
			return

	_do_actual_sail_out(from_port_id)


func _do_actual_sail_out(from_port_id: int) -> void:
	_close_modal()
	current_mode = GameMode.WORLD_MAP
	port_view.visible = false
	world_map_view.visible = true
	port_view.is_modal_open = true
	world_map_view.is_modal_open = false
	world_map_view.activate_at_port(from_port_id)
	GameData.play_bgm("sailing")
	var p := GameData.get_port(from_port_id)
	_set_log_text("[color=#77ddff][%s][/color] 부두에서 출항했습니다! 8방향(WASD/방향키)으로 항해하며, 항구 좌표 진입 또는 [Space/Enter]로 입항·탐색할 수 있습니다." % p.get("name", ""))
	_refresh_hud()


func _on_port_docked(pid: int) -> void:
	_enter_port(pid)


# ==============================================================================
# HUD Refresh
# ==============================================================================
func _refresh_hud() -> void:
	var char_rec := GameData.get_character(GameData.protagonist_id)
	protag_portrait_rect.texture = GameData.get_portrait_atlas_texture(int(char_rec.get("portrait_id", GameData.protagonist_id)))

	if current_mode == GameMode.PORT:
		var p := GameData.get_port(GameData.current_port_id)
		location_label.text = "항구: %s\n(타일셋 #%d)" % [p.get("name", ""), int(p.get("chip_no", 0))]
	else:
		location_label.text = "해상 항해 중\n좌표: (%d, %d)" % [GameData.world_tile_x, GameData.world_tile_y]

	var tod_map := {"dawn": "새벽", "day": "낮", "dusk": "석양", "night": "밤"}
	var tod_kr: String = tod_map.get(GameData.get_time_of_day_key(), "낮")
	date_label.text = "%d년 %d월 %d일\n%02d:00 (%s)" % [GameData.year, GameData.month, GameData.day, GameData.hour_of_day, tod_kr]

	gold_label.text = "금화: %d 닢  금괴: %d\n예금: %d  부채: %d" % [
		GameData.gold_coins, GameData.gold_ingots, GameData.bank_deposit, GameData.bank_debt
	]

	if not GameData.fleet_ships.is_empty():
		var s: Dictionary = GameData.fleet_ships[0]
		fleet_label.text = "기함: %s (%s)\n내구: %d/%d  선원: %d/%d\n식량: %d  물: %d" % [
			s["name"], s.get("type_name", "범선"),
			s["hull"], s["max_hull"],
			s["crew"], s["max_crew"],
			s["food"], s["water"]
		]

	var wc := GameData.get_wind_and_current(GameData.world_tile_x, GameData.world_tile_y)
	var dir_names := ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]
	wind_label.text = "풍향: %s풍 (풍속 %d)\n해류: %s류 (유속 %d)" % [
		dir_names[wc["wind_dir"] % 8], wc["wind_speed"],
		dir_names[wc["current_dir"] % 8], wc["current_speed"]
	]

	if current_mode == GameMode.PORT:
		port_view.queue_redraw()
	elif current_mode == GameMode.WORLD_MAP:
		world_map_view.queue_redraw()


func _set_log_text(bbcode: String) -> void:
	bottom_log_label.text = bbcode
	bottom_log_label.visible_characters = 0
	log_typewriter_active = true
	log_typewriter_elapsed = 0.0


func _on_npc_interacted(npc: Dictionary) -> void:
	var dlgs: Array = npc.get("dialogues", [])
	if dlgs.is_empty():
		return
	var line: String = dlgs[randi() % dlgs.size()]
	_set_log_text("[color=#ffd866]【%s】[/color] \"%s\"" % [npc.get("name", "시민"), line])


# ==============================================================================
# Building Interaction & Modal Menus
# ==============================================================================
func _open_modal(title: String, kao_id: int, body_bbcode: String, actions: Array, building_key: String = "") -> void:
	modal_layer.visible = true
	port_view.is_modal_open = true
	world_map_view.is_modal_open = true
	modal_title.text = title

	# 1. Building Interior Illustration vs Character Portrait
	if building_key != "" and GameData.building_interior_textures.has(building_key):
		modal_interior_rect.texture = GameData.building_interior_textures[building_key]
		modal_interior_rect.visible = true
		modal_portrait.visible = false
	else:
		modal_interior_rect.visible = false
		modal_portrait.texture = GameData.get_portrait_atlas_texture(kao_id)
		modal_portrait.visible = true

	# 2. Progressive Typewriter Dialogue Effect
	modal_body.text = body_bbcode
	modal_body.visible_characters = 0
	typewriter_active = true
	typewriter_elapsed = 0.0
	modal_prompt_label.visible = false

	# 3. Action Buttons
	for c in modal_buttons_box.get_children():
		c.queue_free()

	for act in actions:
		var btn := Button.new()
		btn.text = act["label"]
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(act["callback"])
		modal_buttons_box.add_child(btn)


func _close_modal() -> void:
	modal_layer.visible = false
	typewriter_active = false
	if current_mode == GameMode.PORT:
		GameData.play_port_bgm(GameData.current_port_id)
		port_view.is_modal_open = false
	elif current_mode == GameMode.WORLD_MAP:
		GameData.play_bgm("sailing")
		world_map_view.is_modal_open = false
	_refresh_hud()


func _on_building_entered(b_info: Dictionary) -> void:
	var bslot: int = int(b_info.get("slot", -1))
	var trig := GameData.find_matching_scenario_trigger(GameData.current_port_id, bslot)
	if not trig.is_empty():
		var res := GameData.execute_scenario_trigger(trig)
		if res.get("executed", false):
			_show_scenario_result_modal(trig, res, b_info, false)
			return
	_open_standard_building_menu(b_info)


func _show_scenario_result_modal(trig: Dictionary, res: Dictionary, b_info: Dictionary, sail_after: bool = false) -> void:
	var dialogs: Array = res.get("dialogues", [])
	var rewards: Array = res.get("rewards", [])
	var choices: Array = res.get("choices", [])
	var p := GameData.get_port(GameData.current_port_id)
	var pname: String = p.get("name", str(trig.get("port_name", "")))
	var bname: String = b_info.get("name_kr", str(trig.get("building_name", "")))

	var lines_bb := "[color=#77ddff]【시나리오 이벤트 — %s (%s) | 제%d장 제%d절】[/color]\n\n" % [
		pname, bname, GameData.scenario_chapter + 1, GameData.scenario_subsection + 1
	]
	var portrait_id: int = int(GameData.get_character(GameData.protagonist_id).get("portrait_id", GameData.protagonist_id))
	for i in range(dialogs.size()):
		var d: Dictionary = dialogs[i]
		var spk_code: int = int(d.get("speaker_code", 0))
		if spk_code > 0 and spk_code < 128:
			portrait_id = spk_code
		lines_bb += "• " + GameData.format_scenario_text(str(d.get("text", ""))) + "\n\n"

	if not choices.is_empty():
		for ch in choices:
			var opts: Array = ch.get("options", [])
			var sel: int = int(ch.get("selected", 0))
			if sel >= 0 and sel < opts.size():
				lines_bb += "[color=#ffd866]▶ 선택: 「%s」[/color]\n" % opts[sel]
		lines_bb += "\n"

	if not rewards.is_empty():
		lines_bb += "[color=#66ff88]【이벤트 결과 및 보상】[/color]\n"
		for rw in rewards:
			lines_bb += "★ [b]%s[/b]\n" % str(rw)

	var actions: Array = []
	if sail_after:
		actions.append({"label": "바다로 출항 계속", "callback": _do_actual_sail_out.bind(GameData.current_port_id)})
	else:
		actions.append({"label": "%s 메뉴 열기" % bname, "callback": _open_standard_building_menu.bind(b_info)})
		actions.append({"label": "항구 거리로 나가기", "callback": _close_modal})

	_open_modal(
		"%s - %s (시나리오 이벤트)" % [pname, bname],
		portrait_id,
		lines_bb,
		actions,
		b_info.get("id", "")
	)


func _open_standard_building_menu(b_info: Dictionary) -> void:
	var bid: String = b_info.get("id", "").strip_edges()
	var bname: String = b_info.get("name_kr", "건물")
	var p := GameData.get_port(GameData.current_port_id)
	var pname: String = p.get("name", "")

	match bid:
		"harbor":
			_open_harbor_menu(pname)
		"market":
			_open_market_menu(pname)
		"tavern":
			_open_tavern_menu(pname)
		"shipyard":
			_open_shipyard_menu(pname)
		"lodge":
			_open_inn_menu(pname)
		"palace":
			_open_palace_menu(pname)
		"guild":
			_open_guild_menu(pname)
		"bank":
			_open_bank_menu(pname)
		"church":
			_open_church_menu(pname)
		"fortune":
			_open_fortune_menu(pname)
		"item_shop":
			_open_item_shop_menu(pname)
		"mansion":
			_open_mansion_menu(pname)
		_:
			_open_modal(
				"%s - %s" % [pname, bname],
				70,
				"어서 오십시오! 이곳은 [color=#ffd866]%s[/color]의 [b]%s[/b]입니다." % [pname, bname],
				[{"label": "나가기", "callback": _close_modal}]
			)


func _open_harbor_menu(pname: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var body := "[color=#77ddff][%s 부두][/color]\n\"선장님, 출항 준비가 되었습니까? 식량과 식수를 충분히 보급한 뒤 출항하십시오.\"\n\n" % pname
	body += "• 현재 기함: [b]%s[/b] (%s)\n" % [ship["name"], ship.get("type_name", "범선")]
	body += "• 선원: %d / %d 명\n• 식량: %d 일분   • 물: %d 일분\n" % [
		ship["crew"], ship["max_crew"], ship["food"], ship["water"]
	]
	if ship.has("figurehead"):
		body += "• 선수상: [color=#ffd866]%s[/color] (재해 방지 %d%%)\n" % [ship["figurehead"], ship.get("disaster_protection", 0)]
	if ship.has("cannon_type"):
		body += "• 무장: [color=#ff7777]%s[/color] %d문 (위력 %d)\n" % [ship["cannon_type"], ship.get("cannons", 0), ship.get("cannon_power", 0)]

	_open_modal(
		"%s 부두 (Harbor)" % pname,
		72,
		body,
		[
			{"label": "출항한다 (월드맵)", "callback": _sail_out_to_world_map.bind(GameData.current_port_id)},
			{"label": "식량/물 보급 (50닢)", "callback": _buy_harbor_supplies.bind(pname)},
			{"label": "항구로 돌아가기", "callback": _close_modal}
		],
		"harbor"
	)


func _buy_harbor_supplies(pname: String) -> void:
	if GameData.gold_coins >= 50:
		var ship: Dictionary = GameData.fleet_ships[0]
		GameData.gold_coins -= 50
		ship["food"] += 20
		ship["water"] += 20
		_open_harbor_menu(pname)
		_refresh_hud()


func _open_market_menu(pname: String) -> void:
	var goods := GameData.get_port_market_goods(GameData.current_port_id)
	var ship: Dictionary = GameData.fleet_ships[0]
	var cargo: Dictionary = ship["cargo"]
	var inv: Dictionary = GameData.get_port_investment(GameData.current_port_id)
	var body := "[color=#ffd866][%s 교역소 시세표][/color] (상업 가치: %d / 1000)\n" % [pname, int(inv.get("commercial", 300))]
	for g in goods:
		var owned_qty: int = cargo.get(g["name"], 0)
		body += "• [b]%s[/b] (%s) — 매입: [color=#77ff77]%d닢[/color] / 매각: %d닢 (보유: %d)\n" % [
			g["name"], g["category"], g["buy_price"], g["sell_price"], owned_qty
		]

	var actions: Array = []
	for i in range(mini(3, goods.size())):
		var g: Dictionary = goods[i]
		actions.append({
			"label": "%s 10개 구매 (%d닢)" % [g["name"], g["buy_price"] * 10],
			"callback": _buy_market_good.bind(g, pname)
		})
		if cargo.get(g["name"], 0) > 0:
			actions.append({
				"label": "%s 10개 매각 (+%d닢)" % [g["name"], g["sell_price"] * 10],
				"callback": _sell_market_good.bind(g, pname)
			})

	actions.append({"label": "상업 투자 (500닢)", "callback": _invest_market.bind(pname, 500)})
	actions.append({"label": "나가기", "callback": _close_modal})
	_open_modal("%s 교역소 (Market)" % pname, 74, body, actions, "market")


func _invest_market(pname: String, amount: int) -> void:
	var res := GameData.invest_port(GameData.current_port_id, "commercial", amount)
	if res.get("success", false):
		_set_log_text("[color=#77ff77]%s 교역소에 금화 %d닢을 투자하여 상업 가치가 %d로 상승했습니다![/color]" % [pname, amount, res["current_commercial"]])
	else:
		_set_log_text("[color=#ff7777]투자 실패: %s[/color]" % res.get("reason", ""))
	_open_market_menu(pname)
	_refresh_hud()


func _buy_market_good(g: Dictionary, pname: String) -> void:
	var cost: int = g["buy_price"] * 10
	if GameData.gold_coins >= cost:
		var cargo: Dictionary = GameData.fleet_ships[0]["cargo"]
		GameData.gold_coins -= cost
		cargo[g["name"]] = cargo.get(g["name"], 0) + 10
		_open_market_menu(pname)
		_refresh_hud()


func _sell_market_good(g: Dictionary, pname: String) -> void:
	var cargo: Dictionary = GameData.fleet_ships[0]["cargo"]
	var sell_q := mini(10, cargo.get(g["name"], 0))
	if sell_q > 0:
		GameData.gold_coins += sell_q * int(g["sell_price"])
		cargo[g["name"]] -= sell_q
		if cargo[g["name"]] <= 0:
			cargo.erase(g["name"])
		_open_market_menu(pname)
		_refresh_hud()


func _open_tavern_menu(pname: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var waitress_kao := 105 + (GameData.current_port_id % 18)
	var disc_hint: Dictionary = GameData.discoveries[GameData.current_port_id % GameData.discoveries.size()]
	var body := "[color=#ff99cc][%s 주점][/color]\n\"어서 오세요, 선장님! 시원한 포도주와 맥주가 준비되어 있답니다.\"\n\n" % pname
	body += "• 현재 선원: %d / %d 명\n" % [ship["crew"], ship["max_crew"]]
	body += "• [소문]: 좌표 [color=#ffd866](%d, %d)[/color] 부근에서 [b]'%s'[/b]에 대한 전설이 들려옵니다!" % [
		int(disc_hint["world_x"]), int(disc_hint["world_y"]), disc_hint["name"]
	]
	_open_modal(
		"%s 주점 (Tavern)" % pname,
		waitress_kao,
		body,
		[
			{"label": "선원 10명 모집 (80닢)", "callback": _hire_tavern_crew.bind(pname)},
			{"label": "선원들에게 한턱내기 (30닢)", "callback": _treat_tavern_drinks.bind(pname)},
			{"label": "항해사 고용 면담", "callback": _open_tavern_recruit.bind(pname)},
			{"label": "여급과 이야기/선물", "callback": _open_tavern_waitress.bind(pname, waitress_kao)},
			{"label": "블랙잭 카드 도박", "callback": _open_tavern_gamble.bind(pname)},
			{"label": "나가기", "callback": _close_modal}
		],
		"tavern"
	)


func _open_tavern_recruit(pname: String) -> void:
	var candidates := GameData.get_hireable_companions(GameData.current_port_id)
	var body := "[color=#ffd866][%s 주점 — 항해사 탐색][/color]\n이곳 주점 테이블에서 새로운 일자리를 찾는 베테랑 항해사들입니다:\n\n" % pname
	var actions: Array = []
	if candidates.is_empty():
		body += "현재 주점에 고용 가능한 항해사가 머물고 있지 않습니다.\n"
	else:
		for c in candidates:
			var cid: int = int(c["id"])
			var wage: int = 300 + (cid * 20) % 300
			body += "• [b]%s[/b] (%s) — 항해Lv %d / 전투Lv %d (계약금: %d닢)\n" % [
				c["full_name"], c["nation_name"], int(c["nav_level"]), int(c["combat_level"]), wage
			]
			actions.append({
				"label": "%s 고용 (%d닢)" % [c["full_name"], wage],
				"callback": _do_hire_companion.bind(c, wage, pname)
			})
	actions.append({"label": "주점 메인으로", "callback": _open_tavern_menu.bind(pname)})
	_open_modal("%s 주점 (항해사 고용)" % pname, 71, body, actions, "tavern")


func _do_hire_companion(c: Dictionary, wage: int, pname: String) -> void:
	var cid: int = int(c["id"])
	if GameData.hire_companion(cid, wage):
		_set_log_text("[color=#77ff77]새로운 동료 [%s]이(가) 함대에 합류했습니다![/color]" % c["full_name"])
	else:
		_set_log_text("[color=#ff7777]고용 실패: 금화가 부족합니다.[/color]")
	_open_tavern_recruit(pname)
	_refresh_hud()


func _open_tavern_waitress(pname: String, waitress_kao: int) -> void:
	var aff_info := GameData.interact_waitress(GameData.current_port_id, 0)
	var body := "[color=#ff99cc][%s 주점 여급][/color]\n\"어머 선장님, 오셨어요?\"\n\n" % pname
	body += "• 여급 친밀도: [color=#ffd866]%d[/color] pt\n\n" % int(aff_info.get("affection", 0))
	body += aff_info.get("hint", "") + "\n"

	var actions: Array = [
		{"label": "가벼운 선물 건네기 (50닢)", "callback": _gift_waitress.bind(pname, waitress_kao, 50)},
		{"label": "진귀한 보석 선물 (200닢)", "callback": _gift_waitress.bind(pname, waitress_kao, 200)},
		{"label": "주점 메인으로", "callback": _open_tavern_menu.bind(pname)}
	]
	_open_modal("%s 주점 여급" % pname, waitress_kao, body, actions, "waitress")


func _gift_waitress(pname: String, waitress_kao: int, cost: int) -> void:
	var res := GameData.interact_waitress(GameData.current_port_id, cost)
	if res.get("success", false):
		_set_log_text("[color=#ff99cc]여급에게 선물을 건넸습니다! 친밀도가 %d pt가 되었습니다.[/color]" % res.get("affection", 0))
	else:
		_set_log_text("[color=#ff7777]%s[/color]" % res.get("reason", ""))
	_open_tavern_waitress(pname, waitress_kao)
	_refresh_hud()


func _open_tavern_gamble(pname: String) -> void:
	var body := "[color=#ffd866][%s 주점 도박판 (블랙잭)][/color]\n딜러와 카드를 겨루어 21에 가까운 쪽이 판돈의 두 배를 가져갑니다.\n(현재 소지 금화: %d닢)\n" % [
		pname, GameData.gold_coins
	]
	var actions: Array = [
		{"label": "50닢 베팅하고 카드 받기", "callback": _play_blackjack_round.bind(pname, 50)},
		{"label": "100닢 베팅하고 카드 받기", "callback": _play_blackjack_round.bind(pname, 100)},
		{"label": "200닢 베팅하고 카드 받기", "callback": _play_blackjack_round.bind(pname, 200)},
		{"label": "주점 메인으로", "callback": _open_tavern_menu.bind(pname)}
	]
	_open_modal("%s 주점 도박 (블랙잭)" % pname, 85, body, actions, "tavern")


func _play_blackjack_round(pname: String, bet: int) -> void:
	var res := GameData.play_blackjack(bet)
	if not res.get("success", false):
		_set_log_text("[color=#ff7777]%s[/color]" % res.get("reason", ""))
		_open_tavern_gamble(pname)
		return
	var body := "[color=#ffd866][%s 주점 도박 결과][/color]\n\n" % pname
	body += "• 선장님 패: %s (합계: [b]%d[/b])\n" % [str(res["player_cards"]), res["player_sum"]]
	body += "• 딜러 패: %s (합계: [b]%d[/b])\n\n" % [str(res["dealer_cards"]), res["dealer_sum"]]
	body += "[color=%s]%s[/color]" % [("#77ff77" if res["won"] else "#ff7777"), res["msg"]]

	var actions: Array = [
		{"label": "다시 베팅하기", "callback": _open_tavern_gamble.bind(pname)},
		{"label": "주점 메인으로", "callback": _open_tavern_menu.bind(pname)}
	]
	_open_modal("%s 주점 도박 (결과)" % pname, 85, body, actions, "tavern")
	_refresh_hud()


func _hire_tavern_crew(pname: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	if GameData.gold_coins >= 80 and ship["crew"] < ship["max_crew"]:
		GameData.gold_coins -= 80
		ship["crew"] = mini(ship["max_crew"], ship["crew"] + 10)
		_open_tavern_menu(pname)
		_refresh_hud()


func _treat_tavern_drinks(pname: String) -> void:
	if GameData.gold_coins >= 30:
		GameData.gold_coins -= 30
		GameData.advance_hours(2)
		_open_tavern_menu(pname)
		_refresh_hud()


func _repair_flagship(pname: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	if GameData.gold_coins >= 100:
		GameData.gold_coins -= 100
		ship["hull"] = ship["max_hull"]
		_open_shipyard_menu(pname)
		_refresh_hud()


func _buy_new_ship(st: Dictionary, price: int, pname: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	if GameData.gold_coins >= price:
		GameData.gold_coins -= price
		ship["type_id"] = int(st["id"])
		ship["type_name"] = st["name"]
		ship["max_hull"] = int(st["max_hull"])
		ship["hull"] = int(st["max_hull"])
		ship["max_crew"] = int(st["max_crew"])
		ship["capacity"] = int(st["capacity"])
		_open_shipyard_menu(pname)
		_refresh_hud()


func _claim_palace_grant() -> void:
	GameData.gold_coins += 500
	_refresh_hud()
	_close_modal()


func _open_shipyard_menu(pname: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var inv: Dictionary = GameData.get_port_investment(GameData.current_port_id)
	var body := "[color=#77ddff][%s 조선소][/color] (공업 가치: %d / 1000)\n\"배를 수리하거나 새로운 함선을 건조하시겠소?\"\n\n" % [
		pname, int(inv.get("industrial", 300))
	]
	body += "• 현재 기함: [b]%s[/b] (%s) — 내구도 %d / %d\n" % [
		ship["name"], ship.get("type_name", ""), ship["hull"], ship["max_hull"]
	]
	if ship.has("figurehead"):
		body += "• 장착 선수상: [color=#ffd866]%s[/color]\n" % ship["figurehead"]
	if ship.has("cannon_type"):
		body += "• 무장 대포: [color=#ff7777]%s[/color] %d문\n" % [ship["cannon_type"], ship.get("cannons", 0)]

	var actions: Array = []
	if ship["hull"] < ship["max_hull"]:
		actions.append({"label": "기함 수리 (100닢)", "callback": _repair_flagship.bind(pname)})

	actions.append({"label": "선박 개조 (선수상/대포)", "callback": _open_shipyard_remodel.bind(pname)})
	actions.append({"label": "신조함 건조 목록", "callback": _open_shipyard_build_list.bind(pname)})
	actions.append({"label": "공업 투자 (500닢)", "callback": _invest_industry.bind(pname, 500)})
	actions.append({"label": "나가기", "callback": _close_modal})
	_open_modal("%s 조선소 (Shipyard)" % pname, 73, body, actions, "shipyard")


func _invest_industry(pname: String, amount: int) -> void:
	var res := GameData.invest_port(GameData.current_port_id, "industrial", amount)
	if res.get("success", false):
		_set_log_text("[color=#77ff77]%s 조선소에 금화 %d닢을 투자하여 공업 가치가 %d로 상승했습니다![/color]" % [pname, amount, res["current_industrial"]])
	else:
		_set_log_text("[color=#ff7777]투자 실패: %s[/color]" % res.get("reason", ""))
	_open_shipyard_menu(pname)
	_refresh_hud()


func _open_shipyard_remodel(pname: String) -> void:
	var body := "[color=#77ddff][%s 조선소 — 선박 개조][/color]\n기함에 설치할 특수 장비를 선택하십시오:\n\n" % pname
	body += "[선수상 목록 (폭풍 및 해양 재해 방어)]:\n"
	for fig in GameData.FIGUREHEAD_TYPES:
		body += "• [b]%s[/b] (재해방어 %d%%, 가격: %d닢)\n" % [fig["name"], fig["protection"], fig["price"]]
	body += "\n[대포 목록 (포격전 위력 강화)]:\n"
	for can in GameData.CANNON_TYPES:
		body += "• [b]%s[/b] (위력 %d, 사거리 %d, 문당 %d닢)\n" % [can["name"], can["power"], can["range"], can["price_per_gun"]]

	var actions: Array = [
		{"label": "천사상 선수상 장착 (2500닢)", "callback": _install_fig.bind(3, pname)},
		{"label": "여신상 선수상 장착 (8000닢)", "callback": _install_fig.bind(5, pname)},
		{"label": "컬버린포 10문 장착 (650닢)", "callback": _install_can.bind(3, 10, pname)},
		{"label": "캐넌포 10문 장착 (900닢)", "callback": _install_can.bind(4, 10, pname)},
		{"label": "조선소 메인으로", "callback": _open_shipyard_menu.bind(pname)}
	]
	_open_modal("%s 조선소 (선박 개조)" % pname, 73, body, actions, "shipyard")


func _install_fig(idx: int, pname: String) -> void:
	var res := GameData.install_figurehead(idx)
	if res.get("success", false):
		_set_log_text("[color=#77ff77]기함에 [%s] 선수상을 장착했습니다! (재해 방지 %d%%)[/color]" % [res["name"], res["protection"]])
	else:
		_set_log_text("[color=#ff7777]%s[/color]" % res.get("reason", ""))
	_open_shipyard_remodel(pname)
	_refresh_hud()


func _install_can(idx: int, count: int, pname: String) -> void:
	var res := GameData.install_cannons(idx, count)
	if res.get("success", false):
		_set_log_text("[color=#77ff77]기함에 [%s] 대포 %d문을 장착했습니다! (포격 위력 %d)[/color]" % [res["name"], count, res["power"]])
	else:
		_set_log_text("[color=#ff7777]%s[/color]" % res.get("reason", ""))
	_open_shipyard_remodel(pname)
	_refresh_hud()


func _open_shipyard_build_list(pname: String) -> void:
	var inv: Dictionary = GameData.get_port_investment(GameData.current_port_id)
	var ind: int = int(inv.get("industrial", 300))
	var body := "[color=#77ddff][%s 조선소 — 신조함 건조][/color]\n" % pname
	var available_ids: Array = [2, 6]
	if ind >= 450:
		available_ids.append(9)
	if ind >= 700:
		available_ids.append(13)
	if ind >= 900:
		available_ids.append(15)

	var actions: Array = []
	for st_id in available_ids:
		var st := GameData.get_ship_type(st_id)
		var price: int = maxi(400, int(st.get("new_price_x100", 10)) * 50)
		body += "• [b]%s[/b] — 적재: %d / 내구: %d / 최대선원: %d (건조비: %d닢)\n" % [
			st["name"], int(st["capacity"]), int(st["max_hull"]), int(st["max_crew"]), price
		]
		actions.append({
			"label": "%s 구입 (%d닢)" % [st["name"], price],
			"callback": _buy_new_ship.bind(st, price, pname)
		})
	actions.append({"label": "조선소 메인으로", "callback": _open_shipyard_menu.bind(pname)})
	_open_modal("%s 조선소 (건조)" % pname, 73, body, actions, "shipyard")


func _open_inn_menu(pname: String) -> void:
	_open_modal(
		"%s 여관 (Inn)" % pname,
		75,
		"\"편안히 쉬어 가시겠습니까? 하룻밤 숙박비로 금화 10닢을 받습니다.\"",
		[
			{"label": "아침까지 숙박 (10닢)", "callback": _sleep_until_morning},
			{"label": "저녁까지 휴식", "callback": _rest_six_hours},
			{"label": "나가기", "callback": _close_modal}
		],
		"inn"
	)


func _sleep_until_morning() -> void:
	if GameData.gold_coins >= 10:
		GameData.gold_coins -= 10
		GameData.advance_days(1)
		GameData.hour_of_day = 8
		_close_modal()


func _rest_six_hours() -> void:
	GameData.advance_hours(6)
	_close_modal()


func _open_palace_menu(pname: String) -> void:
	var cur_rank: int = GameData.royal_rank
	var cur_title: String = GameData.ROYAL_TITLES[cur_rank]
	var total_fame := GameData.adventure_fame + GameData.trade_fame + GameData.piracy_fame
	var body := "[color=#ffd866][%s 왕궁 / 총독 관저][/color]\n\"국왕 폐하를 알현하러 온 항해사인가?\"\n\n" % pname
	body += "• 현재 작위: [color=#ffd866][b]「%s」[/b][/color] (Rank %d)\n" % [cur_title, cur_rank]
	body += "• 누적 명성: 모험 %d / 상업 %d / 해적 %d (총합: [b]%d[/b] pt)\n" % [
		GameData.adventure_fame, GameData.trade_fame, GameData.piracy_fame, total_fame
	]
	body += "• 현재 보고 가능한 발견물: [b]%d / 100[/b]종\n" % GameData.discovered_ids.size()

	if not GameData.royal_mission.is_empty():
		body += "\n[color=#77ddff]【현재 진행 중인 칙명】[/color]\n• %s: %s\n" % [
			GameData.royal_mission.get("title", ""), GameData.royal_mission.get("desc", "")
		]

	var actions: Array = [
		{"label": "작위 승급 심사 (알현)", "callback": _check_royal_rank.bind(pname)},
		{"label": "탐험 후원금 수령 (+500닢)", "callback": _claim_palace_grant},
	]
	if GameData.royal_mission.is_empty():
		actions.append({"label": "국왕 칙명 하달 요청", "callback": _request_royal_mission.bind(pname)})
	else:
		actions.append({"label": "칙명 완료 보고", "callback": _report_royal_mission.bind(pname)})

	actions.append({"label": "나가기", "callback": _close_modal})
	_open_modal("%s 왕궁/총독부" % pname, 65, body, actions, "palace")


func _check_royal_rank(pname: String) -> void:
	var res := GameData.check_royal_promotion()
	if res.get("promoted", false):
		GameData.play_sfx("fanfare")
		_set_log_text("[color=#ffd866]%s[/color]" % res.get("msg", ""))
	else:
		_set_log_text("국왕 폐하: \"그대의 충성은 훌륭하나, 작위를 높이기 위해선 더 큰 명성이 필요하다.\"")
	_open_palace_menu(pname)


func _request_royal_mission(pname: String) -> void:
	var m := GameData.generate_royal_mission()
	_set_log_text("[color=#77ddff]국왕의 칙명이 하달되었습니다: %s[/color]" % m.get("desc", ""))
	_open_palace_menu(pname)


func _report_royal_mission(pname: String) -> void:
	var res := GameData.complete_royal_mission(GameData.current_port_id)
	if res.get("success", false):
		GameData.play_sfx("fanfare")
		_set_log_text("[color=#77ff77]%s[/color]" % res.get("msg", ""))
	else:
		_set_log_text("[color=#ff7777]%s[/color]" % res.get("reason", ""))
	_open_palace_menu(pname)


func _open_guild_menu(pname: String) -> void:
	var body := "[color=#ffd866][%s 조합 / 길드][/color]\n\"상인 조합에서는 진귀한 보물과 항해 도구를 거래하며 각국의 의뢰를 중개합니다.\"\n\n" % pname
	if not GameData.active_guild_quest.is_empty():
		var q: Dictionary = GameData.active_guild_quest
		body += "[color=#77ddff]【현재 수행 중인 조합 의뢰】[/color]\n"
		body += "• 의뢰: [b]%s[/b]\n• 내용: %s\n• 보수: 금화 [color=#77ff77]%d닢[/color] / %s 명성 +%d\n" % [
			q.get("title", ""), q.get("desc", ""), int(q.get("reward_gold", 0)),
			q.get("fame_type", ""), int(q.get("fame_reward", 0))
		]
	else:
		body += "현재 맡은 의뢰가 없습니다. 새로운 일거리를 찾아보시겠습니까?\n"

	var actions: Array = []
	if GameData.active_guild_quest.is_empty():
		actions.append({"label": "새로운 업무 알선 (의뢰 받기)", "callback": _open_guild_quest_offer.bind(pname)})
	else:
		actions.append({"label": "의뢰 완료 보고 / 보수 수령", "callback": _report_guild_quest.bind(pname)})
		actions.append({"label": "의뢰 포기", "callback": _abandon_guild_quest.bind(pname)})

	actions.append({"label": "나가기", "callback": _close_modal})
	_open_modal("%s 길드 (Guild)" % pname, 76, body, actions, "guild")


func _open_guild_quest_offer(pname: String) -> void:
	var q := GameData.generate_guild_quest(GameData.current_port_id)
	var body := "[color=#ffd866][%s 조합 — 신규 의뢰 제안][/color]\n\n" % pname
	body += "• 의뢰명: [b]%s[/b]\n" % q.get("title", "")
	body += "• 의뢰 내용: %s\n\n" % q.get("desc", "")
	body += "• 성공 보수: [color=#77ff77]금화 %d 닢[/color]\n" % int(q.get("reward_gold", 0))
	body += "• 명성 보상: %s 명성 +%d pt\n" % [q.get("fame_type", ""), int(q.get("fame_reward", 0))]
	body += "• 기한: %d일 이내\n" % int(q.get("limit_days", 30))

	var actions: Array = [
		{"label": "의뢰 수락하기", "callback": _accept_quest.bind(q, pname)},
		{"label": "다른 의뢰 보기", "callback": _open_guild_quest_offer.bind(pname)},
		{"label": "조합 메인으로", "callback": _open_guild_menu.bind(pname)}
	]
	_open_modal("%s 길드 (신규 의뢰)" % pname, 76, body, actions, "guild")


func _accept_quest(q: Dictionary, pname: String) -> void:
	GameData.accept_guild_quest(q)
	_set_log_text("[color=#77ddff]조합 의뢰 『%s』을(를) 수락했습니다![/color]" % q.get("title", ""))
	_open_guild_menu(pname)


func _report_guild_quest(pname: String) -> void:
	var res := GameData.check_guild_quest_completion(GameData.current_port_id)
	if res.get("can_complete", false):
		GameData.play_sfx("fanfare")
		_set_log_text("[color=#77ff77]%s[/color]" % res.get("msg", ""))
	else:
		_set_log_text("[color=#ff7777]%s[/color]" % res.get("reason", ""))
	_open_guild_menu(pname)


func _abandon_guild_quest(pname: String) -> void:
	GameData.active_guild_quest.clear()
	_set_log_text("조합 의뢰를 중도 포기했습니다.")
	_open_guild_menu(pname)


func _open_bank_menu(pname: String) -> void:
	var body := "[color=#77ff77][%s 마르코 폴로 은행][/color]\n• 현재 소지 금화: %d 닢\n• 예금액: %d 닢" % [
		pname, GameData.gold_coins, GameData.bank_deposit
	]
	_open_modal(
		"%s 은행 (Bank)" % pname,
		77,
		body,
		[
			{"label": "500닢 예금", "callback": _bank_deposit_500.bind(pname)},
			{"label": "500닢 출금", "callback": _bank_withdraw_500.bind(pname)},
			{"label": "나가기", "callback": _close_modal}
		],
		"bank"
	)


func _bank_deposit_500(pname: String) -> void:
	if GameData.gold_coins >= 500:
		GameData.gold_coins -= 500
		GameData.bank_deposit += 500
		_open_bank_menu(pname)
		_refresh_hud()


func _bank_withdraw_500(pname: String) -> void:
	if GameData.bank_deposit >= 500:
		GameData.bank_deposit -= 500
		GameData.gold_coins += 500
		_open_bank_menu(pname)
		_refresh_hud()


func _open_church_menu(pname: String) -> void:
	var body := "\"신의 가호가 그대의 항해와 함께하기를 기도합니다.\"\n\n성당에 금화를 기부하고 신의 축복을 빌 수 있습니다."
	_open_modal(
		"%s 성당/사원" % pname,
		78,
		body,
		[
			{"label": "금화 100닢 기부하기", "callback": _donate_church.bind(pname)},
			{"label": "나가기", "callback": _close_modal}
		],
		"church"
	)


func _donate_church(pname: String) -> void:
	if GameData.gold_coins >= 100:
		GameData.gold_coins -= 100
		GameData.adventure_fame += 20
		_set_log_text("[color=#77ddff]성당에 100닢을 기부하여 신의 가호와 행운을 얻었습니다.[/color]")
		_open_church_menu(pname)
		_refresh_hud()


func _open_fortune_menu(pname: String) -> void:
	var disc: Dictionary = GameData.discoveries[(GameData.current_port_id * 3 + 7) % GameData.discoveries.size()]
	_open_modal(
		"%s 점술가" % pname,
		88,
		"\"별자리가 가리키는 운명의 땅은 좌표 [color=#ffd866](%d, %d)[/color]... 그곳에서 [b]%s[/b]의 신비를 마주하게 될 것입니다.\"" % [
			int(disc["world_x"]), int(disc["world_y"]), disc["name"]
		],
		[{"label": "나가기", "callback": _close_modal}],
		"fortune"
	)


func _open_item_shop_menu(pname: String) -> void:
	var is_night_secret := GameData.is_secret_shop_open()
	if is_night_secret:
		var secret_items := GameData.get_secret_shop_items()
		var s_idx := (GameData.current_port_id + GameData.day) % secret_items.size()
		var s_itm: Dictionary = secret_items[s_idx]
		var s_cost: int = maxi(1000, int(s_itm.get("price", 1000)))
		var body := "[color=#ff5577][%s 심야 암시장 (02:00~03:00 AM)][/color]\n\"쉿...! 어둠 속에서만 거래되는 전설의 보물들이오.\"\n\n• [b]%s[/b] (가격: %d닢)\n%s" % [
			pname, s_itm["name"], s_cost, s_itm.get("description", "")
		]
		_open_modal(
			"%s 심야 암시장 (Secret Shop)" % pname,
			128 + 90,
			body,
			[
				{"label": "%s 구매 (%d닢)" % [s_itm["name"], s_cost], "callback": _buy_shop_item.bind(s_itm, s_cost)},
				{"label": "나가기", "callback": _close_modal}
			],
			"item_shop"
		)
		return

	var idx := (GameData.current_port_id * 2) % GameData.items.size()
	var itm: Dictionary = GameData.items[idx]
	var cost := maxi(200, int(itm["price"]))
	var body := "[color=#ffd866][%s 도구점][/color]\n오늘의 추천 명품:\n• [b]%s[/b] (가격: %d닢)\n%s" % [
		pname, itm["name"], cost, itm["description"]
	]
	_open_modal(
		"%s 도구점 (Item Shop)" % pname,
		128 + 80 + (idx % 45),
		body,
		[
			{"label": "%s 구매 (%d닢)" % [itm["name"], cost], "callback": _buy_shop_item.bind(itm, cost)},
			{"label": "나가기", "callback": _close_modal}
		],
		"item_shop"
	)


func _buy_shop_item(itm: Dictionary, cost: int) -> void:
	var item_id: int = int(itm["id"])
	if GameData.gold_coins >= cost and not GameData.owned_item_ids.has(item_id):
		GameData.gold_coins -= cost
		GameData.owned_item_ids.append(item_id)
		_set_log_text("[color=#77ff77][%s]을(를) 구입했습니다![/color]" % itm["name"])
		_refresh_hud()
		_close_modal()
	else:
		_set_log_text("[color=#ff7777]구매할 수 없습니다 (금화 부족 또는 이미 보유).[/color]")


func _open_mansion_menu(pname: String) -> void:
	var body := "[color=#ffd866][%s 저택 / 후원자 관저][/color]\n\"우리 가문과 계약을 맺거나 새로운 발견물을 보고하러 오셨습니까?\"\n\n• 현재 발견한 발견물 수: [b]%d / 100[/b]종" % [
		pname, GameData.discovered_ids.size()
	]
	_open_modal(
		"%s 저택/관저 (Mansion)" % pname,
		6,
		body,
		[
			{"label": "발견물 보고 및 후원금 수령 (+500닢)", "callback": _claim_palace_grant},
			{"label": "나가기", "callback": _close_modal}
		],
		"mansion"
	)


# ==============================================================================
# Discovery Popup & Info Sheets
# ==============================================================================
func _on_discovery_found(disc: Dictionary) -> void:
	var did: int = int(disc["id"])
	if not GameData.discovered_ids.has(did):
		GameData.discovered_ids.append(did)
	var body := "[color=#ffd866]★ 새로운 발견물 발견! ★[/color]\n\n[b]%s[/b] (좌표: %d, %d)\n\n%s" % [
		disc["name"], int(disc["world_x"]), int(disc["world_y"]), disc["description"]
	]
	# KAO.LZW 128 + discovery ID is the exact illustration from the original game!
	_open_modal(
		"발견물: %s" % disc["name"],
		128 + clampi(did, 0, 80),
		body,
		[{"label": "기록하고 항해 계속", "callback": _close_modal}]
	)


func _show_character_sheet() -> void:
	var c := GameData.get_character(GameData.protagonist_id)
	var st: Dictionary = c["stats"]
	var cur_rank: int = GameData.royal_rank
	var cur_title: String = GameData.ROYAL_TITLES[cur_rank]
	var body := "[b]%s[/b] (%s) — 작위: [color=#ffd866][b]「%s」[/b][/color]\n" % [
		c["full_name"], c["nation_name"], cur_title
	]
	body += "항해 Lv %d (EXP %d) / 전투 Lv %d (EXP %d)\n" % [
		int(c["nav_level"]), int(c["nav_exp"]), int(c["combat_level"]), int(c["combat_exp"])
	]
	body += "• 모험 명성: [color=#77ddff]%d[/color]   • 상업 명성: [color=#77ff77]%d[/color]   • 해적 명성: [color=#ff7777]%d[/color]\n\n" % [
		GameData.adventure_fame, GameData.trade_fame, GameData.piracy_fame
	]
	body += "• 통솔력: %d   • 항해술: %d\n• 지  식: %d   • 직  감: %d\n• 용  기: %d   • 검  술: %d\n• 매  력: %d   • 행  운: %d\n\n" % [
		int(st["leadership"]), int(st["seamanship"]), int(st["knowledge"]), int(st["intuition"]),
		int(st["courage"]), int(st["swordplay"]), int(st["charm"]), int(st["luck"])
	]
	body += "[소속 항해사/동료 (%d명)]:\n" % GameData.companions.size()
	for cid in GameData.companions:
		var comp := GameData.get_character(cid)
		body += "• %s (%s, 항해Lv %d, 전투Lv %d)\n" % [comp["full_name"], comp["nation_name"], int(comp["nav_level"]), int(comp["combat_level"])]
	body += "\n[보유 아이템 (%d종)]:\n" % GameData.owned_item_ids.size()
	for iid in GameData.owned_item_ids:
		if iid >= 0 and iid < GameData.items.size():
			body += "• %s: %s\n" % [GameData.items[iid]["name"], GameData.items[iid]["description"]]
	_open_modal("주인공 능력치 및 보유 물품", int(c.get("portrait_id", 0)), body, [{"label": "닫기", "callback": _close_modal}])


func _show_save_menu() -> void:
	var body := "[color=#ffd866]【항해 일지 기록 (저장하기)】[/color]\n저장할 슬롯을 선택하십시오:\n\n"
	var actions: Array = []
	for slot in range(1, 4):
		if GameData.has_save(slot):
			var info := GameData.get_save_info(slot)
			var p_id: int = int(info.get("protagonist_id", 0))
			var p_name: String = GameData.PROTAGONIST_PRESETS[p_id]["name"]
			var p_port: String = GameData.get_port(int(info.get("current_port_id", 0))).get("name", "")
			body += "• [b]슬롯 #%d[/b]: %s (%s) — %d년 %d월 %d일 (금화 %d닢)\n" % [
				slot, p_name, p_port, int(info.get("year", 1522)), int(info.get("month", 5)), int(info.get("day", 17)), int(info.get("gold_coins", 0))
			]
		else:
			body += "• [b]슬롯 #%d[/b]: [color=#888888](비어 있는 항해일지)[/color]\n" % slot

		actions.append({
			"label": "슬롯 #%d에 기록(저장)" % slot,
			"callback": _do_save_slot.bind(slot)
		})

	actions.append({"label": "닫기", "callback": _close_modal})
	_open_modal("항해 일지 저장", 76, body, actions)


func _do_save_slot(slot: int) -> void:
	if GameData.save_game(slot):
		_set_log_text("[color=#77ff77]항해 일지를 슬롯 #%d에 성공적으로 기록(저장)했습니다![/color]" % slot)
	else:
		_set_log_text("[color=#ff7777]저장 중 오류가 발생했습니다.[/color]")
	_close_modal()


func _show_load_menu() -> void:
	var body := "[color=#ffd866]【항해 일지 불러오기】[/color]\n불러올 슬롯을 선택하십시오:\n\n"
	var actions: Array = []
	for slot in range(1, 4):
		if GameData.has_save(slot):
			var info := GameData.get_save_info(slot)
			var p_id: int = int(info.get("protagonist_id", 0))
			var p_name: String = GameData.PROTAGONIST_PRESETS[p_id]["name"]
			var p_port: String = GameData.get_port(int(info.get("current_port_id", 0))).get("name", "")
			body += "• [b]슬롯 #%d[/b]: %s (%s) — %d년 %d월 %d일 (금화 %d닢)\n" % [
				slot, p_name, p_port, int(info.get("year", 1522)), int(info.get("month", 5)), int(info.get("day", 17)), int(info.get("gold_coins", 0))
			]
			actions.append({
				"label": "슬롯 #%d 불러오기" % slot,
				"callback": _do_load_slot.bind(slot)
			})
		else:
			body += "• [b]슬롯 #%d[/b]: [color=#888888](저장 데이터 없음)[/color]\n" % slot

	actions.append({"label": "닫기", "callback": _close_modal})
	_open_modal("항해 일지 불러오기", 76, body, actions)


func _do_load_slot(slot: int) -> void:
	if GameData.load_game(slot):
		_close_modal()
		title_overlay.visible = false
		_set_log_text("[color=#77ff77]슬롯 #%d의 항해 일지를 성공적으로 불러왔습니다![/color]" % slot)
		_enter_port(GameData.current_port_id)
		_refresh_hud()
	else:
		_set_log_text("[color=#ff7777]불러오기에 실패했습니다.[/color]")


func _process(delta: float) -> void:
	if typewriter_active:
		typewriter_elapsed += delta
		var chars := int(typewriter_elapsed / typewriter_speed)
		var total_chars := modal_body.get_total_character_count()
		if chars >= total_chars:
			modal_body.visible_characters = -1
			typewriter_active = false
			modal_prompt_label.visible = true
		else:
			modal_body.visible_characters = chars

	if modal_prompt_label.visible:
		var blink := int(Time.get_ticks_msec() / 400) % 2 == 0
		modal_prompt_label.modulate.a = 1.0 if blink else 0.25

	if log_typewriter_active:
		log_typewriter_elapsed += delta
		var lchars := int(log_typewriter_elapsed / typewriter_speed)
		var ltotal := bottom_log_label.get_total_character_count()
		if lchars >= ltotal:
			bottom_log_label.visible_characters = -1
			log_typewriter_active = false
		else:
			bottom_log_label.visible_characters = lchars


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey:
		if GameData.current_bgm_player != null and not GameData.current_bgm_player.playing and not GameData.is_audio_muted and not GameData.current_bgm_key.is_empty():
			var stream: AudioStream = GameData.audio_streams.get("bgm_" + GameData.current_bgm_key)
			if stream != null:
				GameData.current_bgm_player.stream = stream
				GameData.current_bgm_player.play()

	if typewriter_active and event.is_pressed():
		if (event is InputEventKey and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]) or event is InputEventMouseButton:
			modal_body.visible_characters = -1
			typewriter_active = false
			modal_prompt_label.visible = true
			get_viewport().set_input_as_handled()
			return

	if log_typewriter_active and event.is_pressed():
		bottom_log_label.visible_characters = -1
		log_typewriter_active = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			_do_save_slot(1)
		elif event.keycode == KEY_F9:
			_do_load_slot(1)
		elif event.keycode == KEY_F11:
			GameData.is_audio_muted = not GameData.is_audio_muted
			if GameData.is_audio_muted:
				GameData.stop_bgm()
				_set_log_text("사운드가 음소거되었습니다 (F11로 해제).")
			else:
				if current_mode == GameMode.PORT:
					GameData.play_port_bgm(GameData.current_port_id)
				else:
					GameData.play_bgm("sailing")
				_set_log_text("사운드가 다시 켜졌습니다.")



func _show_fleet_sheet() -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var cargo: Dictionary = ship["cargo"]
	var body := "[b]기함: %s[/b] (%s)\n• 내구도: %d / %d\n• 선원: %d / %d 명\n• 식량: %d 일분 / 식수: %d 일분\n\n[적재 화물 목록]:\n" % [
		ship["name"], ship.get("type_name", "범선"),
		ship["hull"], ship["max_hull"], ship["crew"], ship["max_crew"],
		ship["food"], ship["water"]
	]
	if cargo.is_empty():
		body += "• (적재된 교역품이 없습니다)"
	else:
		for k in cargo.keys():
			body += "• %s: %d 상자\n" % [k, cargo[k]]
	_open_modal("함대 및 적재 화물 정보", 128 + 105, body, [{"label": "닫기", "callback": _close_modal}])


func _show_discoveries_book() -> void:
	var body := "[color=#ffd866][COLONY.DAT 전체 100종 발견물 도감 (발견: %d / 100)][/color]\n\n" % GameData.discovered_ids.size()
	for i in range(25):
		var d: Dictionary = GameData.discoveries[i]
		var did: int = int(d["id"])
		var mark := "★" if GameData.discovered_ids.has(did) else "○"
		body += "%s #%02d [b]%s[/b] (%d, %d): %s\n" % [
			mark, did + 1, d["name"], int(d["world_x"]), int(d["world_y"]), d["description"]
		]
	_open_modal("발견물 도감 (COLONY.DAT)", 128 + 20, body, [{"label": "닫기", "callback": _close_modal}])


func _show_world_minimap() -> void:
	var body := "[color=#77ddff][세계 주요 항구 및 좌표 (총 130개 항구)][/color]\n현재 위치 좌표: [b](%d, %d)[/b]\n\n" % [
		GameData.world_tile_x, GameData.world_tile_y
	]
	for pid in [0, 1, 2, 8, 13, 18, 29, 33, 44, 59, 75, 85, 92, 95, 98, 99]:
		if pid < GameData.ports.size():
			var p := GameData.get_port(pid)
			body += "• #%02d [b]%s[/b] — 월드맵 좌표: (%d, %d)\n" % [int(p["id"]), p["name"], int(p["world_x"]), int(p["world_y"])]
	_open_modal("세계 해역 및 주요 항구 좌표", 128 + 109, body, [{"label": "닫기", "callback": _close_modal}])


func _show_fast_travel_menu() -> void:
	var body := "테스트 및 빠른 탐색을 위해 세계 주요 항구로 즉시 입항하거나 해상 출항할 수 있습니다."
	var famous_ports := [0, 1, 2, 8, 13, 29, 33, 92, 99] # 리스본, 세비야, 이스탄불, 제노바, 베네치아, 런던, 암스테르담, 캘리컷, 나가사키
	var actions: Array = []
	for pid in famous_ports:
		if pid < GameData.ports.size():
			var p := GameData.get_port(pid)
			actions.append({
				"label": "%s 입항 (%d, %d)" % [p["name"], int(p["world_x"]), int(p["world_y"])],
				"callback": _enter_port.bind(pid)
			})
	actions.append({"label": "닫기", "callback": _close_modal})
	_open_modal("주요 항구 빠른 이동 (Fast Travel)", 128 + 104, body, actions)


func _show_scenario_viewer() -> void:
	var snr := GameData.get_active_scenario()
	if snr.is_empty():
		return
	var chaps: Array = snr.get("chapters", [])
	var chap_idx := clampi(GameData.scenario_chapter, 0, maxi(0, chaps.size() - 1))
	var chap: Dictionary = chaps[chap_idx] if not chaps.is_empty() else {}
	var subs: Array = chap.get("subsections", [])
	var sub_idx := clampi(GameData.scenario_subsection, 0, maxi(0, subs.size() - 1))
	var sub: Dictionary = subs[sub_idx] if not subs.is_empty() else {}
	var trigs: Array = sub.get("triggers", [])

	var body := "[color=#ffd866]【%s — 원본 시나리오 이벤트 트리거 목록】[/color]\n" % snr.get("title", "")
	body += "• 현재 진행 단계: [b]Chapter %d / %d, Sub-section %d / %d[/b] (총 대사: %d줄)\n\n" % [
		chap_idx + 1, chaps.size(), sub_idx + 1, subs.size(), int(snr.get("total_lines", 0))
	]
	for t in trigs:
		var dlgs: Array = t.get("dialogues", [])
		var sample_txt := ""
		if not dlgs.is_empty():
			sample_txt = GameData.format_scenario_text(str(dlgs[0].get("text", ""))).replace("\n", " ")
		body += "• [color=#77ddff][%s - %s][/color] (대사 %d줄): %s\n" % [
			t.get("port_name", ""), t.get("building_name", ""), dlgs.size(), sample_txt.substr(0, 48)
		]

	_open_modal(
		"원본 시나리오 진행 현황 (SNR%d.DAT)" % int(snr.get("snr_id", 1)),
		GameData.protagonist_id,
		body,
		[
			{"label": "다음 절(Sub)로 이동", "callback": _next_scenario_sub_viewer},
			{"label": "다음 챕터(Chap)로 이동", "callback": _next_scenario_chap_viewer},
			{"label": "세계 주요 항구 좌표", "callback": _show_world_minimap},
			{"label": "닫기", "callback": _close_modal}
		]
	)


func _next_scenario_sub_viewer() -> void:
	var snr := GameData.get_active_scenario()
	var chaps: Array = snr.get("chapters", [])
	if GameData.scenario_chapter < chaps.size():
		var subs: Array = chaps[GameData.scenario_chapter].get("subsections", [])
		GameData.scenario_subsection = (GameData.scenario_subsection + 1) % maxi(1, subs.size())
	_show_scenario_viewer()


func _next_scenario_chap_viewer() -> void:
	var snr := GameData.get_active_scenario()
	var chaps: Array = snr.get("chapters", [])
	if not chaps.is_empty():
		GameData.scenario_chapter = (GameData.scenario_chapter + 1) % chaps.size()
		GameData.scenario_subsection = 0
	_show_scenario_viewer()


# ==============================================================================
# Naval Fleet Combat, 1:1 Captain Duel (Il-gi-to), & Sea Hazards
# ==============================================================================
func _on_sea_hazard_triggered(hazard: Dictionary) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var h_dmg: int = int(hazard.get("hull_damage", 0))
	var c_loss: int = int(hazard.get("crew_loss", 0))
	if h_dmg > 0:
		ship["hull"] = maxi(10, int(ship["hull"]) - h_dmg)
	if c_loss > 0:
		ship["crew"] = maxi(5, int(ship["crew"]) - c_loss)
	_refresh_hud()

	var body := "[color=#ff7777]【해상 재난 / 괴물 조우 경보】[/color]\n\n%s\n\n" % str(hazard.get("message", ""))
	if h_dmg > 0 or c_loss > 0:
		body += "• 피해 현황: 선체 내구도 -%d, 선원 -%d명\n" % [h_dmg, c_loss]
	body += "• 현재 기함 내구도: %d / %d (선원: %d명)" % [int(ship["hull"]), int(ship["max_hull"]), int(ship["crew"])]

	_open_modal(
		str(hazard.get("title", "해상 이벤트")),
		128 + 56,
		body,
		[{"label": "대오를 정비하고 항해 계속", "callback": _close_modal}]
	)


func _on_fleet_encountered(enemy: Dictionary) -> void:
	active_battle_enemy = enemy
	var body := "[color=#ffd866]【해상 함대 조우 — %s (%s)】[/color]\n\n" % [
		enemy.get("captain_name", ""), enemy.get("nation_name", "")
	]
	body += "• 소속/역할: [b]%s (%s)[/b]\n" % [enemy.get("nation_name", ""), enemy.get("role", "함대")]
	body += "• 적 기함: [b]%s[/b] (%s)\n" % [enemy.get("ship_name", ""), enemy.get("ship_type_name", "")]
	body += "• 적 내구도: %d / %d  |  적 선원: %d 명  |  대포: %d 문\n\n" % [
		int(enemy.get("hull", 100)), int(enemy.get("max_hull", 100)), int(enemy.get("crew", 50)), int(enemy.get("guns", 16))
	]
	if enemy.get("is_hostile", false):
		var p_line: String = GameData.system_messages[815] if GameData.system_messages.size() > 815 else "해적 %s! 칠대양을 떠들썩하게 한 네놈의 악행도 이제 끝이다!"
		body += "\"%s\"" % (p_line.replace("%s", str(enemy.get("captain_name", ""))))
	else:
		var m_line: String = GameData.system_messages[164] if GameData.system_messages.size() > 164 else "해적으로부터 이 바다를 지키고 있다."
		body += "\"%s\"" % m_line

	_open_modal(
		"함대 조우: %s" % enemy.get("captain_name", ""),
		int(enemy.get("portrait_id", 61)),
		body,
		[
			{"label": "해전 개시 (공격)", "callback": _start_naval_battle.bind(enemy)},
			{"label": "일기토 신청 (1:1 결투)", "callback": _start_captain_duel.bind(enemy)},
			{"label": "정중히 지나간다", "callback": _close_modal}
		]
	)


func _start_naval_battle(enemy: Dictionary) -> void:
	active_battle_enemy = enemy
	battle_distance = 2
	battle_turn = 1
	battle_log = "[color=#77ddff]▶ 제1턴: %s 함대와의 해전이 개시되었습니다! (현재 거리: %d)[/color]\n" % [
		enemy.get("captain_name", ""), battle_distance
	]
	_render_naval_battle_modal()


func _render_naval_battle_modal() -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var enemy := active_battle_enemy
	var dist_names := ["백병전 밀착(0)", "근거리(1)", "중거리(2)", "원거리(3)"]
	var d_str: String = dist_names[clampi(battle_distance, 0, 3)]

	var body := "[color=#ffd866]【해상 함대결전 (Naval Combat) — 제%d턴 | 거리: %s】[/color]\n" % [battle_turn, d_str]
	body += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	body += "🚢 [아군 기함] [b]%s[/b] (%s) — 내구: [color=#77ff77]%d/%d[/color] | 선원: [color=#77ff77]%d명[/color]\n" % [
		ship["name"], ship.get("type_name", ""), int(ship["hull"]), int(ship["max_hull"]), int(ship["crew"])
	]
	body += "🏴‍☠️ [적군 기함] [b]%s[/b] (%s) — 내구: [color=#ff7777]%d/%d[/color] | 선원: [color=#ff7777]%d명[/color]\n" % [
		enemy.get("ship_name", ""), enemy.get("ship_type_name", ""), int(enemy.get("hull", 0)), int(enemy.get("max_hull", 100)), int(enemy.get("crew", 0))
	]
	body += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	body += battle_log

	var actions: Array = [
		{"label": "포격 (Cannon Fire)", "callback": _naval_battle_action.bind("cannon")},
		{"label": "접근 기동 (Move In)", "callback": _naval_battle_action.bind("approach")},
		{"label": "육박 돌격 / 백병전", "callback": _naval_battle_action.bind("board")},
		{"label": "적장과 일기토 (1:1 Duel)", "callback": _start_captain_duel.bind(enemy)},
		{"label": "전장이탈 (퇴각)", "callback": _naval_battle_action.bind("retreat")}
	]
	_open_modal(
		"해전: vs %s (%s)" % [enemy.get("captain_name", ""), enemy.get("nation_name", "")],
		int(enemy.get("portrait_id", 61)),
		body,
		actions
	)


func _naval_battle_action(act: String) -> void:
	var ship: Dictionary = GameData.fleet_ships[0]
	var enemy := active_battle_enemy
	battle_turn += 1

	if act == "retreat":
		var esc_msg: String = GameData.system_messages[569] if GameData.system_messages.size() > 569 else "기함의 이탈로 인해 전투는 끝을 맺었다."
		_set_log_text("[color=#ffd866]%s[/color]" % esc_msg)
		_close_modal()
		return
	elif act == "approach":
		battle_distance = maxi(0, battle_distance - 1)
		battle_log = "• 아군 기함이 적 기함을 향해 전속력으로 접근합니다! (현재 거리: %d)\n" % battle_distance
	elif act == "cannon":
		var dmg := maxi(14, 28 - battle_distance * 4 + (int(ship["crew"]) / 5))
		enemy["hull"] = maxi(0, int(enemy["hull"]) - dmg)
		var e_crew_loss := maxi(2, dmg / 6)
		enemy["crew"] = maxi(0, int(enemy["crew"]) - e_crew_loss)
		battle_log = "• [포격중심] 아군 함대의 일제 포격! 적 기함에 [color=#ff9966]내구도 -%d, 선원 -%d명[/color] 타격!\n" % [dmg, e_crew_loss]
	elif act == "board":
		battle_distance = 0
		var my_atk := maxi(8, int(ship["crew"]) / 3 + 6)
		var en_atk := maxi(4, int(enemy["crew"]) / 5)
		enemy["crew"] = maxi(0, int(enemy["crew"]) - my_atk)
		ship["crew"] = maxi(5, int(ship["crew"]) - en_atk)
		battle_log = "• [돌격/백병전] 적함에 갈고리를 걸고 백병전을 벌입니다! (적 선원 -%d명, 아군 선원 -%d명)\n" % [my_atk, en_atk]

	# Check victory before enemy counter-attack
	if int(enemy["hull"]) <= 0 or int(enemy["crew"]) <= 0:
		_on_battle_victory(enemy)
		return

	# Enemy counter-attack
	var e_dmg := maxi(6, int(enemy.get("guns", 12)) / 2 - battle_distance * 2)
	ship["hull"] = maxi(10, int(ship["hull"]) - e_dmg)
	battle_log += "• 적 기함 『%s』의 반격 포격! 아군 기함 내구도 -%d 감소.\n" % [enemy.get("ship_name", ""), e_dmg]
	_refresh_hud()
	_render_naval_battle_modal()


func _start_captain_duel(enemy: Dictionary) -> void:
	## Authentic Uncharted Waters 2 1:1 Captain Duel (일기토):
	## Attack cards: 찌른다 (Thrust, #1058), 벤다 (Slash, #1059), 친다 (Strike, #1060)
	## Defense cards: 걷어낸다 (Parry, #1062), 맞받는다 (Block, #1063), 비킨다 (Dodge, #1064)
	active_battle_enemy = enemy
	duel_player_hp = 100
	duel_enemy_hp = 100
	duel_round = 1
	duel_is_player_attacking = true
	var d_intro: String = GameData.system_messages[1067] if GameData.system_messages.size() > 1067 else "적군의 제독이 일대일 승부를 걸어 왔습니다."
	duel_log = "[color=#ffd866]▶ %s[/color]\n" % d_intro
	_render_duel_modal()


func _render_duel_modal() -> void:
	var c := GameData.get_character(GameData.protagonist_id)
	var my_sword: int = int(c.get("stats", {}).get("swordplay", 75))
	if GameData.owned_item_ids.has(3): # 레이피어 보유 보너스
		my_sword += 15
	var enemy := active_battle_enemy
	var en_sword: int = int(enemy.get("swordplay", 70))

	var phase_str := ("제%d합 : 공 격 (공격 기술을 선택하십시오)" % duel_round) if duel_is_player_attacking else ("제%d합 : 방 어 (방어 기술을 선택하십시오)" % duel_round)
	var body := "[color=#ffdd66]【제독 일기토 (1:1 Captain Duel) — %s】[/color]\n" % phase_str
	body += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	body += "⚔️ [아군 제독] [b]%s[/b] (검술 %d) — 체력(HP): [color=#77ff77]%d / 100[/color]\n" % [
		c.get("full_name", "주인공"), my_sword, duel_player_hp
	]
	body += "🗡️ [적군 제독] [b]%s[/b] (검술 %d) — 체력(HP): [color=#ff7777]%d / 100[/color]\n" % [
		enemy.get("captain_name", "적장"), en_sword, duel_enemy_hp
	]
	body += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	body += duel_log

	var actions: Array = []
	if duel_is_player_attacking:
		actions.append({"label": "찌 른 다 (Thrust)", "callback": _execute_duel_exchange.bind(0)})
		actions.append({"label": "벤  다 (Slash)", "callback": _execute_duel_exchange.bind(1)})
		actions.append({"label": "친  다 (Strike)", "callback": _execute_duel_exchange.bind(2)})
	else:
		actions.append({"label": "걷어낸다 (Parry vs 찌른다)", "callback": _execute_duel_exchange.bind(0)})
		actions.append({"label": "맞받는다 (Block vs 벤다)", "callback": _execute_duel_exchange.bind(1)})
		actions.append({"label": "비킨다 (Dodge vs 친다)", "callback": _execute_duel_exchange.bind(2)})

	_open_modal(
		"일기토: %s vs %s" % [c.get("given_name", ""), enemy.get("captain_name", "")],
		int(enemy.get("portrait_id", 61)),
		body,
		actions
	)


func _execute_duel_exchange(player_move: int) -> void:
	var atk_names := ["찌 른 다", "벤  다", "친  다"]
	var def_names := ["걷어낸다", "맞받는다", "비킨다"]
	var ai_move := (duel_round + int(active_battle_enemy.get("captain_id", 1))) % 3

	if duel_is_player_attacking:
		# Player attacks with player_move (0..2), AI defends with ai_move (0..2)
		# If AI picks matching defense (ai_move == player_move), attack is parried and turn flips!
		if ai_move == player_move:
			duel_log = "• [제%d합 공격] 아군의 [b]『%s』[/b] 공격을 적장이 [b]『%s』[/b]로 막아냈습니다! (공수 교대)\n" % [
				duel_round, atk_names[player_move], def_names[ai_move]
			]
			duel_is_player_attacking = false
		else:
			var dmg := 34 + (player_move * 5)
			duel_enemy_hp = maxi(0, duel_enemy_hp - dmg)
			duel_log = "• [제%d합 명중!] 아군의 [b]『%s』[/b] 공격이 적장의 『%s』 빈틈을 찔렀습니다! ([color=#ff9966]적 체력 -%d[/color])\n" % [
				duel_round, atk_names[player_move], def_names[ai_move], dmg
			]
	else:
		# AI attacks with ai_move (0..2), Player defends with player_move (0..2)
		if player_move == ai_move:
			duel_log = "• [제%d합 방어 성공!] 적장의 [b]『%s』[/b] 공격을 [b]『%s』[/b]로 완벽히 받아쳤습니다! (공수 교대)\n" % [
				duel_round, atk_names[ai_move], def_names[player_move]
			]
			duel_is_player_attacking = true
		else:
			var dmg := 18
			duel_player_hp = maxi(10, duel_player_hp - dmg)
			duel_log = "• [제%d합 피격] 적장의 [b]『%s』[/b] 공격에 당했습니다! (아군 체력 -%d)\n" % [
				duel_round, atk_names[ai_move], dmg
			]

	duel_round += 1
	if duel_enemy_hp <= 0:
		active_battle_enemy["crew"] = 0
		active_battle_enemy["hull"] = 0
		_on_battle_victory(active_battle_enemy, true)
		return

	_render_duel_modal()


func _on_battle_victory(enemy: Dictionary, won_by_duel: bool = false) -> void:
	var loot_gold: int = int(enemy.get("gold", 650))
	GameData.gold_coins += loot_gold
	GameData.piracy_fame += 35
	var c := GameData.get_character(GameData.protagonist_id)
	c["combat_exp"] = int(c.get("combat_exp", 0)) + 40
	if int(c["combat_exp"]) >= 100:
		c["combat_level"] = int(c.get("combat_level", 1)) + 1
		c["combat_exp"] = int(c["combat_exp"]) - 100

	# Check if active guild quest was hunting this pirate
	var quest_bonus_str := ""
	if not GameData.active_guild_quest.is_empty() and GameData.active_guild_quest.get("type", "") == "pirate":
		GameData.active_guild_quest["completed"] = true
		quest_bonus_str = "\n★ [조합 의뢰 달성]: 해적 토벌 임무를 완수했습니다! 조합에서 보수를 수령하십시오."

	var win_header: String = GameData.system_messages[1066] if won_by_duel and GameData.system_messages.size() > 1066 else "적 기함은 백기를 올리고 항복 의사를 표시했다!"
	var body := "[color=#66ff88]【해전 및 일기토 승리!】[/color]\n\n%s\n\n" % win_header
	body += "• 격파한 함대: [b]%s[/b] (%s %s)\n" % [enemy.get("captain_name", ""), enemy.get("nation_name", ""), enemy.get("role", "")]
	body += "• 전리품 획득: [color=#ffd866]금화 +%d 닢[/color]\n" % loot_gold
	body += "• 해적/전투 명성: [color=#77ddff]+35 (현재 %d)[/color] | 전투 경험치 +40%s" % [GameData.piracy_fame, quest_bonus_str]

	_refresh_hud()
	_open_modal(
		"전투 승리 — %s 함대 격파!" % enemy.get("captain_name", ""),
		int(c.get("portrait_id", GameData.protagonist_id)),
		body,
		[{"label": "전리품을 챙기고 항해 계속", "callback": _close_modal}]
	)

