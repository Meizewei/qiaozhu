extends Node2D
## 第四轮：锤子攻击范围可配置，范围内的猪会被同时敲中；每结束 5 轮弹出一次卡片。
## 体力耗尽即本轮结束；敲猪得金币存入存钱罐；小猪受击跳动；锤子 5% 暴击金币翻倍。

signal pig_broken(coins: int)
signal card_opened

const SETTINGS_PATH := "res://data/balance.json"
const CARD_RECT := Rect2(510, 290, 260, 250)
const CONTINUE_RECT := Rect2(535, 563, 210, 52)
const RESET_RECT := Rect2(1090, 36, 140, 46)
const PIG_BOUNDS := Rect2(210, 330, 860, 270) # 小猪活动范围（围栏内）
var settings: Dictionary
var pigs: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var coins := 0 # 存钱罐里的金币（跨轮保留）
var round_coins := 0 # 本轮获得的金币
var hits := 0
var broken := 0
var rounds_played := 0 # 已结束的轮数，每 5 轮弹卡
var phase := "playing" # playing / card / finished
var cooldown := 0.0
var swing := 0.0
var stamina := 100.0
var stamina_flash := 0.0
var hammer_position := Vector2(1030, 540)
var elapsed := 0.0
var font := SystemFont.new()
var sound: AudioStreamPlayer

func _ready() -> void:
    font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans SC", "Noto Sans CJK SC"])
    settings = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
    sound = AudioStreamPlayer.new()
    sound.stream = load("res://assets/hit.wav")
    sound.volume_db = -14
    add_child(sound)
    reset_game()

func random_pig_velocity() -> Vector2:
    var angle := randf_range(0.0, TAU)
    return Vector2(cos(angle), sin(angle)) * float(settings.pig_speed) * randf_range(0.7, 1.3)

func spawn_pigs() -> void:
    pigs.clear()
    for row in range(2):
        for col in range(4):
            pigs.append({
                "position": Vector2(300 + col * 225, 350 + row * 190),
                "hp": int(settings.pig_hp), "respawn": 0.0,
                "flash": 0.0, "hop": 0.0, "seed": float(row * 4 + col),
                "velocity": random_pig_velocity()
            })

func new_round() -> void:
    # 开始新一轮：保留存钱罐金币与轮数计数
    round_coins = 0
    hits = 0
    broken = 0
    phase = "playing"
    cooldown = 0.0
    swing = 0.0
    stamina = float(settings.stamina_max)
    stamina_flash = 0.0
    particles.clear()
    popups.clear()
    spawn_pigs()
    queue_redraw()

func reset_game() -> void:
    # 完全重开：清空存钱罐与轮数
    coins = 0
    rounds_played = 0
    new_round()

func end_round() -> void:
    rounds_played += 1
    if rounds_played % int(settings.card_every_rounds) == 0:
        phase = "card" # 每 5 轮弹出一次卡片
        card_opened.emit()
    else:
        phase = "finished"

func _process(delta: float) -> void:
    elapsed += delta
    cooldown = maxf(0.0, cooldown - delta)
    swing = maxf(0.0, swing - delta)
    stamina_flash = maxf(0.0, stamina_flash - delta)
    for pig in pigs:
        pig.flash = maxf(0.0, pig.flash - delta)
        pig.hop = maxf(0.0, pig.hop - delta)
    if phase == "playing":
        hammer_position = get_global_mouse_position()
        for pig in pigs:
            if pig.hp > 0:
                pig.position += pig.velocity * delta
                if pig.position.x < PIG_BOUNDS.position.x or pig.position.x > PIG_BOUNDS.end.x:
                    pig.velocity.x = -pig.velocity.x
                    pig.position.x = clampf(pig.position.x, PIG_BOUNDS.position.x, PIG_BOUNDS.end.x)
                if pig.position.y < PIG_BOUNDS.position.y or pig.position.y > PIG_BOUNDS.end.y:
                    pig.velocity.y = -pig.velocity.y
                    pig.position.y = clampf(pig.position.y, PIG_BOUNDS.position.y, PIG_BOUNDS.end.y)
            else:
                pig.respawn -= delta
                if pig.respawn <= 0.0:
                    pig.hp = int(settings.pig_hp)
                    pig.velocity = random_pig_velocity()
        if stamina < float(settings.stamina_cost):
            end_round() # 体力耗尽，本轮自动结束
    for i in range(particles.size() - 1, -1, -1):
        var p: Dictionary = particles[i]
        p.life -= delta
        p.position += p.velocity * delta
        p.velocity.y += 600.0 * delta
        if p.life <= 0.0:
            particles.remove_at(i)
    for i in range(popups.size() - 1, -1, -1):
        popups[i].life -= delta
        popups[i].position.y -= 48.0 * delta
        if popups[i].life <= 0.0:
            popups.remove_at(i)
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_R:
            reset_game()
        elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
            if phase == "card":
                apply_card()
            elif phase == "finished":
                new_round()
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var point := get_global_mouse_position()
        if RESET_RECT.has_point(point):
            reset_game()
        elif phase == "card":
            if CONTINUE_RECT.has_point(point) or CARD_RECT.has_point(point):
                apply_card()
        elif phase == "finished":
            if CONTINUE_RECT.has_point(point):
                new_round()
        else:
            strike(point)

func strike(point: Vector2) -> void:
    if phase != "playing" or cooldown > 0.0:
        return
    if stamina < float(settings.stamina_cost):
        stamina_flash = 0.4
        popups.append({"position": point + Vector2(-30, -40), "life": 0.7,
            "text": "体力不足"})
        return
    hammer_position = point
    swing = 0.16
    cooldown = float(settings.swing_cooldown)
    stamina = maxf(0.0, stamina - float(settings.stamina_cost))
    # 攻击范围：椭圆内的所有猪都会被同时敲中
    var range_x := float(settings.hammer_range_x)
    var range_y := float(settings.hammer_range_y)
    var landed := false
    var broke_any := false
    var crit_any := false
    for pig in pigs:
        var offset: Vector2 = (point - pig.position) / Vector2(range_x, range_y)
        if pig.hp > 0 and offset.length_squared() <= 1.0:
            landed = true
            hits += 1
            pig.hp -= 1
            pig.flash = 0.14
            pig.hop = 0.24 # 受击跳动
            var crit := randf() < float(settings.crit_chance)
            if pig.hp <= 0:
                broke_any = true
                if crit:
                    crit_any = true
                pig.respawn = float(settings.respawn_seconds)
                var gain := int(settings.coins_per_pig) * (int(settings.crit_multiplier) if crit else 1)
                coins += gain
                round_coins += gain
                broken += 1
                spawn_particles(pig.position)
                popups.append({"position": pig.position + Vector2(-24, -55), "life": 0.9,
                    "text": ("暴击 +" if crit else "+") + str(gain)})
                pig_broken.emit(gain)
    if landed:
        sound.pitch_scale = 1.35 if crit_any else (1.1 if broke_any else 0.85)
        sound.play()

func apply_card() -> void:
    # 收下卡片后直接开启下一轮；效果后续在这里接入
    if phase == "card":
        new_round()

func spawn_particles(center: Vector2) -> void:
    for i in range(16):
        var angle := randf_range(-PI, 0.0)
        particles.append({"position": center, "velocity": Vector2(cos(angle), sin(angle)) * randf_range(100, 260),
            "life": randf_range(0.4, 0.8), "coin": i % 3 == 0})

func text_at(value: String, pos: Vector2, size: int, color := Color("#f4eadd")) -> void:
    draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func panel(rect: Rect2, color: Color, radius := 18) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(radius)
    draw_style_box(style, rect)

func button(rect: Rect2, label: String, active := true) -> void:
    panel(rect, Color("#d49f59") if active else Color("#454b4c"), 12)
    var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
    text_at(label, Vector2(rect.get_center().x - width / 2, rect.position.y + 32), 21, Color("#252c2b"))

func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 800), Color("#202b2b"))
    draw_circle(Vector2(1050, 180), 380, Color("#263332"))
    text_at("敲小猪", Vector2(54, 71), 36)
    text_at("计科2403  /  第四轮：范围锤 · 五轮弹卡", Vector2(55, 103), 16, Color("#a4b6af"))
    button(RESET_RECT, "重新开始")
    panel(Rect2(52, 137, 1176, 98), Color("#303d3b"))
    # 存钱罐金币（左上角）
    text_at("存钱罐金币", Vector2(80, 174), 17, Color("#a4b6af"))
    draw_circle(Vector2(97, 205), 13, Color("#8a6a2f"))
    draw_circle(Vector2(97, 205), 10, Color("#f4c85f"))
    text_at(str(coins).pad_zeros(3), Vector2(120, 214), 32, Color("#efbc72"))
    text_at("敲碎 " + str(broken) + " 只 · 本轮 +" + str(round_coins), Vector2(280, 205), 24)
    text_at("每只两锤 · 敲碎 +" + str(int(settings.get("coins_per_pig", 5))) + " 金币", Vector2(560, 180), 18)
    text_at("暴击 " + str(int(float(settings.get("crit_chance", 0.05)) * 100)) + "% → 金币 ×" + str(int(settings.get("crit_multiplier", 2))) + " · 每 " + str(int(settings.get("card_every_rounds", 5))) + " 轮弹卡", Vector2(560, 211), 18, Color("#a4b6af"))
    # 体力条
    var stamina_max := float(settings.get("stamina_max", 100))
    var stamina_cost := float(settings.get("stamina_cost", 10))
    var low := stamina < stamina_cost * 3
    var bar_color := Color("#e06c5c") if low or stamina_flash > 0.0 else Color("#8fd0a8")
    if stamina_flash > 0.0:
        bar_color = Color("#e06c5c").lerp(Color.WHITE, 0.5 * sin(stamina_flash * 40) + 0.5)
    text_at("体力", Vector2(920, 174), 17, Color("#a4b6af"))
    text_at(str(int(stamina)) + " / " + str(int(stamina_max)), Vector2(920, 214), 26, bar_color)
    panel(Rect2(1060, 196, 140, 12), Color("#1f2b29"), 5)
    panel(Rect2(1060, 196, 140 * clampf(stamina / stamina_max, 0.0, 1.0), 12), bar_color, 5)
    panel(Rect2(120, 278, 1040, 396), Color("#141e1e"), 30)
    panel(Rect2(110, 260, 1060, 396), Color("#88694e"), 30)
    panel(Rect2(126, 276, 1028, 364), Color("#a88562"), 23)
    for y in range(300, 640, 34):
        draw_line(Vector2(144, y), Vector2(1138, y + 8), Color(0.28, 0.19, 0.12, 0.12), 2)
    for pig in pigs:
        if pig.hp > 0:
            draw_pig(pig)
        else:
            draw_set_transform(pig.position)
            draw_arc(Vector2.ZERO, 36, 0, TAU, 32, Color("#765d45"), 2)
            draw_set_transform(Vector2.ZERO)
    for p in particles:
        var color := Color("#f4c85f") if p.coin else Color("#e7a6a4")
        color.a = minf(1.0, p.life * 2.0)
        draw_circle(p.position, 6 if p.coin else 4, color)
    for p in popups:
        text_at(p.text, p.position, 28, Color("#ffe092"))
    var stamina_cost_text := str(int(settings.get("stamina_cost", 10)))
    text_at("移动鼠标瞄准 · 左键挥锤（-" + stamina_cost_text + " 体力）· R 清空重开", Vector2(320, 728), 22)
    text_at("范围内的猪会被一起敲中；体力耗尽本轮结束，每 5 轮弹出一次卡片。", Vector2(310, 764), 16, Color("#a4b6af"))
    if phase == "playing":
        draw_hammer()
    else:
        draw_rect(Rect2(0, 0, 1280, 800), Color(0.04, 0.07, 0.07, 0.78))
        if phase == "card":
            text_at("一张新的卡片", Vector2(533, 243), 30)
            panel(CARD_RECT, Color("#e6d7bc"), 22)
            panel(Rect2(527, 307, 226, 216), Color("#d5c2a0"), 15)
            text_at("?", Vector2(612, 414), 70, Color("#977d58"))
            text_at("空白卡 · 效果待接入", Vector2(549, 480), 18, Color("#64543e"))
            button(CONTINUE_RECT, "收下并继续")
            text_at("也可按空格继续", Vector2(573, 652), 17, Color("#b1c0b8"))
        else:
            panel(Rect2(385, 270, 510, 375), Color("#34423f"), 25)
            text_at("体力耗尽", Vector2(552, 345), 36)
            text_at("本轮 +" + str(round_coins) + " 金币 · 敲碎 " + str(broken) + " 只", Vector2(461, 416), 26, Color("#efbc72"))
            text_at("存钱罐共存 " + str(coins) + " 金币 · 第 " + str(rounds_played + 1) + " 轮", Vector2(453, 471), 22)
            button(CONTINUE_RECT, "再来一轮")
            text_at("按 R 清空存钱罐重开", Vector2(538, 652), 17, Color("#b1c0b8"))

func draw_pig(pig: Dictionary) -> void:
    var pos: Vector2 = pig.position
    if pig.flash > 0.0:
        pos.x += sin(pig.flash * 90) * 8
    if pig.hop > 0.0:
        pos.y -= sin(pig.hop / 0.24 * PI) * 26 # 受击向上跳起
    var scale_y := 1.0 - 0.08 * sin(elapsed * 2 + pig.seed)
    draw_set_transform(pos, 0, Vector2(1, scale_y))
    draw_set_transform(pos + Vector2(0, 43), 0, Vector2(1, 0.25))
    draw_circle(Vector2.ZERO, 75, Color(0.12, 0.1, 0.08, 0.27))
    draw_set_transform(pos, 0, Vector2(1, scale_y))
    draw_line(Vector2(-64, -5), Vector2(-88, -16), Color("#eab2b0"), 8)
    draw_arc(Vector2(-88, -24), 9, 0.0, PI * 1.6, 16, Color("#eab2b0"), 5)
    draw_rect(Rect2(-44, 34, 18, 22), Color("#be8588"))
    draw_rect(Rect2(28, 34, 18, 22), Color("#be8588"))
    draw_set_transform(pos, 0, Vector2(1.25, scale_y))
    draw_circle(Vector2.ZERO, 56, Color("#d9959a"))
    draw_circle(Vector2(0, -5), 52, Color("#f0b6b5") if pig.flash <= 0.0 else Color("#ffe5d3"))
    draw_set_transform(pos, 0, Vector2(1, scale_y))
    draw_colored_polygon(PackedVector2Array([Vector2(23, -39), Vector2(39, -69), Vector2(53, -32)]), Color("#e7a5aa"))
    draw_colored_polygon(PackedVector2Array([Vector2(-13, -45), Vector2(0, -71), Vector2(17, -44)]), Color("#e7a5aa"))
    draw_line(Vector2(-21, -32), Vector2(8, -34), Color("#81595f"), 5)
    draw_circle(Vector2(31, -13), 5, Color("#433b3a"))
    draw_circle(Vector2(33, -15), 1.5, Color.WHITE)
    draw_set_transform(pos + Vector2(53, 10), 0, Vector2(1.15, 0.8 * scale_y))
    draw_circle(Vector2.ZERO, 23, Color("#d78d98"))
    draw_circle(Vector2(-8, 1), 3.5, Color("#8e5b69"))
    draw_circle(Vector2(8, 1), 3.5, Color("#8e5b69"))
    draw_set_transform(pos, 0, Vector2(1, scale_y))
    if pig.hp < int(settings.pig_hp):
        draw_polyline(PackedVector2Array([Vector2(-26,-22), Vector2(-13,-9), Vector2(-23,5), Vector2(-7,23)]), Color("#985f69"), 3, true)
    draw_set_transform(Vector2.ZERO)

func draw_hammer() -> void:
    # 攻击范围指示：锤子周围的浅色椭圆即判定范围
    var range_x := float(settings.get("hammer_range_x", 84))
    var range_y := float(settings.get("hammer_range_y", 64))
    draw_set_transform(hammer_position, 0, Vector2(range_x, range_y))
    draw_arc(Vector2.ZERO, 1.0, 0, TAU, 64, Color(1, 1, 1, 0.09), 2.0)
    draw_set_transform(Vector2.ZERO)
    var angle := -0.4 - sin(swing / 0.16 * PI) * 0.8
    draw_set_transform(hammer_position + Vector2(13, -5), angle)
    panel(Rect2(11, -2, 17, 100), Color("#5e412f"), 6)
    panel(Rect2(8, -5, 15, 98), Color("#c59859"), 5)
    panel(Rect2(-42, -30, 108, 47), Color("#172323"), 9)
    panel(Rect2(-47, -37, 108, 47), Color("#9aafb0"), 9)
    draw_line(Vector2(-35,-27), Vector2(44,-27), Color("#d7e1d8"), 4)
    draw_set_transform(Vector2.ZERO)