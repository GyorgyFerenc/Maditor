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
    //playground(); return;

    context.allocator      = mem.panic_allocator();
    context.temp_allocator = mem.panic_allocator();

    rl.SetConfigFlags({.WINDOW_RESIZABLE});

    rl.InitWindow(1080, 720, "Maditor");
    defer rl.CloseWindow();
    rl.SetExitKey(.KEY_NULL);

    app: App;
    init(&app);

    when ODIN_DEBUG{
        //open_to_text_window("test.temp", &app);
    }

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
            //test(&app);

            if app.draw_fps do rl.DrawFPS(0, 0);
        rl.EndDrawing();
    }
}

test :: proc(app: ^App){
    ctx := Draw_Context{box = {{0, 0}, {1080, 720}}};
    r := 'a';
    font := app.settings.font;
    size : f32 = 100;
    box := measure_rune(ctx, r, size, font.font);
    width := measure_rune_draw_width(r, size, font.font);

    draw_box(ctx, {{0, 0}, {width, 100}}, rl.BLUE);
    draw_box(ctx, box, rl.RED);
    draw_rune(ctx, r, size, font.font, {0, 0}, rl.GREEN);

    str := "kecske ment a kis kertbe;;;;     ";

    fmt.println(" ");
    for r in str{
        //info := rl.GetGlyphInfo(font.font, r);
        width := measure_rune_draw_width(r, size, font.font);
        fmt.println(r, "->", width);
    }
    fmt.println(" ");
}

playground :: proc(){
}

