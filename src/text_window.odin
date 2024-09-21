package main
/*
    Todo(Ferenc): Investigate problems when the buffer is empty
*/

import "core:c"
import "core:mem"
import "core:fmt"
import "core:unicode/utf8"
import "core:unicode"
import s "core:strings"
import "core:math"
import "core:slice"

import rl "vendor:raylib"

import "src:Buffer"

Text_Window_Mode :: enum{
    Normal,
    Insert,
    Visual,
}

Text_Window :: struct{
    using window_data: Window_Data,
    
    app: ^App,
    buffer: Buffer.Buffer,
    cursor: Buffer.Pos_Id,
    colors: [dynamic]Text_Window_Color,
    mode: Text_Window_Mode,
    view_y: f32,
    visual: struct{
        anchor: Buffer.Pos_Id,
        line: bool,

        start: Buffer.Pos_Id,
        end:   Buffer.Pos_Id,
    },
    insert: struct{
        old_buffer: Buffer.Buffer,
    },
    draw: struct{
        line_count: bool,
        status_line: bool,
        text: Text_Style,
    },
    search: struct{
        pattern: string,
        found_pos: int,
        found: bool,
    },
    undo: [dynamic]Buffer.Buffer,
}

Text_Window_Color :: struct{
    color: rl.Color,
    pos:   int,
    len:   int,
}

init_text_window :: proc(self: ^Text_Window, buffer: Buffer.Buffer, app: ^App){
    self.app    = app;
    self.buffer = buffer;
    self.colors = make([dynamic]Text_Window_Color, allocator = app.gpa);
    self.cursor = Buffer.new_pos(&self.buffer);
    self.visual.anchor = Buffer.new_pos(&self.buffer); 
    self.visual.start  = Buffer.new_pos(&self.buffer); 
    self.visual.end    = Buffer.new_pos(&self.buffer);
    self.draw.line_count  = true;
    self.draw.status_line = true;
    self.undo = make([dynamic]Buffer.Buffer, app.gpa);
    sync_title(self);
}

update_text_window :: proc(self: ^Text_Window, app: ^App){
    sync_title(self);

    color_scheme := app.settings.color_scheme;
    self.draw.text = Text_Style{
        font = app.settings.font.font,
        size = app.settings.font.size,
        spacing = 1,
        color = color_scheme.text,
    };

    if match_key_bind(app, BACK_TO_NORMAL){
        go_to_mode(self, .Normal);
    }

    number := 1;
    if self.mode == .Normal || self.mode == .Visual{
        if match_key_bind(app, MOVE_LEFT, &number){
            for _ in 0..<number{ move_cursor(self, .Left); }
        }
        if match_key_bind(app, MOVE_RIGHT, &number){
            for _ in 0..<number{ move_cursor(self, .Right); }
        }
        if match_key_bind(app, MOVE_UP, &number){
            for _ in 0..<number{ move_cursor(self, .Up); }
        }
        if match_key_bind(app, MOVE_DOWN, &number){
            for _ in 0..<number{ move_cursor(self, .Down); }
        }
        if match_key_bind(app, PAGE_UP){
            for _ in 0..<30{ move_cursor(self, .Up); }
        }
        if match_key_bind(app, PAGE_DOWN){
            for _ in 0..<30{ move_cursor(self, .Down); }
        }
        if match_key_bind(app, MOVE_WORD_FORWARD, &number){
            for _ in 0..<number{ move_cursor_by_word(self, .Forward); }
        }
        if match_key_bind(app, MOVE_WORD_BACKWARD, &number){ 
            for _ in 0..<number{ move_cursor_by_word(self, .Backward); }
        }
        if match_key_bind(app, MOVE_WORD_INSIDE_FORWARD, &number){
            for _ in 0..<number{ move_cursor_by_word_inside(self, .Forward); }
        }
        if match_key_bind(app, MOVE_WORD_INSIDE_BACKWARD, &number){ 
            for _ in 0..<number{ move_cursor_by_word_inside(self, .Backward); }
        }
        if match_key_bind(app, CENTER_SCREEN){
            line  := Buffer.get_line_number(self.buffer, self.cursor);
            pos_y := cast(f32) line * self.draw.text.size;
            self.view_y = math.floor(pos_y - self.box.size.y / 2);
            if self.view_y < 0 do self.view_y = 0;
        }       
        if match_key_bind(app, GO_TO_BEGIN_LINE){
            Buffer.set_pos(&self.buffer, self.cursor, Buffer.find_line_begin(self.buffer, self.cursor));
        }
        if match_key_bind(app, GO_TO_END_LINE){
            Buffer.set_pos(&self.buffer, self.cursor, Buffer.find_line_end(self.buffer, self.cursor));
        }
        if match_key_bind(app, GO_TO_BEGIN_FILE){
            Buffer.set_pos(&self.buffer, self.cursor, 0);
        }
        if match_key_bind(app, GO_TO_END_FILE){
            Buffer.set_pos(&self.buffer, self.cursor, Buffer.length(self.buffer) - 1);
        }
        if match_key_bind(app, FIND_FORWARD){
            find_next(self, .Forward);
        }
        if match_key_bind(app, FIND_BACKWARD){
            find_next(self, .Backward);
        }
    }

    switch self.mode{
    case .Normal:
        if self.buffer.dirty && app.settings.autosave{
            Buffer.save(&self.buffer, app.fa);
        }

        if match_key_bind(app, NORMAL_GO_TO_INSERT){ go_to_insert_mode(self); }
        if match_key_bind(app, NORMAL_GO_TO_INSERT_APPEND){
            move_cursor(self, .Right);
            go_to_insert_mode(self);
        }
        if match_key_bind(app, NORMAL_GO_TO_INSERT_NEW_LINE_BELLOW){
            end := insert_new_line_below(self);
            Buffer.set_pos(&self.buffer, self.cursor, end + 1);
            go_to_insert_mode(self);
        }
        if match_key_bind(app, NORMAL_GO_TO_INSERT_NEW_LINE_ABOVE){
            begin := insert_new_line_above(self);
            Buffer.set_pos(&self.buffer, self.cursor, begin);
            go_to_insert_mode(self);
        }
        if match_key_bind(app, NORMAL_REMOVE_RUNE){
            // Todo(Ferenc): Fix this, add wrap to move_cursor
            //move_cursor(self, .Right);
            //Buffer.remove_rune_left(&self.buffer, self.cursor);
        }
        if match_key_bind(app, NORMAL_GO_TO_VISUAL){
            go_to_visual_mode(self);
        }
        if match_key_bind(app, NORMAL_GO_TO_VISUAL_LINE){
            go_to_visual_mode(self, true);
        }
        if match_key_bind(app, NORMAL_PASTE){
            insert_range(self, app.copy_buffer[:]);
        }
        if match_key_bind(app, NORMAL_UNDO){
            undo(self);
        }
        if match_key_bind(app, NORMAL_REDO){
            // Todo(Ferenc): support it
            //redo(self); 
        }

        if match_key_bind(app, NORMAL_DELETE_WORLD_FORWARD){
            delete_by_word(self, .Forward);
        }
        if match_key_bind(app, NORMAL_DELETE_WORLD_BACKWARD){
            delete_by_word(self, .Backward);
        }
        if match_key_bind(app, NORMAL_DELETE_WORLD_INSIDE_FORWARD){
            delete_by_word_inside(self, .Forward);
        }
        if match_key_bind(app, NORMAL_DELETE_WORLD_INSIDE_BACKWARD){
            delete_by_word_inside(self, .Backward);
        }
        if match_key_bind(app, NORMAL_DELETE_RIGHT){
            delete_by_cursor(self, .Right);
        }
        if match_key_bind(app, NORMAL_DELETE_LEFT){
            delete_by_cursor(self, .Left);
        }
        if match_key_bind(app, NORMAL_DELETE_UNTIL_END_LINE){
            delete_until_end_line(self);
        }
        if match_key_bind(app, NORMAL_DELETE_LINE){
            delete_line(self);
        }

        if match_key_bind(app, NORMAL_CHANGE_WORLD_FORWARD){
            change_by_word(self, .Forward);
        }
        if match_key_bind(app, NORMAL_CHANGE_WORLD_BACKWARD){
            change_by_word(self, .Backward);
        }
        if match_key_bind(app, NORMAL_CHANGE_WORLD_INSIDE_FORWARD){
            change_by_word_inside(self, .Forward);
        }
        if match_key_bind(app, NORMAL_CHANGE_WORLD_INSIDE_BACKWARD){
            change_by_word_inside(self, .Backward);
        }
        if match_key_bind(app, NORMAL_CHANGE_RIGHT){
            change_by_cursor(self, .Right);
        }
        if match_key_bind(app, NORMAL_CHANGE_LEFT){
            change_by_cursor(self, .Left);
        }
        if match_key_bind(app, NORMAL_CHANGE_UNTIL_END_LINE){
            change_until_end_line(self);
        }
        if match_key_bind(app, NORMAL_CHANGE_LINE){
            change_line(self);
        }

    case .Insert:
        if match_key_bind(app, INSERT_REMOVE_RUNE) ||
           match_key_bind(app, INSERT_REMOVE_RUNE2) {
            Buffer.remove_rune_left(&self.buffer, self.cursor);
        }
        if match_key_bind(app, INSERT_NEW_LINE){
            Buffer.insert_rune(&self.buffer, self.cursor, '\n');
        }
        if match_key_bind(app, INSERT_TAB){
            for _ in 0..<app.settings.tab_size{
                Buffer.insert_rune(&self.buffer, self.cursor, ' ');
            }
        }
        r := poll_rune(app);
        if r != 0{
            Buffer.insert_rune(&self.buffer, self.cursor, r);
        }
    case .Visual:
        visual := &self.visual;
        anchor_pos := Buffer.get_pos(self.buffer, visual.anchor);
        cursor_pos := Buffer.get_pos(self.buffer, self.cursor);

        if visual.line {
            if cursor_pos < anchor_pos{
                Buffer.set_pos(&self.buffer, visual.start, Buffer.find_line_begin_i(self.buffer, cursor_pos));
                Buffer.set_pos(&self.buffer, visual.end,   Buffer.find_line_end_i(self.buffer,   anchor_pos));
            } else {
                Buffer.set_pos(&self.buffer, visual.start, Buffer.find_line_begin_i(self.buffer, anchor_pos));
                Buffer.set_pos(&self.buffer, visual.end,   Buffer.find_line_end_i(self.buffer,   cursor_pos));
            }
        } else {
            if cursor_pos < anchor_pos{
                Buffer.set_pos(&self.buffer, visual.start, cursor_pos);
                Buffer.set_pos(&self.buffer, visual.end,   anchor_pos);
            } else {
                Buffer.set_pos(&self.buffer, visual.start, anchor_pos);
                Buffer.set_pos(&self.buffer, visual.end,   cursor_pos);
            }
        }

        start := Buffer.get_pos(self.buffer, visual.start);
        end   := Buffer.get_pos(self.buffer, visual.end);

        select_len := end - start + 1;
        if match_key_bind(app, VISUAL_DELETE){
            remove_range(self, visual.start, select_len);
        }
        if match_key_bind(app, VISUAL_CHANGE){
            pos := Buffer.get_pos(self.buffer, visual.start);         
            Buffer.set_pos(&self.buffer, self.cursor, end + 1);
            remove_range_i(self, pos, select_len);
            go_to_insert_mode(self);
        }

        if match_key_bind(app, VISUAL_COPY){
            clear(&app.copy_buffer);
            for i in 0..<select_len{
                append(&app.copy_buffer, Buffer.get_rune_i(self.buffer, start + i));
            }
        }

    }
}

draw_text_window :: proc(self: ^Text_Window, app: ^App){
    defer clear(&self.colors);

    slice.sort_by(self.colors[:], proc(a, b: Text_Window_Color) -> bool{
        return a.pos < b.pos;
    });    

    color_scheme := app.settings.color_scheme;
    style := self.draw.text; 

    big_text_box: Box = self.box;

    if self.draw.status_line{
        status_line: Box;
        big_text_box, status_line = remove_padding_side(self.box, 30, .Bottom);
        draw_status_line(self, app, status_line, color_scheme.background3, style);
    }

    line_count := Buffer.get_line_number_i(self.buffer, Buffer.length(self.buffer) - 1);
    line_nr_len := style.size * 3;

    text_box := big_text_box;
    line_box: Box;
    if self.draw.line_count{
        text_box, line_box = remove_padding_side(big_text_box, cast(f32) line_nr_len, .Left);
        draw_box(line_box, color_scheme.background2);
    }
    draw_box(text_box, color_scheme.background1);

    begin_box_draw_mode(big_text_box);
    defer end_box_draw_mode();

    start_x :=  text_box.pos.x;
    position := text_box.pos;

    cursor_i := Buffer.get_pos(self.buffer, self.cursor);
    line_count = 1;
    cursor_line := Buffer.get_line_number(self.buffer, self.cursor);
    line_start := true;

    cursor_up_position   := cast(f32) cursor_line * style.size - style.size;
    cursor_down_position := cast(f32) cursor_line * style.size + style.size;
    if cursor_up_position <= self.view_y{
        self.view_y = cursor_up_position;
    }
    if cursor_down_position > self.view_y + text_box.size.y{
        self.view_y = cursor_down_position - text_box.size.y;
    }
    space_width := measure_rune_size(' ', style).x;
    color_window := Text_Window_Color{rl.WHITE, 0, 0};
    color_index := 0;
    it := Buffer.iter(self.buffer);
    for r, idx in Buffer.next(&it){
        if self.draw.line_count && line_start{
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
            rl.DrawTextEx(style.font, line_cstr, to_view_pos(self, line_count_pos), style.size, style.spacing, color_scheme.text);
        }

        if color_index < len(self.colors){
            if self.colors[color_index].pos == idx{
                color_window = self.colors[color_index];
                color_index += 1;
            }
            for color_index < len(self.colors) && self.colors[color_index].pos <= idx{
                color_index += 1;
            }
        }

        color := color_scheme.text;
        if color_window.pos <= idx && idx < color_window.pos + color_window.len{
            color = color_window.color;
        }

        size := measure_rune_size(r, style);
        adjusted_pos := to_view_pos(self, position);
        rune_box := Box{adjusted_pos, size};

        if r == '\n'{
            line_count += 1;
            position.y += style.size;
            position.x = start_x;
            line_start = true;
            rune_box.size = measure_rune_size('?', style);
        } else if r == '\t'{
            // Todo(Ferenc): Implement it 
            //tab_stop_size := cast(f32) app.settings.tab_size * space_width + 
            //                 cast(f32) (app.settings.tab_size - 1) * style.spacing;
            //number_of_stops := cast(int) position.x / cast(int) tab_stop_size;
            //new_x := start_x + cast(f32) number_of_stops * tab_stop_size;
            //rune_box.size.x = new_x - position.x - style.spacing;
            size := cast(f32) app.settings.tab_size * space_width + 
                    cast(f32) (app.settings.tab_size - 1) * style.spacing;
            rune_box.size.x = size - style.spacing;
            position.x += size;
        } else {
            rl.DrawTextCodepoint(style.font, r, adjusted_pos , style.size, color);
            position.x += size.x + style.spacing;
        }

        if cursor_i == idx{
            color := color_scheme.white;
            switch self.mode{
            case .Normal: color = color_scheme.white;
            case .Insert: color = color_scheme.green;
            case .Visual: color = color_scheme.purple;
            }
            draw_cursor(rune_box, color);
        }

        if self.mode == .Visual{
            start := Buffer.get_pos(self.buffer, self.visual.start);            
            end   := Buffer.get_pos(self.buffer, self.visual.end);
            b, _  := add_margin_side(rune_box, style.spacing, .Right);
            c := app.settings.color_scheme.foreground1;
            c.a = 100;
            if start <= idx && idx <= end{
                draw_box(b, c);
            }
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

    draw_status_line :: proc(self: ^Text_Window, app: ^App, status_line: Box, background: rl.Color, style: Text_Style){
        begin_box_draw_mode(status_line);
        defer end_box_draw_mode();

        draw_box(status_line, background);

        text: cstring = "";
        switch self.mode{
        case .Normal: text = "NORMAL";
        case .Insert: text = "INSERT";
        case .Visual: text = "VISUAL";
        }

        // Todo(Ferenc): align vertical center
        
        size := measure_text(cast(string) text, style, app.fa);
        rl.DrawTextEx(style.font, text, status_line.pos, style.size, style.spacing, style.color);
        
        status_line, _ := remove_padding_side(status_line, size.x + 10, .Left);
        cstr := s.clone_to_cstring(self.title, app.fa);
        rl.DrawTextEx(style.font, cstr, status_line.pos, style.size, style.spacing, style.color);
        size = measure_text(self.title, style, app.fa);
        box, _ := remove_padding_side(status_line, size.x + 10, .Left);
        box.size = status_line.size.yy / 2;

        if self.buffer.dirty{
            draw_box(box, app.settings.color_scheme.red);
        } else {
            draw_box(box, app.settings.color_scheme.green);
        }
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

Move_Cursor :: enum{Left, Right, Up, Down}
move_cursor :: proc(self: ^Text_Window, direction: Move_Cursor) -> bool{
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

text_window_to_window :: proc(self: ^Text_Window) -> Window{
    return generic_to_window(self, update_text_window, draw_text_window, destroy_text_window);
}

empty_text_window :: proc(app: ^App) -> Window_Id{
    tw := new(Text_Window, app.gpa);
    init_text_window(tw, Buffer.create(app.gpa), app);
    id := add_window(app, text_window_to_window(tw));
    set_active(id, app);
    return id;
}

open_to_text_window :: proc(path: string, app: ^App) -> (Window_Id, bool){
    buffer, ok := Buffer.load(path, app.gpa, app.fa);
    if !ok do return {}, false;

    tw := new(Text_Window, app.gpa);
    init_text_window(tw, buffer, app);
    id := add_window(app, text_window_to_window(tw));
    set_active(id, app);

    return id, true;
}

go_to_mode :: proc(self: ^Text_Window, mode: Text_Window_Mode){
    leave_mode(self);
    self.mode = mode;
}

go_to_insert_mode :: proc(self: ^Text_Window){
    go_to_mode(self, .Insert);
    discard_next_rune(self.app);
    self.insert.old_buffer = Buffer.clone(self.buffer, self.app.gpa);
}

go_to_visual_mode :: proc(self: ^Text_Window, line := false){
    go_to_mode(self, .Visual);
    Buffer.set_pos_to_pos(&self.buffer, self.visual.anchor, self.cursor);
    self.visual.line = line;
}

leave_mode :: proc(self: ^Text_Window){
    switch self.mode{
    case .Normal:
    case .Visual:
    case .Insert:
        if !Buffer.text_equal(self.insert.old_buffer, self.buffer){
            push_undo(self, self.insert.old_buffer);
        }
        Buffer.destroy(self.insert.old_buffer);
    }
}

Condition_Move :: enum{Forward, Backward}
move_cursor_by_condition :: proc(self: ^Text_Window, dir: Condition_Move, check: proc(rune)->bool) -> bool{
    kind := Move_Cursor.Right;
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

move_cursor_by_word :: proc(self: ^Text_Window, dir: Condition_Move) -> bool{
    return move_cursor_by_condition(self, dir, proc(r: rune) -> bool{
        return unicode.is_alpha(r) || r == '_' || unicode.is_number(r);
    });
}

move_cursor_by_word_inside :: proc(self: ^Text_Window, dir: Condition_Move) -> bool{
    return move_cursor_by_condition(self, dir, unicode.is_alpha);
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

jump_to_line :: proc(self: ^Text_Window, line_number: int){
    Buffer.set_pos(&self.buffer, self.cursor, Buffer.get_position_of_line(self.buffer, line_number));
}

/*
    Clones the pattern
*/
start_search :: proc(self: ^Text_Window, pattern: string){
    search := &self.search;
    if search.pattern != ""{
        delete(search.pattern, self.app.gpa);
    }
    search.pattern = s.clone(pattern, self.app.gpa);
    search.found_pos = 0;
    find_next(self);
}

find_next :: proc(self: ^Text_Window, dir: enum{Forward, Backward} = .Forward){
    search := &self.search;
    search.found = false;
    text := Buffer.to_string(self.buffer, self.app.fa);
    
    pos := search.found_pos;

    increment: int;
    switch dir{
    case .Forward: increment = 1;
    case .Backward: increment = -1;
    }

    for {
        pos += increment;
        if pos < 0 || pos >= len(text){
            break;
        }
        
        if match(text[pos:], search.pattern){
            search.found_pos = pos;
            search.found = true;
            break;
        }
    }

    if self.search.found {
        Buffer.set_pos(&self.buffer, self.cursor, self.search.found_pos);
    } else {
        search.found_pos = 0;
    }

    match :: proc(text: string, pattern: string) -> bool{
        return s.starts_with(text, pattern);
    }
}

remove_range :: proc(self: ^Text_Window, p: Buffer.Pos_Id, len: int){
    if len == 0 do return;
    push_undo(self, self.buffer);
    Buffer.remove_range(&self.buffer, p, len);
}

remove_range_i :: proc(self: ^Text_Window, pos: int, len: int){
    if len == 0 do return;
    push_undo(self, self.buffer);
    Buffer.remove_range_i(&self.buffer, pos, len);  
}

push_undo :: proc(self: ^Text_Window, b: Buffer.Buffer){
    append(&self.undo, Buffer.clone(b, self.app.gpa));
}

undo :: proc(self: ^Text_Window){
    if len(self.undo) == 0 do return;
    b := self.undo[len(self.undo) - 1];
    pop(&self.undo);

    Buffer.destroy(self.buffer);
    self.buffer = Buffer.clone(b, self.app.gpa);
}

delete_by_word :: proc(self: ^Text_Window, dir: Condition_Move){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_cursor_by_word(self, dir);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    delete_between_positions(self, pos, new_pos);
}

delete_by_word_inside :: proc(self: ^Text_Window, dir: Condition_Move){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_cursor_by_word_inside(self, dir);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    delete_between_positions(self, pos, new_pos);
}

delete_by_cursor :: proc(self: ^Text_Window, direction: Move_Cursor){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_cursor(self, direction);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    delete_between_positions(self, pos, new_pos);
}

delete_by :: proc(self: ^Text_Window, move_proc: proc(^Text_Window)){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_proc(self);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    delete_between_positions(self, pos, new_pos);
}

delete_until_end_line :: proc(self: ^Text_Window){
    delete_between_positions(self, 
        Buffer.get_pos(self.buffer, self.cursor),
        Buffer.find_line_end(self.buffer, self.cursor));
}

delete_line :: proc(self: ^Text_Window){
    delete_between_positions(self, 
        Buffer.find_line_begin(self.buffer, self.cursor),
        Buffer.find_line_end(self.buffer, self.cursor) + 1);
}

delete_between_positions :: proc(self: ^Text_Window, p1, p2: int){
    if p1 < p2{
        len := p2 - p1;
        remove_range_i(self, p1, len);
    } else {
        len := p1 - p2;
        remove_range_i(self, p2, len);
    }
}

change_by :: proc(self: ^Text_Window, move_proc: proc(^Text_Window)){
    delete_by(self, move_proc);
    go_to_insert_mode(self);
}



change_by_word :: proc(self: ^Text_Window, dir: Condition_Move){
    delete_by_word(self, dir);
    go_to_insert_mode(self);
}

change_by_word_inside :: proc(self: ^Text_Window, dir: Condition_Move){
    delete_by_word_inside(self, dir);
    go_to_insert_mode(self);
}

change_by_cursor :: proc(self: ^Text_Window, dir: Move_Cursor){
    delete_by_cursor(self, dir);
    go_to_insert_mode(self);
}

change_until_end_line :: proc(self: ^Text_Window){
    delete_until_end_line(self);
    go_to_insert_mode(self);
}

change_line :: proc(self: ^Text_Window){
    delete_line(self);
    go_to_insert_mode(self);
}


insert_range :: proc(self: ^Text_Window, array: []rune){
    old_buffer := Buffer.clone(self.buffer, self.app.gpa);
    defer Buffer.destroy(old_buffer);

    for r in array{
        Buffer.insert_rune(&self.buffer, self.cursor, r);
    }
    if !Buffer.text_equal(old_buffer, self.buffer){
        push_undo(self, old_buffer); // Todo(Ferenc): make a push which does not copies for speed
    }
}

sync_title :: proc(self: ^Text_Window){
    path, ok := self.buffer.path.?;
    if ok {
        self.title = path;
    } else {
        self.title = "[EMPTY BUFFER]";
    }
}

add_color :: proc(self: ^Text_Window, color: Text_Window_Color){
    append(&self.colors, color);
}

MOVE_LEFT                 :: Key_Bind{Key{key = .H}};
MOVE_RIGHT                :: Key_Bind{Key{key = .L}};
MOVE_UP                   :: Key_Bind{Key{key = .K}};
MOVE_DOWN                 :: Key_Bind{Key{key = .J}};
PAGE_DOWN                 :: Key_Bind{Key{key = .D, ctrl = true}};
PAGE_UP                   :: Key_Bind{Key{key = .U, ctrl = true}};
MOVE_WORD_FORWARD         :: Key_Bind{Key{key = .W}};
MOVE_WORD_BACKWARD        :: Key_Bind{Key{key = .B}};
MOVE_WORD_INSIDE_FORWARD  :: Key_Bind{Key{key = .W, shift = true}};
MOVE_WORD_INSIDE_BACKWARD :: Key_Bind{Key{key = .B, shift = true}};
CENTER_SCREEN             :: Key_Bind{Key{key = .Z}, Key{key = .Z}};
GO_TO_BEGIN_LINE          :: Key_Bind{Key{key = .H, shift = true}};
GO_TO_END_LINE            :: Key_Bind{Key{key = .L, shift = true}};
GO_TO_BEGIN_FILE          :: Key_Bind{Key{key = .K, shift = true}};
GO_TO_END_FILE            :: Key_Bind{Key{key = .J, shift = true}};
FIND_FORWARD              :: Key_Bind{Key{key = .N}};
FIND_BACKWARD             :: Key_Bind{Key{key = .N, shift = true}};

NORMAL_UNDO                         :: Key_Bind{Key{key = .U}};
NORMAL_REDO                         :: Key_Bind{Key{key = .U, shift = true}};
NORMAL_GO_TO_INSERT                 :: Key_Bind{Key{key = .I}};
NORMAL_REMOVE_RUNE                  :: Key_Bind{Key{key = .X}};
NORMAL_GO_TO_VISUAL                 :: Key_Bind{Key{key = .V}};
NORMAL_GO_TO_VISUAL_LINE            :: Key_Bind{Key{key = .V, shift = true}};
NORMAL_GO_TO_INSERT_APPEND          :: Key_Bind{Key{key = .A}};
NORMAL_GO_TO_INSERT_NEW_LINE_BELLOW :: Key_Bind{Key{key = .O}};
NORMAL_GO_TO_INSERT_NEW_LINE_ABOVE  :: Key_Bind{Key{key = .O, shift = true}};
NORMAL_PASTE                        :: Key_Bind{Key{key = .P}};

NORMAL_DELETE_WORLD_FORWARD         :: Key_Bind{Key{key = .D}, {key = .W}};
NORMAL_DELETE_WORLD_BACKWARD        :: Key_Bind{Key{key = .D}, {key = .B}};
NORMAL_DELETE_WORLD_INSIDE_FORWARD  :: Key_Bind{Key{key = .D}, {key = .W, shift = true}};
NORMAL_DELETE_WORLD_INSIDE_BACKWARD :: Key_Bind{Key{key = .D}, {key = .B, shift = true}};
NORMAL_DELETE_RIGHT                 :: Key_Bind{Key{key = .D}, {key = .L}};
NORMAL_DELETE_LEFT                  :: Key_Bind{Key{key = .D}, {key = .H}};
NORMAL_DELETE_UNTIL_END_LINE        :: Key_Bind{Key{key = .D, shift = true}};
NORMAL_DELETE_LINE                  :: Key_Bind{Key{key = .D}, {key = .D}};

NORMAL_CHANGE_WORLD_FORWARD         :: Key_Bind{Key{key = .C}, {key = .W}};
NORMAL_CHANGE_WORLD_BACKWARD        :: Key_Bind{Key{key = .C}, {key = .B}};
NORMAL_CHANGE_WORLD_INSIDE_FORWARD  :: Key_Bind{Key{key = .C}, {key = .W, shift = true}};
NORMAL_CHANGE_WORLD_INSIDE_BACKWARD :: Key_Bind{Key{key = .C}, {key = .B, shift = true}};
NORMAL_CHANGE_RIGHT                 :: Key_Bind{Key{key = .C}, {key = .L}};
NORMAL_CHANGE_LEFT                  :: Key_Bind{Key{key = .C}, {key = .H}};
NORMAL_CHANGE_UNTIL_END_LINE        :: Key_Bind{Key{key = .C, shift = true}};
NORMAL_CHANGE_LINE                  :: Key_Bind{Key{key = .C}, {key = .C}};

INSERT_REMOVE_RUNE  :: Key_Bind{Key{key = .BACKSPACE}};
INSERT_REMOVE_RUNE2 :: Key_Bind{Key{key = .BACKSPACE, shift = true}};
INSERT_NEW_LINE     :: Key_Bind{Key{key = .ENTER}};
INSERT_TAB          :: Key_Bind{Key{key = .TAB}};

VISUAL_DELETE :: Key_Bind{Key{key = .D}};
VISUAL_COPY   :: Key_Bind{Key{key = .Y}};
VISUAL_CHANGE :: Key_Bind{Key{key = .C}};

BACK_TO_NORMAL :: Key_Bind{Key{key = .C, ctrl = true}};
