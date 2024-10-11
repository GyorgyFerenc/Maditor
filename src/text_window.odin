package main
/*
    Todo(Ferenc): Investigate problems when the buffer is empty
    Todo(Ferenc): Investigate inserting the end of the file
*/

import "core:strconv"
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
import "src:Operation_Stack"

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
    visual: struct{
        anchor: Buffer.Pos_Id,
        line: bool,

        start: Buffer.Pos_Id,
        end:   Buffer.Pos_Id,
    },
    draw: struct{
        line_count: bool,
        status_line: bool,
        camera: Camera,
    },
    search: struct{
        pattern: string,
        found_pos: int,
        found: bool,
    },
    undo: Operation_Stack.Operation_Stack(Buffer.Buffer),
    jump_list: Operation_Stack.Operation_Stack(int), // Maybe do Buffer.Pos_Id
}

Text_Window_Color :: struct{
    color: rl.Color,
    pos:   int, // pos in binary
    len:   int,
    i:     int,
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
    self.undo      = Operation_Stack.create(Buffer.Buffer, app.gpa);
    self.jump_list = Operation_Stack.create(int, app.gpa);

    sync_title(self);
}

update_text_window :: proc(self: ^Text_Window, app: ^App){
    settings := app.settings;
    sync_title(self);

    color_scheme := app.settings.color_scheme;

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
            jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor));
            defer jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor), true);

            for _ in 0..<30{ move_cursor(self, .Up); }
        }
        if match_key_bind(app, PAGE_DOWN){
            jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor));
            defer jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor), true);

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
            pos_y := cast(f32) line * self.app.settings.font.size;
            self.draw.camera.pos.y = math.floor(pos_y - self.box.size.y / 2);
            if self.draw.camera.pos.y < 0 do self.draw.camera.pos.y = 0;
        }       
        if match_key_bind(app, GO_TO_BEGIN_LINE){
            Buffer.set_pos(&self.buffer, self.cursor, Buffer.find_line_begin(self.buffer, self.cursor));
        }
        if match_key_bind(app, GO_TO_END_LINE){
            Buffer.set_pos(&self.buffer, self.cursor, Buffer.find_line_end(self.buffer, self.cursor));
        }
        if match_key_bind(app, GO_TO_BEGIN_FILE){
            jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor));
            defer jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor), true);

            Buffer.set_pos(&self.buffer, self.cursor, 0);
        }
        if match_key_bind(app, GO_TO_END_FILE){
            jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor));
            defer jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor), true);

            Buffer.set_pos(&self.buffer, self.cursor, Buffer.length(self.buffer) - 1);
        }
        if match_key_bind(app, FIND_FORWARD){
            find_next(self, .Forward);
        }
        if match_key_bind(app, FIND_BACKWARD){
            find_next(self, .Backward);
        }

        if match_key_bind(app, MOVE_BY_TAB_FORWARD){
            offset := tab_pos_offset_from_cursor(self);
            for _ in 0..<offset{
                move_cursor(self, .Right);
            }
        }
        if match_key_bind(app, MOVE_BY_TAB_BACKWARD){
            offset := tab_pos_offset_from_cursor(self);
            for _ in 0..<offset{
                move_cursor(self, .Left);
            }
        }

        if match_key_bind(app, JUMP_BACK){
            jump_list_back(self);
        }
        if match_key_bind(app, JUMP_FORWARD){
            jump_list_forward(self);
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
            remove_range(self, self.cursor, 1);
            move_cursor(self, .Right, true);
        }
        if match_key_bind(app, NORMAL_GO_TO_VISUAL){
            go_to_visual_mode(self);
        }
        if match_key_bind(app, NORMAL_GO_TO_VISUAL_LINE){
            go_to_visual_mode(self, true);
        }
        if match_key_bind(app, NORMAL_PASTE){
            paste(self);
        }
        if match_key_bind(app, NORMAL_PASTE_SYSTEM){
            paste(self, true);
        }
        if match_key_bind(app, NORMAL_UNDO){
            undo(self);
        }
        if match_key_bind(app, NORMAL_REDO){
            redo(self); 
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

        if match_key_bind(app, NORMAL_COPY_WORLD_FORWARD){
           copy_by_word(self, .Forward);
        }       
        if match_key_bind(app, NORMAL_COPY_WORLD_BACKWARD){
           copy_by_word(self, .Backward);
        }
        if match_key_bind(app, NORMAL_COPY_WORLD_INSIDE_FORWARD){
            copy_by_word_inside(self, .Forward);
        }
        if match_key_bind(app, NORMAL_COPY_WORLD_INSIDE_BACKWARD){
            copy_by_word_inside(self, .Backward);
        }
        if match_key_bind(app, NORMAL_COPY_RIGHT){
            copy_by_cursor(self, .Right);
        }
        if match_key_bind(app, NORMAL_COPY_LEFT){
            copy_by_cursor(self, .Left);
        }
        if match_key_bind(app, NORMAL_COPY_UNTIL_END_LINE){
            copy_until_end_line(self);
        }
        if match_key_bind(app, NORMAL_COPY_LINE){
            copy_line(self);
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
            asd := tab_pos_offset_from_cursor(self);
            for _ in 0..<asd{
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
            copy_range_i(self, start, select_len); 
        }
        if match_key_bind(app, VISUAL_COPY_SYSTEM){
            copy_range_i(self, start, select_len, true); 
        }
        if match_key_bind(app, VISUAL_CUT){
            copy_range_i(self, start, select_len); 
            remove_range(self, visual.start, select_len);
        }
        if match_key_bind(app, VISUAL_PASTE){
            remove_range(self, visual.start, select_len);
            move_cursor(self, .Right, true);
            paste(self);
        }
        if match_key_bind(app, VISUAL_PASTE_SYSTEM){
            remove_range(self, visual.start, select_len);
            move_cursor(self, .Right, true);
            paste(self, true);
        }
    }
}

draw_text_window :: proc(self: ^Text_Window, app: ^App){
    defer clear(&self.colors);

    color_scheme := self.app.settings.color_scheme;
    font := self.app.settings.font;
    settings := self.app.settings;

    box := self.box;

    if self.draw.status_line{
        status_line: Box;
        box, status_line = remove_padding_side(self.box, font.size + 5, .Bottom);
        draw_status_line(self, status_line);
    }

    ctx := Draw_Context{box = box};
    begin_ctx(ctx);
    defer end_ctx(ctx);

    nr_of_lines := Buffer.get_line_number_i(self.buffer, Buffer.length(self.buffer) - 1);
    line_box: Box;
    if self.draw.line_count{
        box, line_box = remove_padding_side(box, cast(f32) ((count_digits(nr_of_lines) / 4 + 1) * 4) * settings.space_width + 20, .Left);
    }

    cursor_line := Buffer.get_line_number(self.buffer, self.cursor);
    cursor_up_pos   := cast(f32) (cursor_line - 1) * font.size;
    cursor_down_pos := cast(f32) (cursor_line) * font.size;
    
    if cursor_up_pos <= self.draw.camera.pos.y{
        self.draw.camera.pos.y = cursor_up_pos;
    }
    if cursor_down_pos > self.draw.camera.pos.y + box.size.y{
        self.draw.camera.pos.y = cursor_down_pos - box.size.y;
    }

    line_count_ctx := Draw_Context{box = line_box};
    line_count_ctx.camera = self.draw.camera;

    text_ctx := Draw_Context{box = box};
    text_ctx.camera = self.draw.camera;

    // calculate chunk
    line_space := font.size + VSPACING;
    line_seen_by_camera := cast(int) (self.draw.camera.pos.y / line_space) + 1;
    start_rune_pos := Buffer.get_position_of_line(self.buffer, line_seen_by_camera);
    start_draw_pos := cast(f32) (line_seen_by_camera - 1) * line_space;
    nr_of_lines_seen := cast(int) (text_ctx.box.size.y / line_space + 1);

    fill(text_ctx, color_scheme.background1);
    fill(line_count_ctx, color_scheme.background2);
    feeder := Draw_Text_Feeder{
        ctx  = text_ctx,
        pos  = {0, start_draw_pos},
        font = font.font,
        size = font.size,
        hspacing = 1,
        vspacing = VSPACING,
        color = color_scheme.text,
        tab_size = settings.tab_size,
    };
    
    color_idx := 0;    
    text_byte_i := 0;

    line_start := true;
    iter := Buffer.iter(self.buffer);
    if start_rune_pos != 0 {
        for r, i in Buffer.next(&iter){
            for color_idx < len(self.colors){
                window := self.colors[color_idx];

                if window.pos <= text_byte_i && text_byte_i < window.pos + window.len{
                    feeder.color = window.color;
                    break;
                } 
                if text_byte_i < window.pos do break;
                color_idx += 1;
            }
            _, rune_size := utf8.encode_rune(r);
            text_byte_i += rune_size;
            if color_idx >= len(self.colors) do break;

            if !(i < start_rune_pos - 1) {
                break;
            }
        }
    }
    
    Buffer.seek(&iter, start_rune_pos);

    for r, i in Buffer.next(&iter){
        if feeder.line > nr_of_lines_seen do break;

        rune_pos := feeder.pos + feeder.rune_position;

        if self.draw.line_count && line_start{
            line_start = false;
            buffer: [100]u8 = ---;
            pos := v2{0, rune_pos.y};
            number := cursor_line;
            f_line := line_seen_by_camera + feeder.line;
            if f_line < cursor_line  do number = cursor_line - f_line;
            if f_line > cursor_line  do number = f_line - cursor_line;
            if f_line == cursor_line do pos.x += settings.space_width;
            str := strconv.itoa(buffer[:], number);
            draw_text(line_count_ctx, str,
                pos = pos,
                font = font.font,
                size = font.size,
                color = color_scheme.text,
                hspacing = 1,
            );            
        }

        feeder.color = color_scheme.text;
        
        for color_idx < len(self.colors){
            window := self.colors[color_idx];

            if window.pos <= text_byte_i && text_byte_i < window.pos + window.len{
                feeder.color = window.color;
                break;
            } 
            if text_byte_i < window.pos do break;
            color_idx += 1;
        }
        _, rune_size := utf8.encode_rune(r);
        text_byte_i += rune_size;


        feed_rune(&feeder, r);
        width := feeder.rune_draw_width;
        if r == '\n' do width = self.app.settings.space_width;
        rune_box := Box{rune_pos, {width, font.size}};

        if Buffer.get_pos(self.buffer, self.cursor) == i{
            draw_cursor(self, text_ctx, rune_box);
        }

        if r == '\n' do line_start = true;
        if self.mode == .Visual{
            start := Buffer.get_pos(self.buffer, self.visual.start);
            end   := Buffer.get_pos(self.buffer, self.visual.end);
            color := color_scheme.foreground1;
            color.a = 100;            
            rune_box, _ = add_margin_side(rune_box, feeder.hspacing, .Left);
            rune_box, _ = add_margin_side(rune_box, feeder.vspacing, .Top);
            if start <= i && i <= end{
                draw_box(text_ctx, rune_box, color);
            }

        }
    }

    draw_cursor :: proc(self: ^Text_Window, ctx: Draw_Context, box: Box){
        color_scheme := self.app.settings.color_scheme;
        color: rl.Color;
        switch self.mode{
        case .Normal: color = color_scheme.white;
        case .Insert: color = color_scheme.green;
        case .Visual: color = color_scheme.purple;
        }
        color.a = 100;
        draw_box(ctx, box, color);
        color.a = 0xFF;
        draw_box_outline(ctx, box, 1, color);
    }

    draw_status_line :: proc(self: ^Text_Window, status_line: Box){
        status_line := status_line;
        color_scheme := self.app.settings.color_scheme;
        font := self.app.settings.font;

        ctx := Draw_Context{box = status_line};
        begin_ctx(ctx);
        defer end_ctx(ctx);

        status_line.pos = {0, 0};        
        fill(ctx, color_scheme.background3);

        text: string = "";
        switch self.mode{
        case .Normal: text = "NORMAL";
        case .Insert: text = "INSERT";
        case .Visual: text = "VISUAL";
        }
        
        text_box := measure_text(
            ctx = ctx,
            text = text,
            pos = {0, 0},
            size = font.size,
            font = font.font,
            hspacing = 1,
        );
        text_box = align_vertical(text_box, status_line, .Center, .Center);
        draw_text(
            ctx = ctx,
            text = text,
            pos = text_box.pos,
            size = font.size,
            font = font.font,
            color = color_scheme.text,
        );
        
        text_box.pos.x += text_box.size.x + 2;
        draw_text(
            ctx = ctx,
            text = self.title,
            pos = text_box.pos,
            size = font.size,
            font = font.font,
            color = color_scheme.text,
        );
    }

    count_digits :: proc(n: int) -> int{
        n := n;
        count := 0;
        for {
            count += 1;
            n /= 10;
            if n == 0 do break;
        }
        return count;
    }
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

insert_new_line_below :: proc(self: ^Text_Window) -> int{
    end := Buffer.find_line_end(self.buffer, self.cursor);
    insert_rune(self, end, '\n');
    return end;
}

insert_new_line_above :: proc(self: ^Text_Window) -> int{
    begin := Buffer.find_line_begin(self.buffer, self.cursor);
    insert_rune(self, begin, '\n');
    return begin;
}

insert_rune :: proc(self: ^Text_Window, pos: int, r: rune){
    insert_range(self, pos, {r}); 
}

Move_Cursor :: enum{Left, Right, Up, Down}
move_cursor :: proc(self: ^Text_Window, direction: Move_Cursor, wrap := false) -> bool{
    cursor_pos := Buffer.get_pos(self.buffer, self.cursor);
    move_left  := direction == .Left;
    move_right := direction == .Right;
    move_up    := direction == .Up;
    move_down  := direction == .Down;

    if move_left{
        new_pos := cursor_pos - 1;
        current := Buffer.get_rune_i(self.buffer, new_pos);


        if wrap {
            Buffer.set_pos(&self.buffer, self.cursor, new_pos);
            return cursor_pos != new_pos;
        } else {
            if current != 0 && current != '\n'{
                Buffer.set_pos(&self.buffer, self.cursor, new_pos);
                return cursor_pos != new_pos;
            }
        }
    }
    if move_right{
        new_pos := cursor_pos + 1;
        current := Buffer.get_rune_i(self.buffer, new_pos);
        left    := Buffer.get_rune_i(self.buffer, new_pos - 1);

        if wrap {
            Buffer.set_pos(&self.buffer, self.cursor, new_pos);
            return cursor_pos != new_pos;
        } else {
            if current != 0 && left != '\n'{
                Buffer.set_pos(&self.buffer, self.cursor, new_pos);
                return cursor_pos != new_pos;
            }
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
go_to_mode :: proc(self: ^Text_Window, mode: Text_Window_Mode){
    leave_mode(self);
    self.mode = mode;
}

go_to_insert_mode :: proc(self: ^Text_Window){
    go_to_mode(self, .Insert);
    discard_next_rune(self.app);
    push_undo(self, self.buffer);
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
        push_undo(self, self.buffer, true);
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
    jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor));
    Buffer.set_pos(&self.buffer, self.cursor, Buffer.get_position_of_line(self.buffer, line_number));
    jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor), true);
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
    jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor));
    defer jump_list_push(self, Buffer.get_pos(self.buffer, self.cursor), true);

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

push_undo :: proc(self: ^Text_Window, b: Buffer.Buffer, silent := false){
    // Todo(Ferenc): This leaks because Operation_Stack.push removes and not destroy
    if silent do Operation_Stack.silent_push(&self.undo, Buffer.clone(b, self.app.gpa));
    else do Operation_Stack.push(&self.undo, Buffer.clone(b, self.app.gpa));
}

undo :: proc(self: ^Text_Window){
    b, ok := Operation_Stack.back(&self.undo);
    if !ok do return;
    self.buffer = Buffer.clone(b, self.app.gpa);
}

redo :: proc(self: ^Text_Window){
    b, ok := Operation_Stack.forward(&self.undo);
    if !ok do return;
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
    move_cursor(self, .Right, true);
    go_to_insert_mode(self);
}

change_line :: proc(self: ^Text_Window){
    delete_line(self);
    go_to_insert_mode(self);
}

insert_range_cursor :: proc(self: ^Text_Window, array: []rune){
    old_buffer := Buffer.clone(self.buffer, self.app.gpa);
    defer Buffer.destroy(old_buffer);

    for r in array{
        Buffer.insert_rune(&self.buffer, self.cursor, r);
    }
    if !Buffer.text_equal(old_buffer, self.buffer){
        push_undo(self, old_buffer); // Todo(Ferenc): make a push which does not copies for speed
    }
}

insert_range :: proc(self: ^Text_Window, pos: int, array: []rune){
    old_buffer := Buffer.clone(self.buffer, self.app.gpa);
    defer Buffer.destroy(old_buffer);

    for r, idx in array{
        Buffer.insert_rune_i(&self.buffer, pos + idx, r);
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
    color := color;
    color.i = len(self.colors);
    append(&self.colors, color);
}

copy_range_i :: proc(self: ^Text_Window, start, len: int, system := false){
    clear(&self.app.copy_buffer);
    if system {
        str := Buffer.to_string(self.buffer, self.app.fa);
        start_byte_i := 0;
        byte_len := 0;
        count := 0;
        for _, i in str{
            defer count += 1;
            if start == count do start_byte_i = i;
            if start + len == count {
                byte_len = i - start_byte_i;
            }
        }
        asd := s.clone_to_cstring(str[start_byte_i:][:byte_len], self.app.fa);
        rl.SetClipboardText(asd);
    } else {
        for i in 0..<len{
            append(&self.app.copy_buffer, Buffer.get_rune_i(self.buffer, start + i));
        }
    }
}

copy_between_positions :: proc(self: ^Text_Window, p1, p2: int){
    if p1 < p2{
        len := p2 - p1;
        copy_range_i(self, p1, len);
    } else {
        len := p1 - p2;
        copy_range_i(self, p2, len);
    }
}

copy_by_word :: proc(self: ^Text_Window, dir: Condition_Move){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_cursor_by_word(self, dir);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    Buffer.set_pos(&self.buffer, self.cursor, pos);
    copy_between_positions(self, pos, new_pos);
}

copy_by_word_inside :: proc(self: ^Text_Window, dir: Condition_Move){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_cursor_by_word_inside(self, dir);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    Buffer.set_pos(&self.buffer, self.cursor, pos);
    copy_between_positions(self, pos, new_pos);
}

copy_by_cursor :: proc(self: ^Text_Window, direction: Move_Cursor){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_cursor(self, direction);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    Buffer.set_pos(&self.buffer, self.cursor, pos);
    copy_between_positions(self, pos, new_pos);
}

copy_by :: proc(self: ^Text_Window, move_proc: proc(^Text_Window)){
    pos := Buffer.get_pos(self.buffer, self.cursor);
    move_proc(self);
    new_pos := Buffer.get_pos(self.buffer, self.cursor);
    Buffer.set_pos(&self.buffer, self.cursor, pos);
    copy_between_positions(self, pos, new_pos);
}

copy_until_end_line :: proc(self: ^Text_Window){
    copy_between_positions(self, 
        Buffer.get_pos(self.buffer, self.cursor),
        Buffer.find_line_end(self.buffer, self.cursor));
}

copy_line :: proc(self: ^Text_Window){
    copy_between_positions(self, 
        Buffer.find_line_begin(self.buffer, self.cursor),
        Buffer.find_line_end(self.buffer, self.cursor) + 1);
}

paste :: proc(self: ^Text_Window, system := false){
    if system{
        cstr := rl.GetClipboardText();
        array := make([dynamic]rune, allocator = self.app.fa);
        for r in cast(string) cstr{
            append(&array, r);
        }
        insert_range_cursor(self, array[:]);
    } else {
        insert_range_cursor(self, self.app.copy_buffer[:]);
    }
}

tab_pos_offset_from_cursor :: proc(self: ^Text_Window) -> int{
    settings := self.app.settings;
    pos := Buffer.get_pos(self.buffer, self.cursor);
    line_pos := Buffer.find_line_begin(self.buffer, self.cursor);
    pos_from_begin := pos - line_pos;
    tab_pos := settings.tab_size * (pos_from_begin / settings.tab_size + 1);
    offset := tab_pos - pos_from_begin;
    return offset;
}

jump_list_push :: proc(self: ^Text_Window, pos: int, silent := false){
    if silent do Operation_Stack.silent_push(&self.jump_list, pos);
    else do      Operation_Stack.push(&self.jump_list, pos);
}

jump_list_back :: proc(self: ^Text_Window){
    pos, ok := Operation_Stack.back(&self.jump_list);
    if ok do Buffer.set_pos(&self.buffer, self.cursor, pos);
}

jump_list_forward :: proc(self: ^Text_Window){
    pos, ok := Operation_Stack.forward(&self.jump_list);
    if ok do Buffer.set_pos(&self.buffer, self.cursor, pos);
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
MOVE_BY_TAB_FORWARD       :: Key_Bind{Key{key = .TAB}};
MOVE_BY_TAB_BACKWARD      :: Key_Bind{Key{key = .TAB, shift = true}};
CENTER_SCREEN             :: Key_Bind{Key{key = .Z}, Key{key = .Z}};
GO_TO_BEGIN_LINE          :: Key_Bind{Key{key = .H, shift = true}};
GO_TO_END_LINE            :: Key_Bind{Key{key = .L, shift = true}};
GO_TO_BEGIN_FILE          :: Key_Bind{Key{key = .K, shift = true}};
GO_TO_END_FILE            :: Key_Bind{Key{key = .J, shift = true}};
FIND_FORWARD              :: Key_Bind{Key{key = .N}};
FIND_BACKWARD             :: Key_Bind{Key{key = .N, shift = true}};
JUMP_BACK                 :: Key_Bind{Key{key = .O, ctrl = true}};
JUMP_FORWARD              :: Key_Bind{Key{key = .I, ctrl = true}};

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
NORMAL_PASTE_SYSTEM                 :: Key_Bind{{key = .SPACE}, {key = .P}};

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

NORMAL_COPY_WORLD_FORWARD         :: Key_Bind{Key{key = .Y}, {key = .W}};
NORMAL_COPY_WORLD_BACKWARD        :: Key_Bind{Key{key = .Y}, {key = .B}};
NORMAL_COPY_WORLD_INSIDE_FORWARD  :: Key_Bind{Key{key = .Y}, {key = .W, shift = true}};
NORMAL_COPY_WORLD_INSIDE_BACKWARD :: Key_Bind{Key{key = .Y}, {key = .B, shift = true}};
NORMAL_COPY_RIGHT                 :: Key_Bind{Key{key = .Y}, {key = .L}};
NORMAL_COPY_LEFT                  :: Key_Bind{Key{key = .Y}, {key = .H}};
NORMAL_COPY_UNTIL_END_LINE        :: Key_Bind{Key{key = .Y, shift = true}};
NORMAL_COPY_LINE                  :: Key_Bind{Key{key = .Y}, {key = .Y}};

INSERT_REMOVE_RUNE  :: Key_Bind{Key{key = .BACKSPACE}};
INSERT_REMOVE_RUNE2 :: Key_Bind{Key{key = .BACKSPACE, shift = true}};
INSERT_NEW_LINE     :: Key_Bind{Key{key = .ENTER}};
INSERT_TAB          :: Key_Bind{Key{key = .TAB}};

VISUAL_DELETE :: Key_Bind{Key{key = .D}};
VISUAL_COPY   :: Key_Bind{Key{key = .Y}};
VISUAL_CUT    :: Key_Bind{Key{key = .X}};
VISUAL_CHANGE :: Key_Bind{Key{key = .C}};
VISUAL_PASTE  :: Key_Bind{Key{key = .P}};
VISUAL_PASTE_SYSTEM :: Key_Bind{{key = .SPACE}, {key = .P}};
VISUAL_COPY_SYSTEM  :: Key_Bind{{key = .SPACE}, {key = .Y}};

BACK_TO_NORMAL :: Key_Bind{Key{key = .C, ctrl = true}};

VSPACING :: 0; // Todo(Ferenc): add to settings

