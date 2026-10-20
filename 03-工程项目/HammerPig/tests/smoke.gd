extends SceneTree
var game
var checks := 0

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    if not ok:
        push_error("FAIL: " + message)
        quit(1)
    assert(ok, message)
    checks += 1
    print("PASS: ", message)

func click(point: Vector2) -> void:
    game.cooldown = 0.0
    game.strike(point)

func break_pig(index: int) -> void:
    var point: Vector2 = game.pigs[index].position
    click(point)
    click(point)

func run() -> void:
    game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    check(game.pigs.size() == 8 and game.score == 0, "initial scene and eight pigs")
    click(Vector2(0, 0))
    check(game.hits == 0 and game.score == 0, "miss gives no points")
    click(game.pigs[0].position)
    check(game.pigs[0].hp == 1 and game.score == 0, "first hit cracks pig")
    game.strike(game.pigs[0].position)
    check(game.pigs[0].hp == 1, "cooldown blocks rapid duplicate hit")
    click(game.pigs[0].position)
    check(game.score == 10 and game.broken == 1 and game.pigs[0].hp == 0, "second hit breaks pig and scores")
    click(game.pigs[0].position)
    check(game.score == 10, "dead pig cannot score twice")
    game._process(0.9)
    check(game.pigs[0].hp == 2, "broken pig respawns")
    for i in range(4):
        break_pig(i)
    check(game.score == 50 and game.phase == "card", "50 points opens card")
    click(game.pigs[4].position)
    check(game.pigs[4].hp == 2 and game.score == 50, "modal card blocks gameplay")
    var key := InputEventKey.new()
    key.pressed = true
    key.keycode = KEY_SPACE
    game._unhandled_input(key)
    check(game.phase == "playing", "space closes placeholder card")
    game._process(0.9)
    for i in range(5):
        break_pig(i)
    check(game.score == 100 and game.phase == "card", "100 points opens second card")
    game.apply_card()
    game._process(0.9)
    break_pig(0)
    break_pig(1)
    check(game.score == 120 and game.phase == "finished", "target ends round")
    click(game.pigs[7].position)
    check(game.score == 120, "finished round blocks scoring")
    key.keycode = KEY_R
    game._unhandled_input(key)
    check(game.score == 0 and game.phase == "playing" and game.next_card == 50, "R resets score phase and card threshold")
    check(game.particles.is_empty() and game.broken == 0 and game.pigs[0].hp == 2, "reset clears effects and restores pigs")
    print("ALL ", checks, " CHECKS PASSED")
    game.sound.stop()
    await create_timer(0.25).timeout
    game.queue_free()
    game = null
    await process_frame
    await process_frame
    quit()
