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

    key_binds: struct{
        len: int,
        buffer: [50]Key,
        current_wait: f32,
        max_wait: f32,

        discard_rune: bool,
    },

    ui: struct{
        windows: Pool_Array.Pool_Array(Window),
        active_window: Window_Id,

        cmd: Command_Line,
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

    app.ui.windows = Pool_Array.create(Window, app.gpa);
    app.ui.active_window = Pool_Array.Null_Id;

    init_settings(&app.settings, app);
}

update :: proc(app: ^App){
    update_key_binds(app);

    global_key_binds(app);

    ui := &app.ui;
    window, ok := get_window(app, ui.active_window);
    if ok {
        window.box.pos = {0, 0};
        window.box.size = to_v2(app.settings.window.size);

        do_window(window, app);
    } else {
        show_default_screen(app);
    }
}

show_default_screen :: proc(app: ^App){
    rl.DrawText("Maditor is a simple editor for the mentally deranged\nPress : for typing commands.", 0, 0, 20, rl.WHITE);
}

global_key_binds :: proc(app: ^App){
    
}

discard_next_rune :: proc(app: ^App){
    app.key_binds.discard_rune = true;
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
        key_binds.buffer[key_binds.len] = key;
        key_binds.len += 1;
    } else {
        if key_binds.len == 0 do return;
        key_binds.current_wait += app.delta;
    }

    if key_binds.current_wait >= key_binds.max_wait{
        key_binds.current_wait = 0;
        key_binds.len = 0;
    }
}

match_key_bind :: proc(app: ^App, key_bind: Key_Bind) -> bool{
    if len(key_bind) != app.key_binds.len {
        return false;
    }

    for i in 0..<app.key_binds.len{
        if app.key_binds.buffer[i] != key_bind[i] do return false;
    }

    app.key_binds.len          = 0;
    app.key_binds.current_wait = 0;

    return true;
}

Settings :: struct{
    window: struct{
        size: v2i,
        fullscreen: bool,
    },
    key_binds: struct{
        max_wait: f32, // ms
    },
}

init_settings :: proc(s: ^Settings, app: ^App){
    s.window.size        = {1080, 720};
    s.window.fullscreen  = false;
    s.key_binds.max_wait = 1000 / 2; 

    apply(s^, app);
}

apply :: proc(s: Settings, app: ^App){
    if s.window.fullscreen{
        rl.SetWindowState({.FULLSCREEN_MODE});
    } else {
        rl.ClearWindowState({.FULLSCREEN_MODE});
    }

    rl.SetWindowSize(cast(c.int) s.window.size.x, cast(c.int) s.window.size.y);

    app.key_binds.max_wait = s.key_binds.max_wait;
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

	if key.key == .KEY_NULL      do return {}, false;
	if key.key == .LEFT_SHIFT    do return {}, false;
	if key.key == .LEFT_CONTROL  do return {}, false;
	if key.key == .LEFT_ALT      do return {}, false;
	if key.key == .LEFT_SUPER    do return {}, false;
	if key.key == .RIGHT_SHIFT   do return {}, false;
	if key.key == .RIGHT_CONTROL do return {}, false;
	if key.key == .RIGHT_ALT     do return {}, false;
	if key.key == .RIGHT_SUPER   do return {}, false;

    return key, true;
}

Key_Bind :: []Key;
