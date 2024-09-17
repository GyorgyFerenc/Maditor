package main

import "core:c"
import "core:mem"
import "core:fmt"
import "core:unicode/utf8"
import "core:unicode"
import s "core:strings"
import "core:math"

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
    visual: struct{
        cursor: Buffer.Pos_Id,

        start: Buffer.Pos_Id,
        end: Buffer.Pos_Id,
    },
    draw: struct{
        line_count: bool,
        status_line: bool,
    },
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
    self.visual.cursor = Buffer.new_pos(&self.buffer);
    self.visual.start  = self.visual.cursor;
    self.visual.end    = self.cursor;
    self.draw.line_count  = true;
    self.draw.status_line = true;
}

update_text_window :: proc(self: ^Text_Window, app: ^App){
    path, ok := self.buffer.path.?;
    if ok {
        self.title = path;
    } else {
        self.title = "[EMPTY BUFFER]";
    }

    if match_key_bind(app, BACK_TO_NORMAL){
        self.mode = .Normal;
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
    }

    switch self.mode{
    case .Normal:
        if self.buffer.dirty && app.settings.autosave{
            Buffer.save(&self.buffer, app.fa);
        }

        if match_key_bind(app, NORMAL_GO_TO_INSERT){ go_to_insert_mode(self, app); }
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
            move_cursor(self, .Right);
            Buffer.remove_rune_left(&self.buffer, self.cursor);
        }
        if match_key_bind(app, NORMAL_GO_TO_VISUAL){
            go_to_visual_mode(self);
        }
    case .Insert:
        if match_key_bind(app, INSERT_REMOVE_RUNE){
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
        vc := Buffer.get_pos(self.buffer, visual.cursor);
        c  := Buffer.get_pos(self.buffer, self.cursor);
        start := 0;
        end   := 0;

        if vc < c{
            visual.start = visual.cursor;
            visual.end = self.cursor;
            start = vc;
            end   = c;
        } else {
            visual.start = self.cursor;
            visual.end = visual.cursor;
            start = c;
            end   = vc;
        }
        
        dgst := match_key_bind(app, VISUAL_DELETE_GO_INSERT);
        if match_key_bind(app, VISUAL_DELETE) || dgst{
            len := end - start + 1;
            Buffer.remove_range(&self.buffer, visual.start, len);
            if dgst do go_to_insert_mode(self, app);
        }
    }
}

draw_text_window :: proc(self: ^Text_Window, app: ^App){
    defer clear(&self.colors);

    color_scheme := app.settings.color_scheme;
    style := Text_Style{
        font = app.settings.font.font,
        size = app.settings.font.size,
        spacing = 1,
        color = color_scheme.text,
    };

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
            rl.DrawTextEx(style.font, line_cstr, to_view_pos(self, line_count_pos), style.size, style.spacing, rl.WHITE);
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

go_to_visual_mode :: proc(self: ^Text_Window){
    self.mode = .Visual;
    Buffer.set_pos_to_pos(&self.buffer, self.visual.cursor, self.cursor);
}

Condition_Move :: enum{Forward, Backward}
move_cursor_by_condition :: proc(self: ^Text_Window, dir: Condition_Move, check: proc(rune)->bool) -> bool{
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

NORMAL_GO_TO_INSERT                 :: Key_Bind{Key{key = .I}};
NORMAL_REMOVE_RUNE                  :: Key_Bind{Key{key = .X}};
NORMAL_GO_TO_VISUAL                 :: Key_Bind{Key{key = .V}};
NORMAL_GO_TO_INSERT_APPEND          :: Key_Bind{Key{key = .A}};
NORMAL_GO_TO_INSERT_NEW_LINE_BELLOW :: Key_Bind{Key{key = .O}};
NORMAL_GO_TO_INSERT_NEW_LINE_ABOVE  :: Key_Bind{Key{key = .O, shift = true}};

INSERT_REMOVE_RUNE :: Key_Bind{Key{key = .BACKSPACE}};
INSERT_NEW_LINE    :: Key_Bind{Key{key = .ENTER}};
INSERT_TAB         :: Key_Bind{Key{key = .TAB}};

VISUAL_DELETE           :: Key_Bind{Key{key = .D}};
VISUAL_DELETE_GO_INSERT :: Key_Bind{Key{key = .C}};

BACK_TO_NORMAL :: Key_Bind{Key{key = .C, ctrl = true}};
