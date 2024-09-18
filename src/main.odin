package main

import "core:fmt"
import "core:mem"
import "core:time"
import "core:os"

import rl "vendor:raylib"

import "src:Buffer"
import "src:Pool_Array"


main :: proc(){
    context.allocator      = mem.panic_allocator();
    context.temp_allocator = mem.panic_allocator();

    rl.SetConfigFlags({.WINDOW_RESIZABLE});

    rl.InitWindow(1080, 720, "Maditor");
    defer rl.CloseWindow();
    rl.SetExitKey(.KEY_NULL);

    app: App;
    init(&app);

    open_to_text_window("test.temp", &app);
    //debug_settings(&app);

    start := time.now();
    for app.running{
        end := time.now();
        app.delta_duration = time.diff(start, end);
        app.delta = cast(f32) time.duration_milliseconds(app.delta_duration);
        start = end;
        free_all(app.fa);

        if rl.WindowShouldClose() do app.running = false;

        rl.BeginDrawing();
            rl.ClearBackground(rl.BLACK);
            
            update(&app);

        rl.EndDrawing();
    }
}

debug_settings :: proc(app: ^App){
}
