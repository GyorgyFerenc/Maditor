package main

import "core:c"
import "core:mem"
import "core:fmt"
import "core:unicode/utf8"
import "core:unicode"
import s "core:strings"
import rl "vendor:raylib"

import "src:Buffer"

Text_Window :: struct{
    using window_data: Window_Data,
    
    buffer: Buffer.Buffer,
    cursor: Buffer.Pos_Id,
    colors: [dynamic]Text_Window_Color,
    mode: enum{
        Normal,
        Insert,
        Visual,
    },
    view_y: f32,
}

Text_Window_Color :: struct{
    color: rl.Color,
    pos:   int,
    len:   int,
}

init_text_window :: proc(self: ^Text_Window, buffer: Buffer.Buffer, alloc: mem.Allocator){
    self.buffer = buffer;
    self.colors = make([dynamic]Text_Window_Color, allocator = alloc);
    self.cursor = Buffer.new_pos(&self.buffer);
}

update_text_window :: proc(self: ^Text_Window, app: ^App){
    if match_key_bind(app, BACK_TO_NORMAL){
        self.mode = .Normal;
    }

    switch self.mode{
    case .Normal:
        if match_key_bind(app, NORMAL_MOVE_LEFT){          move_cursor(self, .Left); }
        if match_key_bind(app, NORMAL_MOVE_RIGHT){         move_cursor(self, .Right); }
        if match_key_bind(app, NORMAL_MOVE_UP){            move_cursor(self, .Up); }
        if match_key_bind(app, NORMAL_MOVE_DOWN){          move_cursor(self, .Down); }
        if match_key_bind(app, NORMAL_GO_TO_INSERT){       go_to_insert_mode(self, app); }
        if match_key_bind(app, NORMAL_GO_TO_INSERT_APPEND){
            move_cursor(self, .Right);
            go_to_insert_mode(self, app);
        }
        if match_key_bind(app, NORMAL_GO_TO_INSERT_NEW_LINE_BELLOW){
            end := insert_new_line_below(self);
            Buffer.set_pos(&self.buffer, self.cursor, end + 1);
            go_to_insert_mode(self, app);
        }
        if match_key_bind(app, NORMAL_GO_TO_INSERT_NEW_LINE_ABOVE){
            begin := insert_new_line_above(self);
            Buffer.set_pos(&self.buffer, self.cursor, begin);
            go_to_insert_mode(self, app);
        }
        if match_key_bind(app, NORMAL_REMOVE_RUNE){
            Buffer.remove_rune(&self.buffer, self.cursor);
            move_cursor(self, .Right);
        }
        if match_key_bind(app, NORMAL_SAVE){
            _ = Buffer.save(self.buffer, app.fa);
        }
        if match_key_bind(app, NORMAL_PAGE_UP){      
            for _ in 0..<30{
                move_cursor(self, .Up); 
            }
        }
        if match_key_bind(app, NORMAL_PAGE_DOWN){
            for _ in 0..<30{
                move_cursor(self, .Down); 
            }
        }
        if match_key_bind(app, NORMAL_MOVE_WORD_FORWARD){
            move_cursor_by_word(self, .Forward, proc(r: rune) -> bool{
                return unicode.is_alpha(r) || r == '_' || unicode.is_number(r);
            });
        }
        if match_key_bind(app, NORMAL_MOVE_WORD_BACKWARD){ 
            move_cursor_by_word(self, .Backward, proc(r: rune) -> bool{
                return unicode.is_alpha(r) || r == '_' || unicode.is_number(r);
            });
        }
        if match_key_bind(app, NORMAL_MOVE_WORD_INSIDE_FORWARD){
            move_cursor_by_word(self, .Forward, unicode.is_alpha);
        }
        if match_key_bind(app, NORMAL_MOVE_WORD_INSIDE_BACKWARD){ 
            move_cursor_by_word(self, .Backward, unicode.is_alpha);
        }
    case .Insert:
        if match_key_bind(app, INSERT_REMOVE_RUNE){
            Buffer.remove_rune_left(&self.buffer, self.cursor);
        }
        if match_key_bind(app, INSERT_NEW_LINE){
            Buffer.insert_rune(&self.buffer, self.cursor, '\n');
        }
        r := poll_rune(app);
        if r != 0{
            Buffer.insert_rune(&self.buffer, self.cursor, r);
        }
    case .Visual:
        
    }
}

draw_text_window :: proc(self: ^Text_Window, app: ^App){
    defer clear(&self.colors);

    color_scheme := app.settings.color_scheme;
    text_size := app.settings.font.size;
    font := app.settings.font.font;
    spacing: f32 = 1;

    big_text_box, status_line := remove_padding_side(self.box, 30, .Bottom);
    draw_status_line(self, status_line, color_scheme.background3, Text_Style{
        font = font,
        size = text_size,
        spacing = spacing,
        color = color_scheme.text,
    });

    line_count := Buffer.get_line_number_i(self.buffer, Buffer.length(self.buffer) - 1);
    line_nr_len := text_size * 3;
    text_box, line_box := remove_padding_side(big_text_box, cast(f32) line_nr_len, .Left);
    draw_box(line_box, color_scheme.background2);
    draw_box(text_box, color_scheme.background1);

    begin_box_draw_mode(big_text_box);
    defer end_box_draw_mode();

    start_x :=  text_box.pos.x;
    position := text_box.pos;

    cursor_i := Buffer.get_pos(self.buffer, self.cursor);
    line_count = 1;
    cursor_line := Buffer.get_line_number(self.buffer, self.cursor);
    line_start := true;

    cursor_up_position   := cast(f32) cursor_line * text_size - text_size;
    cursor_down_position := cast(f32) cursor_line * text_size + text_size;
    if cursor_up_position <= self.view_y{
        self.view_y = cursor_up_position;
    }
    if cursor_down_position > self.view_y + text_box.size.y{
        self.view_y = cursor_down_position - text_box.size.y;
    }
    color_window := Text_Window_Color{rl.WHITE, 0, 0};
    color_index := 0;
    it := Buffer.iter(self.buffer);
    for r, idx in Buffer.next(&it){
        if line_start{
            line_start = false;

            // draw line count
            builder := s.builder_make(app.fa);
            defer s.builder_reset(&builder);
            line_count_pos := v2{line_box.pos.x, position.y};
            if line_count == cursor_line{
                line_count_pos.x += 10;
                s.write_int(&builder, line_count);
            } else if line_count < cursor_line{
                s.write_int(&builder, cursor_line - line_count);
            } else {
                s.write_int(&builder, line_count - cursor_line);
            }
            line_cstr := s.to_cstring(&builder);
            rl.DrawTextEx(font, line_cstr, to_view_pos(self, line_count_pos), text_size, spacing, rl.WHITE);
        }

        if color_index < len(self.colors){
            if self.colors[color_index].pos == idx{
                color_window = self.colors[color_index];
                color_index += 1;
            }
        }

        color := color_scheme.text;
        if color_window.pos <= idx && idx < color_window.pos + color_window.len{
            color = color_window.color;
        }

        size := measure_rune_size(r, font, text_size, spacing);
        adjusted_pos := to_view_pos(self, position);
        cursor_box := Box{adjusted_pos, size};

        if r != '\n'{
            rl.DrawTextCodepoint(font, r, adjusted_pos , text_size, color);
            position.x += size.x + spacing;
        } else {
            line_count += 1;
            position.y += text_size;
            position.x = start_x;
            line_start = true;
            cursor_box.size = measure_rune_size('?' , font, text_size, spacing);
        }

        if cursor_i == idx{
            color := color_scheme.white;
            switch self.mode{
            case .Normal: color = color_scheme.white;
            case .Insert: color = color_scheme.green;
            case .Visual: color = color_scheme.purple;
            }
            draw_cursor(cursor_box, color);
        }
    }

    draw_cursor :: proc(box: Box, color1: rl.Color){
        color1 := color1;
        color1.a = 100;
        draw_box(box, color1);
        color1.a = 0xFF;
        draw_box_outline(box, 1, color1);
    }

    to_view_pos :: proc(self: ^Text_Window, pos: v2) -> v2{
        return {pos.x, pos.y - self.view_y};
    }

    draw_status_line :: proc(self: ^Text_Window, status_line: Box, background: rl.Color, style: Text_Style){
        begin_box_draw_mode(status_line);
        defer end_box_draw_mode();

        draw_box(status_line, background);

        text: cstring = "";
        switch self.mode{
        case .Normal: text = "NORMAL";
        case .Insert: text = "INSERT";
        case .Visual: text = "VISUAL";
        }
        
        rl.DrawTextEx(style.font, text, status_line.pos, style.size, style.spacing, style.color);
    }
}

insert_new_line_below :: proc(self: ^Text_Window) -> int{
    end := Buffer.find_line_end(self.buffer, self.cursor);
    Buffer.insert_rune_i(&self.buffer, end, '\n');
    return end;
}

insert_new_line_above :: proc(self: ^Text_Window) -> int{
    begin := Buffer.find_line_begin(self.buffer, self.cursor);
    Buffer.insert_rune_i(&self.buffer, begin, '\n');
    return begin;
}

Move_Curosr :: enum{Left, Right, Up, Down}
move_cursor :: proc(self: ^Text_Window, direction: Move_Curosr) -> bool{
    cursor_pos := Buffer.get_pos(self.buffer, self.cursor);
    move_left  := direction == .Left;
    move_right := direction == .Right;
    move_up    := direction == .Up;
    move_down  := direction == .Down;

    if move_left{
        new_pos := cursor_pos - 1;
        current := Buffer.get_rune_i(self.buffer, new_pos);

        if current != 0 && current != '\n'{
            Buffer.set_pos(&self.buffer, self.cursor, new_pos);
            return cursor_pos != new_pos;
        }
    }
    if move_right{
        new_pos := cursor_pos + 1;
        current := Buffer.get_rune_i(self.buffer, new_pos);
        left    := Buffer.get_rune_i(self.buffer, new_pos - 1);

        if current != 0 && left != '\n'{
            Buffer.set_pos(&self.buffer, self.cursor, new_pos);
            return cursor_pos != new_pos;
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
        return cursor_pos != new_position;
    }

    return false;
}

destroy_text_window :: proc(self: ^Text_Window, app: ^App){
    Buffer.destroy(self.buffer);
    free(self, app.gpa);
    delete(self.colors);
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
    return generic_to_window(self, update_text_window, draw_text_window, destroy_text_window);
}

empty_text_window :: proc(app: ^App){
    tw := new(Text_Window, app.gpa);
    init_text_window(tw, Buffer.create(app.gpa), app.gpa);
    id := add_window(app, text_window_to_window(tw));
    set_active(id, app);
}

open_to_text_window :: proc(path: string, app: ^App){
    buffer, ok := Buffer.load(path, app.gpa, app.fa);
    if !ok do return;

    tw := new(Text_Window, app.gpa);
    init_text_window(tw, buffer, app.gpa);
    id := add_window(app, text_window_to_window(tw));
    set_active(id, app);
}

go_to_insert_mode :: proc(self: ^Text_Window, app: ^App){
    self.mode = .Insert;
    discard_next_rune(app);
}

move_cursor_by_word :: proc(self: ^Text_Window, dir: enum{Forward, Backward}, check: proc(rune)->bool) -> bool{
    kind := Move_Curosr.Right;
    if dir == .Backward do kind = .Left
    moved := false;

    r := Buffer.get_rune(self.buffer, self.cursor);
    expected := check(r);

    for{
        mc := move_cursor(self, kind);
        moved |= mc;
        if !mc do break;

        r := Buffer.get_rune(self.buffer, self.cursor);
        if check(r) != expected{ break; }
    }

    return moved;
}

length_of_int :: proc(nr: int) -> int{
    nr := nr;
    count := 0;
    for {
        count += 1;
        nr = nr / 10;
        if nr == 0 do break;
    }

    return count;
}

NORMAL_MOVE_LEFT    :: Key_Bind{Key{key = .H}};
NORMAL_MOVE_RIGHT   :: Key_Bind{Key{key = .L}};
NORMAL_MOVE_UP      :: Key_Bind{Key{key = .K}};
NORMAL_MOVE_DOWN    :: Key_Bind{Key{key = .J}};
NORMAL_REMOVE_RUNE  :: Key_Bind{Key{key = .X}};
NORMAL_GO_TO_INSERT :: Key_Bind{Key{key = .I}};
NORMAL_SAVE         :: Key_Bind{Key{key = .S}};
NORMAL_PAGE_DOWN    :: Key_Bind{Key{key = .D, ctrl = true}};
NORMAL_PAGE_UP      :: Key_Bind{Key{key = .U, ctrl = true}};

NORMAL_MOVE_WORD_FORWARD            :: Key_Bind{Key{key = .W}};
NORMAL_MOVE_WORD_BACKWARD           :: Key_Bind{Key{key = .B}};
NORMAL_MOVE_WORD_INSIDE_FORWARD     :: Key_Bind{Key{key = .W, shift = true}};
NORMAL_MOVE_WORD_INSIDE_BACKWARD    :: Key_Bind{Key{key = .B, shift = true}};
NORMAL_GO_TO_INSERT_APPEND          :: Key_Bind{Key{key = .A}};
NORMAL_GO_TO_INSERT_NEW_LINE_BELLOW :: Key_Bind{Key{key = .O}};
NORMAL_GO_TO_INSERT_NEW_LINE_ABOVE  :: Key_Bind{Key{key = .O, shift = true}};

// Insert
INSERT_REMOVE_RUNE :: Key_Bind{Key{key = .BACKSPACE}};
INSERT_NEW_LINE    :: Key_Bind{Key{key = .ENTER}};

// All
BACK_TO_NORMAL :: Key_Bind{Key{key = .C, ctrl = true}};
