package main

import "core:fmt"
import "core:mem"
import "core:time"
import "core:os"
import "core:c"

import rl "vendor:raylib"

import "src:Pool_Array"


App :: struct{
    gpa: mem.Allocator, // General Purpose Allocator
    fa:  mem.Allocator, // Frame Allocator

    running: bool,
    delta: f32, // miliseconds
    delta_duration: time.Duration,

    settings: Settings,
    copy_buffer: [dynamic]rune,
    draw_fps: bool,

    key_binds: struct{
        len: int,
        number: int,
        buffer: [50]Key,
        current_wait: f32,
        max_wait: f32,

        discard_rune: bool,
    },

    ui: struct{
        windows: Pool_Array.Pool_Array(Window),
        active_window: Window_Id,
        window_select: Maybe(Window_Id),
        file_explorer: Maybe(Window_Id),

        cmd: Command_Line,
        harpoon: Harpoon,
    },

    plugins: struct{
        odin_plugin: Odin_Plugin,
    },

    // Do not touch
    arena: mem.Arena, // The memory must be alive for the whole program but do not need the actual variable
}

init :: proc(app: ^App){
    app.running = true;

    // Allocators
    app.gpa = os.heap_allocator();
    buffer := make([]u8, 10 * mem.Megabyte, allocator = app.gpa);
    mem.arena_init(&app.arena, buffer);
    app.fa = mem.arena_allocator(&app.arena);
    app.copy_buffer = make([dynamic]rune, allocator = app.gpa);

    app.ui.windows = Pool_Array.create(Window, app.gpa);
    app.ui.active_window = Pool_Array.Null_Id;

    init_settings(&app.settings, app);

    reset_keybinds(app);

    init_command_line(&app.ui.cmd, app.gpa, app);
    init_harpoon(&app.ui.harpoon, app);
    init_odin_plugin(&app.plugins.odin_plugin, app);
}

update :: proc(app: ^App){
    detect_window_size_change(app);
    update_key_binds(app);
    global_key_binds(app);

    ui := &app.ui;
    update_command_line(&ui.cmd, app);
    update_harpoon(&app.ui.harpoon);

    window, ok := get_window(app, ui.active_window);
    if ok {
        window.box.pos = {0, 0};
        window.box.size = to_v2(app.settings.window.size);

        update_window(window, app);

        update_odin_plugin(&app.plugins.odin_plugin, app);

        draw_window(window, app);
    } else {
        show_default_screen(app);
    }

    draw_command_line(&ui.cmd, app);
    draw_harpoon(&app.ui.harpoon);
}

show_default_screen :: proc(app: ^App){
    color_scheme := app.settings.color_scheme;
    font := app.settings.font;
    ctx := Draw_Context{box = {{0, 0}, to_v2(app.settings.window.size)}};
    fill(ctx, color_scheme.background1);
    draw_text(ctx,
        text = "Maditor is a simple editor for the mentally deranged\nPress ctrl+; for typing commands.",
        pos  = {0, 0},
        font = font.font,
        size = font.size,
        hspacing = 1,
        color = color_scheme.text,
    );
}

global_key_binds :: proc(app: ^App){
    if match_key_bind(app, SELECT_WINDOW){
        open_window_select(app);
    }
    if match_key_bind(app, FILE_EXPLORER){
        open_file_explorer(app);
    }
}

discard_next_rune :: proc(app: ^App){
    when ODIN_OS == .Linux{
        app.key_binds.discard_rune = true;
    }
}

poll_rune :: proc(app: ^App) -> rune{
    app.key_binds.len = 0;
    r := rl.GetCharPressed();
    if r != 0{
        if !app.key_binds.discard_rune{
            return r;
        }
        app.key_binds.discard_rune = false;
    }
    return 0;
}

update_key_binds :: proc(app: ^App){
    key_binds := &app.key_binds;

    key, has := poll_key();

    if has {
        if key_binds.len >= 50 do return; 

        if key.key >= .ZERO && key.key <= .NINE{
            key_binds.number = key_binds.number * 10 + cast(int) (key.key - .ZERO);
        } else {
            key_binds.buffer[key_binds.len] = key;
            key_binds.len += 1;
        }
    } else {
        if key_binds.len == 0 do return;
        key_binds.current_wait += app.delta;
    }

    if key_binds.current_wait >= key_binds.max_wait{
        reset_keybinds(app);
    }
}

match_key_bind :: proc(app: ^App, key_bind: Key_Bind, number: ^int = nil) -> bool{
    // Todo(Ferenc): Move number out to another procedure

    if len(key_bind) != app.key_binds.len {
        return false;
    }

    for i in 0..<app.key_binds.len{
        if app.key_binds.buffer[i] != key_bind[i] do return false;
    }
    
    if number != nil{
        if app.key_binds.number == 0{
            number^ = 1;
        } else {
            number^ = app.key_binds.number;
        }
    }

    reset_keybinds(app);
    return true;
}

reset_keybinds :: proc(app: ^App){
    app.key_binds.len          = 0;
    app.key_binds.current_wait = 0;
    app.key_binds.number       = 0;
}

Key :: struct{
    key: rl.KeyboardKey,
    shift: bool,
    ctrl:  bool,
    alt:   bool,
    super: bool,
}

poll_key :: proc() -> (Key, bool){
    key := Key{
        key   = rl.GetKeyPressed(),
        shift = rl.IsKeyDown(.LEFT_SHIFT),
        ctrl  = rl.IsKeyDown(.LEFT_CONTROL),
        alt   = rl.IsKeyDown(.LEFT_ALT),
        super = rl.IsKeyDown(.LEFT_SUPER),
    };

    if key.key == .KEY_NULL     do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .LEFT_SHIFT   do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .LEFT_CONTROL do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .LEFT_ALT     do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .LEFT_SUPER   do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .RIGHT_SHIFT   do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .RIGHT_CONTROL do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .RIGHT_ALT     do return {}, false;	if key.key == .KEY_NULL      do return {}, false;
    if key.key == .RIGHT_SUPER   do return {}, false;	if key.key == .KEY_NULL      do return {}, false;

    return key, true;
}

Key_Bind :: []Key;

SELECT_WINDOW :: Key_Bind{Key{key = .P, ctrl = true}};
FILE_EXPLORER :: Key_Bind{Key{key = .T, ctrl = true}};




