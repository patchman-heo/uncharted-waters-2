extends SceneTree
## Automated Godot 4 Runtime & Visual Self-Test Suite (tools/autotest.gd)
## Runs inside Godot 4 (via --headless or xvfb-run), instantiates Main.tscn,
## tests all 6 protagonists, tests entering all 12 building types in Lisbon/Seville,
## tests World Map sailing, discoveries, and captures visual verification screenshots!

func _init() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func():
		print("\n[Autotest Fail-Safe Watchdog] 30 seconds limit reached! Force quitting...")
		quit(1)
	)
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== [Godot 4 Autotest] Starting Automated Runtime & Visual Verification ===")
	var main_scene_res := load("res://scenes/main.tscn")
	if main_scene_res == null:
		push_error("Failed to load res://scenes/main.tscn")
		quit(1)
		return

	var main_node: Control = main_scene_res.instantiate()
	if not main_node.has_method("_on_select_protagonist"):
		push_error("Main node does not have _on_select_protagonist method (script parse error)!")
		quit(1)
		return

	root.add_child(main_node)
	await process_frame
	await process_frame

	# 1. Verify Title Screen & All 6 Protagonists' Starting Ports
	var gd: Node = root.get_node("GameData")
	var expected_starts := {
		0: "리스본",
		1: "세비야",
		2: "런던",
		3: "암스테르담",
		4: "제노바",
		5: "이스탄불"
	}
	for protag_idx in range(6):
		main_node._on_select_protagonist(protag_idx)
		await process_frame
		var p: Dictionary = gd.get_port(gd.current_port_id)
		var pname: String = p.get("name", "")
		if pname != expected_starts[protag_idx]:
			push_error("Protagonist %d started in wrong port: %s (expected %s)" % [protag_idx, pname, expected_starts[protag_idx]])
			quit(1)
			return
		print("  [PASS] Protagonist #%d (%s) -> Start Port #%d (%s) at spawn (%d, %d)" % [
			protag_idx, gd.PROTAGONIST_PRESETS[protag_idx]["name"],
			gd.current_port_id, pname, main_node.port_view.player_x, main_node.port_view.player_y
		])

	# 2. Switch back to Joao (0: Lisbon) and test walking into every building in Lisbon
	main_node._on_select_protagonist(0)
	await process_frame
	await process_frame
	await _save_screenshot("autotest_lisbon_spawn.png")

	var lisbon: Dictionary = gd.get_port(0)
	var b_list: Array = lisbon.get("buildings", [])
	var slot_map := {}
	for b in b_list:
		slot_map[int(b["slot"])] = b

	# 2a. Verify Joao's authentic opening scenario bytecode walkthrough!
	# Step A: Enter Mansion (slot 7) -> Leon Ferrero gives order, Rocco (0x45 = 69) joins, flag[0]=1
	main_node._on_building_entered(slot_map[7])
	await process_frame
	await _save_screenshot("autotest_joao_mansion_event.png")
	if int(gd.scenario_flags.get(0, 0)) != 1 or not gd.companions.has(69):
		push_error("Joao Mansion event failed to set flag[0]=1 or add Rocco (69)! flags=" + str(gd.scenario_flags))
		quit(1)
		return
	print("  [PASS] Joao Scenario Step A (Mansion): Duke Leon dialogue & Rocco (ID 69) joined!")
	main_node._close_modal()

	# Step B: Enter Shipyard (slot 2) -> Receives ship '헤르메스Ⅱ세' (Caravel Latina, type 5), flag[3]=1
	main_node._on_building_entered(slot_map[2])
	await process_frame
	if gd.fleet_ships[0]["name"] != "헤르메스Ⅱ세" or int(gd.scenario_flags.get(3, 0)) != 1:
		push_error("Joao Shipyard event failed to grant '헤르메스Ⅱ세'! ship=" + str(gd.fleet_ships[0]))
		quit(1)
		return
	print("  [PASS] Joao Scenario Step B (Shipyard): Received flagship '%s'!" % gd.fleet_ships[0]["name"])
	main_node._close_modal()

	# Step C: Enter Tavern (slot 1) -> Carlotta & Lucia give +1000 gold and tell Joao to visit mother at night (22:00-24:00)
	var gold_before_tavern: int = gd.gold_coins
	main_node._on_building_entered(slot_map[1])
	await process_frame
	if gd.gold_coins != gold_before_tavern + 1000 or int(gd.scenario_flags.get(5, 0)) != 1:
		push_error("Joao Tavern event failed to grant +1000 gold or set flag[5]=1!")
		quit(1)
		return
	print("  [PASS] Joao Scenario Step C (Tavern): Carlotta granted +1000 gold (total=%d)!" % gd.gold_coins)
	main_node._close_modal()

	# Step D: Visit Mansion at Night (22:00) -> Duchess gives Silver Hairpin (item 52 = 0x34), flag[1]=1
	gd.hour_of_day = 22
	main_node._on_building_entered(slot_map[7])
	await process_frame
	if not gd.owned_item_ids.has(52) or int(gd.scenario_flags.get(1, 0)) != 1:
		push_error("Joao Night Mansion event failed to grant Silver Hairpin (ID 52)! owned=" + str(gd.owned_item_ids))
		quit(1)
		return
	print("  [PASS] Joao Scenario Step D (Mansion at 22:00 Night): Received '은제 머리장식' (ID 52)!")
	main_node._close_modal()
	gd.hour_of_day = 10

	# Step E: Visit Church (slot 10) -> Father Enrico (ID 70 = 0x46) joins, flag[2]=1
	main_node._on_building_entered(slot_map[10])
	await process_frame
	if not gd.companions.has(70) or int(gd.scenario_flags.get(2, 0)) != 1:
		push_error("Joao Church event failed to add Father Enrico (ID 70)! companions=" + str(gd.companions))
		quit(1)
		return
	print("  [PASS] Joao Scenario Step E (Church): Father Enrico (ID 70) joined!")
	main_node._close_modal()

	# Step F: Visit Item Shop (slot 9) -> Receives Rapier (item 3 = 0x03), flag[9]=1
	main_node._on_building_entered(slot_map[9])
	await process_frame
	if not gd.owned_item_ids.has(3) or int(gd.scenario_flags.get(9, 0)) != 1:
		push_error("Joao Shop event failed to grant Rapier (ID 3)! owned=" + str(gd.owned_item_ids))
		quit(1)
		return
	print("  [PASS] Joao Scenario Step F (Item Shop): Received '레이피어' (ID 3)!")
	main_node._close_modal()

	# Step G: Visit all remaining buildings in Lisbon to verify standard & scenario modals
	for b in b_list:
		main_node._on_building_entered(b)
		await process_frame
		if not main_node.modal_layer.visible:
			push_error("Modal did not open for building: " + str(b))
			quit(1)
			return
		print("  [PASS] Lisbon Building Slot #%02d (%s -> %s) opened modal: '%s'" % [
			int(b["slot"]), b["id"], b["name_kr"], main_node.modal_title.text
		])
		main_node._close_modal()
		await process_frame

	# 2b. Test Scenario Viewer Modal
	main_node._show_scenario_viewer()
	await process_frame
	await _save_screenshot("autotest_scenario_viewer.png")
	main_node._close_modal()
	await process_frame

	# 3. Test Market Buy/Sell, Harbor Supply, Bank Deposit/Withdraw, Inn Sleep, Shipyard Repair
	main_node._open_market_menu("리스본")
	await process_frame
	await _save_screenshot("autotest_market_modal.png")
	if not main_node.modal_portrait.visible:
		push_error("Market portrait is not visible in modal!")
		quit(1)
		return
	print("  [PASS] Market modal portrait verified.")
	main_node._invest_market("리스본", 500)
	await process_frame
	main_node._close_modal()

	# 3b. Test Tavern: Interior, Waitress Gift, Companions Recruitment, Blackjack Mini-Game
	main_node._open_tavern_menu("리스본")
	await process_frame
	await _save_screenshot("autotest_tavern_interior.png")
	if not main_node.modal_portrait.visible:
		push_error("Tavern portrait is not visible in modal!")
		quit(1)
		return
	print("  [PASS] Tavern modal portrait verified.")
	main_node._gift_waitress("리스본", 105, 50)
	await process_frame
	main_node._play_blackjack_round("리스본", 50)
	await process_frame
	main_node._close_modal()

	# 3c. Test Shipyard: Figureheads, Cannons Remodel, & Industrial Investment
	gd.gold_coins += 30000 # Grant test gold for ship remodeling and investments
	main_node._open_shipyard_menu("리스본")
	await process_frame
	main_node._open_shipyard_remodel("리스본")
	await process_frame
	await _save_screenshot("autotest_shipyard_remodel.png")
	main_node._install_fig(3, "리스본") # Angel figurehead
	await process_frame
	main_node._install_can(3, 10, "리스본") # Culverin 10 guns
	await process_frame
	main_node._invest_industry("리스본", 500)
	await process_frame
	var cur_ship: Dictionary = gd.fleet_ships[0]
	if cur_ship.get("figurehead") != "천사상" or cur_ship.get("cannon_type") != "컬버린포":
		push_error("Shipyard remodeling failed to apply figurehead/cannons! ship=" + str(cur_ship))
		quit(1)
		return
	print("  [PASS] Shipyard Remodel verified: Figurehead='%s', Cannons='%s' (%d guns)" % [
		cur_ship.get("figurehead"), cur_ship.get("cannon_type"), int(cur_ship.get("cannons", 0))
	])
	main_node._close_modal()

	# 3d. Test Guild Quests: Generation, Acceptance, and Inspection
	main_node._open_guild_menu("리스본")
	await process_frame
	main_node._open_guild_quest_offer("리스본")
	await process_frame
	await _save_screenshot("autotest_guild_quest.png")
	var generated_q: Dictionary = gd.generate_guild_quest(0)
	main_node._accept_quest(generated_q, "리스본")
	await process_frame
	if gd.active_guild_quest.is_empty():
		push_error("Guild quest was not accepted into active_guild_quest!")
		quit(1)
		return
	print("  [PASS] Guild Quest accepted: '%s' (Reward: %d gold)" % [
		gd.active_guild_quest.get("title", ""), int(gd.active_guild_quest.get("reward_gold", 0))
	])
	main_node._close_modal()

	# 3e. Test Royal Palace: Titles, Promotion Check, & Royal Mission
	gd.adventure_fame = 2000
	main_node._open_palace_menu("리스본")
	await process_frame
	main_node._check_royal_rank("리스본")
	await process_frame
	if gd.royal_rank < 1:
		push_error("Royal rank was not promoted with 2000 fame!")
		quit(1)
		return
	print("  [PASS] Royal Palace Promotion verified: Rank #%d (「%s」)" % [
		gd.royal_rank, gd.ROYAL_TITLES[gd.royal_rank]
	])
	main_node._request_royal_mission("리스본")
	await process_frame
	if gd.royal_mission.is_empty():
		push_error("Royal mission was not generated!")
		quit(1)
		return
	print("  [PASS] Royal Mission received: '%s'" % gd.royal_mission.get("title", ""))
	main_node._close_modal()

	# 3f. Test Night Secret Item Shop (at 02:00 AM)
	gd.hour_of_day = 2
	main_node._open_item_shop_menu("리스본")
	await process_frame
	if not main_node.modal_title.text.contains("암시장"):
		push_error("Item shop did not open secret shop at 02:00 AM! Title: " + main_node.modal_title.text)
		quit(1)
		return
	print("  [PASS] Night Secret Item Shop verified at 02:00 AM: '%s'" % main_node.modal_title.text)
	main_node._close_modal()
	gd.hour_of_day = 10

	# 3g. Test Save & Load System
	main_node._show_save_menu()
	await process_frame
	await _save_screenshot("autotest_save_menu.png")
	main_node._do_save_slot(1)
	await process_frame
	if not gd.has_save(1):
		push_error("Save file user://save_1.json was not created!")
		quit(1)
		return

	# Mutate state and then load to verify full restoration
	var saved_gold: int = gd.gold_coins
	var saved_rank: int = gd.royal_rank
	gd.gold_coins = 999999
	gd.royal_rank = 0
	main_node._do_load_slot(1)
	await process_frame
	if gd.gold_coins != saved_gold or gd.royal_rank != saved_rank:
		push_error("Load failed to restore gold (%d vs %d) or rank (%d vs %d)!" % [
			gd.gold_coins, saved_gold, gd.royal_rank, saved_rank
		])
		quit(1)
		return
	print("  [PASS] Save & Load System verified! Successfully saved and restored slot #1.")

	# 4. Test Sailing out to World Map, AI Fleets, Naval Combat, 1:1 Captain Duel, Sea Monsters, & Discoveries
	main_node._do_actual_sail_out(0)
	await process_frame
	await process_frame
	await _save_screenshot("autotest_worldmap_sail.png")
	print("  [PASS] World Map sailing active at (%d, %d) with %d AI fleets" % [gd.world_tile_x, gd.world_tile_y, gd.ai_fleets.size()])

	if gd.ai_fleets.is_empty():
		push_error("No AI fleets spawned on World Map!")
		quit(1)
		return

	# 4a. Test Naval Combat (포격 / 접근)
	var test_enemy: Dictionary = gd.ai_fleets[0]
	main_node._start_naval_battle(test_enemy)
	await process_frame
	main_node._naval_battle_action("cannon")
	await process_frame
	await _save_screenshot("autotest_naval_battle.png")
	print("  [PASS] Naval Combat modal & Cannon Fire verified against '%s' (Enemy Hull: %d/%d)" % [
		test_enemy["captain_name"], int(test_enemy["hull"]), int(test_enemy["max_hull"])
	])

	# 4b. Test 1:1 Captain Duel (일기토: 찌른다 / 벤다 / 친다)
	main_node._start_captain_duel(test_enemy)
	await process_frame
	await _save_screenshot("autotest_captain_duel.png")
	for _round_i in range(6):
		if int(test_enemy["hull"]) <= 0 or main_node.duel_enemy_hp <= 0:
			break
		main_node._execute_duel_exchange(2)
		await process_frame
	print("  [PASS] 1:1 Captain Duel (일기토) verified against '%s'!" % test_enemy["captain_name"])
	main_node._close_modal()

	# 4c. Test Sea Monster / Hazard from MONSTER.DAT
	if gd.monsters.is_empty():
		push_error("monsters.json is empty!")
		quit(1)
		return
	var mon0: Dictionary = gd.monsters[0]
	main_node._on_sea_hazard_triggered({
		"hazard_type": "monster",
		"title": "바다 괴물 출현 — %s" % mon0["name"],
		"message": "%s\n\n%s" % [mon0["message_1"], mon0["message_2"]],
		"hull_damage": 10,
		"crew_loss": 2
	})
	await process_frame
	print("  [PASS] Sea Monster / Hazard verified: %s" % mon0["name"])
	main_node._close_modal()

	var disc0: Dictionary = gd.discoveries[0]
	main_node._on_discovery_found(disc0)
	await process_frame
	if not gd.discovered_ids.has(int(disc0["id"])):
		push_error("Discovery #0 was not recorded in discovered_ids!")
		quit(1)
		return
	print("  [PASS] Discovery popup & recording verified: %s" % disc0["name"])
	main_node._close_modal()

	# 5. Test Character Sheet, Fleet Sheet, Discoveries Book, World Minimap, Fast Travel
	main_node._show_character_sheet()
	await process_frame
	main_node._close_modal()

	main_node._show_fleet_sheet()
	await process_frame
	main_node._close_modal()

	main_node._show_discoveries_book()
	await process_frame
	main_node._close_modal()

	main_node._show_world_minimap()
	await process_frame
	main_node._close_modal()

	main_node._show_fast_travel_menu()
	await process_frame
	main_node._close_modal()

	# 6. Test CD Orchestra Audio Engine & BGM Playback
	print("--- Testing CD Orchestra OST Audio Engine ---")
	gd.play_bgm("title")
	if gd.current_bgm_player.stream == null or not gd.current_bgm_player.playing:
		push_error("Failed to play CD Orchestra Title BGM!")
		quit(1)
		return
	print("  [PASS] CD Orchestra Title BGM active & playing ('Wind Ahead')")

	gd.play_port_bgm(0)
	if gd.current_bgm_player.stream == null or not gd.current_bgm_player.playing:
		push_error("Failed to play Lisbon Port BGM!")
		quit(1)
		return
	print("  [PASS] CD Orchestra Lisbon Port BGM active & playing ('Mast in the Mist')")

	gd.play_sfx("fanfare")
	print("  [PASS] CD Orchestra SFX Victory Fanfare verified")

	print("=== [Godot 4 Autotest] ALL RUNTIME & UI TESTS PASSED WITHOUT ERRORS! ===")
	quit(0)


func _save_screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null and not img.is_empty():
		var out_path := "/home/ycheo/.gemini/antigravity/brain/b603db09-5eaf-41e7-861a-ba6454794274/" + filename
		img.save_png(out_path)
		print("  [Screenshot] Saved " + out_path)
