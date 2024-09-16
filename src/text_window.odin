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

    mode: enum{
        Normal,
        Insert,
        Visual,
    },
}


do_text_window :: proc(self: ^Text_Window, app: ^App){
    /*
       Update
    */

    if match_key_bind(app, BACK_TO_NORMAL){
        self.mode = .Normal;
    }

    switch self.mode{
    case .Normal:
        if match_key_bind(app, NORMAL_MOVE_LEFT){
            move_cursor(self, .Left);
        }
        if match_key_bind(app, NORMAL_MOVE_RIGHT){
            move_cursor(self, .Right);
        }
        if match_key_bind(app, NORMAL_MOVE_UP){
            move_cursor(self, .Up);
        }
        if match_key_bind(app, NORMAL_MOVE_DOWN){
            move_cursor(self, .Down);
        }
        if match_key_bind(app, NORMAL_GO_TO_INSERT){
            self.mode = .Insert;
            discard_next_rune(app);
        }
        if match_key_bind(app, NORMAL_REMOVE_RUNE){
            Buffer.remove_rune(&self.buffer, self.cursor);
            move_cursor(self, .Right);
        }
        if match_key_bind(app, NORMAL_SAVE){
            ok := Buffer.save(self.buffer, app.fa);
            fmt.println(ok);
        }
    case .Insert:
        r := poll_rune(app);
        if r != 0{
            Buffer.insert_rune(&self.buffer, self.cursor, r);
        }

        if match_key_bind(app, INSERT_REMOVE_RUNE){
            Buffer.remove_rune_left(&self.buffer, self.cursor);
        }
    case .Visual:
    }


    { // Draw
        text_size :: 20;
        font := rl.GetFontDefault();
        spacing: f32 = 2;

        text_box, status_line := remove_padding_side(self.box, 30, .Bottom);
        
        {
            begin_box_draw_mode(status_line);
            defer end_box_draw_mode();

            text: cstring = "";
            switch self.mode{
            case .Normal: text = "NORMAL";
            case .Insert: text = "INSERT";
            case .Visual: text = "VISUAL";
            }
            
            rl.DrawTextEx(font, text, status_line.pos, text_size, spacing, rl.WHITE);
        }

        begin_box_draw_mode(text_box);
        defer end_box_draw_mode();

        start_x :=  text_box.pos.x;
        position := text_box.pos;

        it := Buffer.iter(self.buffer);
        cursor_i := Buffer.get_pos(self.buffer, self.cursor);
        for r, idx in Buffer.next(&it){
            size := measure_rune_size(r, font, text_size, spacing);
            cursor_pos := position;

            if r != '\n'{
                rl.DrawTextCodepoint(font, r, position, text_size, rl.WHITE);
                position.x += size.x + spacing;
                if cursor_i == idx{
                    rl.DrawRectangleV(cursor_pos, size, rl.Color{0, 0, 0xFF, 0xBB});
                }
            } else {
                position.y += text_size;
                position.x = start_x;
                if cursor_i == idx{
                    rl.DrawRectangleV(cursor_pos, {text_size, text_size}, rl.Color{0, 0, 0xFF, 0xBB});
                }
            }
        }
    }

    NORMAL_MOVE_LEFT    :: Key_Bind{Key{key = .H}};
    NORMAL_MOVE_RIGHT   :: Key_Bind{Key{key = .L}};
    NORMAL_MOVE_UP      :: Key_Bind{Key{key = .K}};
    NORMAL_MOVE_DOWN    :: Key_Bind{Key{key = .J}};
    NORMAL_REMOVE_RUNE  :: Key_Bind{Key{key = .X}};
    NORMAL_GO_TO_INSERT :: Key_Bind{Key{key = .I}};
    NORMAL_SAVE         :: Key_Bind{Key{key = .S}};

    // Insert
    INSERT_REMOVE_RUNE    :: Key_Bind{Key{key = .BACKSPACE}};
    
    // All
    BACK_TO_NORMAL :: Key_Bind{Key{key = .C, ctrl = true}};
}

move_cursor :: proc(self: ^Text_Window, direction: enum{Left, Right, Up, Down}){
    cursor_pos := Buffer.get_pos(self.buffer, self.cursor);
    move_left  := direction == .Left;
    move_right := direction == .Right;
    move_up    := direction == .Up;
    move_down  := direction == .Down;

    if move_left || move_right{
        new_position := cursor_pos;
        if move_left{
            new_position -= 1;
        } else {
            new_position += 1;
        }

        r := Buffer.get_rune_i(self.buffer, new_position);
        if r != 0 && r != '\n'{
            Buffer.set_pos(&self.buffer, self.cursor, new_position);
        }
    }

    if move_up || move_down{
        line_end   := Buffer.find_line_end_i(self.buffer, cursor_pos);
        line_begin := Buffer.find_line_begin_i(self.buffer, cursor_pos);
        new_position := cursor_pos;
        pos_from_begin := cursor_pos - line_begin;
        if move_up{
            new_position = line_begin - 1;
            if new_position < 0 do new_position = 0;
        } else {
            new_position = line_end + 1;
            l := Buffer.length(self.buffer);
            if new_position >= l do new_position = l - 1;
        }

        line_end   =   Buffer.find_line_end_i(self.buffer,   new_position);
        line_begin =   Buffer.find_line_begin_i(self.buffer, new_position);
        new_position = clamp(line_begin + pos_from_begin, line_begin, line_end);
        Buffer.set_pos(&self.buffer, self.cursor, new_position);
    }

}

destroy_text_window :: proc(self: ^Text_Window, app: ^App){
    Buffer.destroy(self.buffer);
    free(self, app.gpa);
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
    return generic_to_window(self, do_text_window, destroy_text_window);
}

empty_text_window :: proc(app: ^App){
    tw := new(Text_Window, app.gpa);
    tw.buffer = Buffer.create(app.gpa);
    tw.cursor = Buffer.new_pos(&tw.buffer);
    id := add_window(app, text_window_to_window(tw));
    set_active(id, app);
}

open_to_text_window :: proc(path: string, app: ^App){
    buffer, ok := Buffer.load(path, app.gpa, app.fa);
    if !ok do return;

    tw := new(Text_Window, app.gpa);
    tw.buffer = buffer;
    tw.cursor = Buffer.new_pos(&tw.buffer);
    id := add_window(app, text_window_to_window(tw));
    set_active(id, app);
}



//
//move_pos :: proc(b: ^Buffer, p: Pos_Id, direction: Move_Direction) -> bool{
//    position := get_pos(b^, p);
//
//    switch direction{
//    case .Up:   
//        line_begin := find_line_begin_i(b^, position);
//        pos_from_begin := position - line_begin;
//        if line_begin == 0 do return false;
//        pos := line_begin - 1; 
//        line_begin = find_line_begin_i(b^, pos);
//        line_end  := find_line_end_i(b^, pos);
//        new_position := clamp(line_begin + pos_from_begin, line_begin, line_end);
//        set_pos(b, p, new_position);
//        return true;
//    case .Down: 
//        line_end := find_line_end_i(b^, position);
//        line_begin := find_line_begin_i(b^, position);
//        pos_from_begin := position - line_begin;
//        if line_end >= length(b^) do return false;
//        pos := line_end + 1;
//        line_begin    = find_line_begin_i(b^, pos);
//        line_end      = find_line_end_i(b^, pos);
//        new_position := clamp(line_begin + pos_from_begin, line_begin, line_end);
//        set_pos(b, p, new_position);
//        return true;
//    case .Left: 
//        new_position := position - 1;
//        r := get_rune_i(b^, new_position);
//        if r != 0 && r != '\n'{
//            set_pos(b, p, new_position);
//            return true;
//        }
//        return false;
//    case .Right:
//        new_position := position + 1;
//        r := get_rune_i(b^, new_position);
//        if r != 0 && r != '\n'{
//            set_pos(b, p, new_position);
//            return true;
//        }
//        return false;
//    }
//
//    return false;
//}
