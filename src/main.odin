package main

import "core:fmt"
import "core:mem"
import "core:time"
import "core:math"
import "core:os"

import rl "vendor:raylib"

import "src:Buffer"
import "src:Pool_Array"
import "src:v2"


main :: proc(){
    context.allocator      = mem.panic_allocator();
    context.temp_allocator = mem.panic_allocator();

    rl.SetConfigFlags({.WINDOW_RESIZABLE});

    rl.InitWindow(1080, 720, "Maditor");
    defer rl.CloseWindow();
    rl.SetExitKey(.KEY_NULL);

    app: App;
    init(&app);

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
            
            //update(&app);
            test(&app);

        rl.EndDrawing();
    }
}

test :: proc(app: ^App){
    ctx := v2.Draw_Context{};
    ctx.box = v2.Box{
        pos = {0, 0},
        size = {1080, 720},
    };
    
    //v2.fill(ctx, rl.GRAY);
    settings := app.settings;
    font := settings.font.font;
    w: f32 = 100;
    v2.draw_box(ctx, {{100, 100}, {w, 200}}, rl.RED);
    v2.draw_text(ctx, "asd \tasd ad  asd asd asd ", 
        font = font, 
        size = 25, 
        pos = {100, 100},
        color = rl.WHITE,
        wrap = w,
        tab_size = 100,
    );
}

