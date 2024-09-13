package main

import "core:c"
import "core:fmt"
import "core:unicode/utf8"
import rl "vendor:raylib"

import "src:Buffer"

Text_Window :: struct{
    using window_data: Window_Data,
    
    buffer: Buffer.Buffer,
    cursor: Buffer.Pos_Id,
}

do_text_window :: proc(self: ^Text_Window, app: ^App){
    /*
       Update
    */


    { // Draw
        begin_box_draw_mode(self.box);
        defer end_box_draw_mode();

        text_size :: 20;
        font := rl.GetFontDefault();
        start_x := self.box.pos.x;
        position := self.box.pos;
        spacing: f32 = 2;

        it := Buffer.iter(&self.buffer);
        cursor_i := Buffer.get_pos(self.buffer, self.cursor);
        for r, idx in Buffer.next(&it){
            size := measure_rune_size(r, font, text_size, spacing);
            cursor_pos := position;

            if r != '\n'{
                rl.DrawTextCodepoint(font, r, position, text_size, rl.WHITE);
                position.x += size.x + spacing;
            } else {
                position.y += text_size;
                position.x = start_x;
            }
            if cursor_i == idx{
                rl.DrawRectangleV(cursor_pos, size, rl.Color{0, 0, 0xFF, 0xBB});
            }
        }
    }
}

// This is janky do better lol
measure_rune_size :: proc(r: rune, font: rl.Font, fontSize: f32, spacing: f32) -> v2{
    str: [5]u8;
    encoded, size := utf8.encode_rune(r);
    for i in 0..<size{
        str[i] = encoded[i];
    }

    ptr := transmute(cstring) &str;
    return rl.MeasureTextEx(font, ptr, fontSize, spacing);

    //    let scale = size / cast(f32) font.baseSize;
    //    let rect = GetGlyphAtlasRec(font, rune);
    //    return rect.width * scale;
}

text_window_to_window :: proc(self: ^Text_Window) -> Window{
    return {
        window_data = &self.window_data,
        data = self,
        procedure = proc(data: rawptr, app: ^App){
            do_text_window(cast(^Text_Window) data, app);
        },
    };
}
