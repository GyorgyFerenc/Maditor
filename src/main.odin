package main

import "core:fmt"
import "core:mem"
import "core:time"
import "core:math"
import "core:os"

import rl "vendor:raylib"

import "src:Buffer"
import "src:Pool_Array"


main :: proc(){
    {fmt.println("Playground"); playground(); return;}

    context.allocator      = mem.panic_allocator();
    context.temp_allocator = mem.panic_allocator();

    rl.SetConfigFlags({.WINDOW_RESIZABLE});

    rl.InitWindow(1080, 720, "Maditor");
    defer rl.CloseWindow();
    rl.SetExitKey(.KEY_NULL);
    rl.SetTargetFPS(144);

    app: App;
    init(&app);

    when ODIN_DEBUG{
        open_to_text_window("test.temp", &app);
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

import "src:Operation_Stack"

playground :: proc(){
    alloc := context.allocator;
    t: mem.Tracking_Allocator;
    mem.tracking_allocator_init(&t, alloc);
    defer {
        fmt.println(t.total_memory_allocated);
        fmt.println(t.total_memory_freed);
    };
    
    alloc = mem.tracking_allocator(&t);
    
    g := create_growth_allocator(alloc, 4 * mem.Kilobyte);
    defer destroy_growth_allocator(g);
    
    a := growth_allocator(&g);
    
    asd := make([dynamic]int, allocator = a);
    append(&asd, 12);
    append(&asd, 12);
    append(&asd, 12);
    
    for _ in 0..<10{
    basd := make(map[string]int, allocator = a);
    basd["kecske"] = 12;
    basd["asd"] = 1243;
    }
    
    //_ = make([]u8, 1 * mem.Kilobyte, allocator = a);
    //_ = make([]u8, 2 * mem.Kilobyte, allocator = a);
}




