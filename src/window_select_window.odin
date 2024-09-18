package main

import "core:math"
import s "core:strings"
import "core:fmt"

import rl "vendor:raylib"

import "src:Pool_Array"

Window_Select_Window :: struct{
    using window_data: Window_Data,

    len: int,
    width: int,
    heigth: int,
    x: int,
    y: int,
}

init_window_select :: proc(self: ^Window_Select_Window, app: ^App){
    self.title = "Window Select";
}

open_window_select :: proc(app: ^App){
    id, ok := app.ui.window_select.?;
    if ok {
        set_active(id, app);
        return;
    }

    w := new(Window_Select_Window, app.gpa);
    init_window_select(w, app);
    id = add_window(app, window_select_to_window(w));
    set_active(id, app);
    app.ui.window_select = id;
}

update_window_select :: proc(self: ^Window_Select_Window, app: ^App){
    if match_key_bind(app, CLOSE_CURRENT){
        close_window(app, get_current_window(self, app));
    }

    self.len    = Pool_Array.length(app.ui.windows)
    if self.len == 0 do return;

    self.width  = cast(int) math.sqrt(cast(f32) self.len);
    self.heigth = self.len / self.width;

    if self.len % self.width != 0{
        self.heigth += 1;
    }

    if self.x >= self.width {
        self.x = self.width - 1;
    }
    if self.y >= self.heigth {
        self.y = self.heigth - 1;
    }

    number := 0;
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
    if match_key_bind(app, SELECT_CURRENT){
        set_active(get_current_window(self, app), app);
    }

    move_cursor :: proc(self: ^Window_Select_Window, dir: enum{Up, Down, Left, Right}){
        switch dir{
        case .Up:
            if self.y > 0 do self.y -= 1;
        case .Down:
            if self.y < self.heigth - 2 {
                self.y += 1;
            } else if self.y == self.heigth - 2 {
                number_of_items := self.len - self.width * (self.heigth - 1);
                if self.x < number_of_items{
                    self.y += 1;
                }
            }
        case .Left:
            if self.x > 0 do self.x -= 1;
        case .Right:
            if self.y < self.heigth - 1{
                if self.x < self.width - 1{
                    self.x += 1;
                }
            } else if self.y == self.heigth - 1 {
                number_of_items := self.len - self.width * (self.heigth - 1);
                if self.x < number_of_items - 1{
                    self.x += 1;
                }
            }
        }
    }
}

draw_window_select :: proc(self: ^Window_Select_Window, app: ^App){
    if self.len == 0 do return;

    color_scheme := app.settings.color_scheme;
    box := self.box;
    begin_box_draw_mode(box);
    defer end_box_draw_mode();
    draw_box(box, color_scheme.background1);

    style := Text_Style{
        font    = app.settings.font.font,
        size    = app.settings.font.size,
        spacing = 1,
        color   = color_scheme.text,
    };

    screen := to_v2(app.settings.window.size);
    box_width:   f32 = screen.x / f32(self.width + 1);
    box_height:  f32 = screen.y / f32(self.heigth + 1);
    horizontal_spacing: f32 = box_width /  cast(f32) self.width;
    vertical_spacing: f32   = box_height / cast(f32) self.heigth;
    current_box := Box{box.pos, {box_width, box_height}};
    start_x := box.pos.x;

    iter := Pool_Array.iter(app.ui.windows);
    for it in Pool_Array.next(&iter){
        x, y := id_to_xy(it.count - 1, self.width);
        draw_box(current_box, color_scheme.background2);
        draw_box_outline(current_box, 2, color_scheme.foreground1);

        w, _ := get_window(app, cast(Window_Id) it.id);
        cstr := s.clone_to_cstring(w.title, app.fa);
        size := measure_text(w.title, style, app.fa);
        text_box := align_vertical(Box{{0, 0}, size}, current_box, .Center, .Center);
        text_box = align_horizontal(text_box, current_box, .Center, .Center);
        rl.DrawTextEx(style.font, cstr, text_box.pos, style.size, style.spacing, style.color);

        if self.x == x && self.y == y{
            color := color_scheme.foreground1;
            color.a = 100;
            draw_box(current_box, color);
        }

        current_box.pos.x += box_width + horizontal_spacing;
        if x + 1 == self.width{
            current_box.pos.x = start_x;
            current_box.pos.y += box_height + vertical_spacing;
        }
    }
}

id_to_xy :: proc(count: int, width: int) -> (x: int, y: int){
    x = count % width;
    y = count / width;
    return x, y;
}

xy_to_id :: proc(x: int, y: int, width: int) -> (count: int){
    count = y * width + x;
    return count;
}

destroy_window_select :: proc(self: ^Window_Select_Window, app: ^App){
    app.ui.window_select = nil;
    free(self, app.gpa);
}

window_select_to_window :: proc(self: ^Window_Select_Window) -> Window{
    return generic_to_window(self, update_window_select, draw_window_select, destroy_window_select);
}

get_current_window :: proc(self: ^Window_Select_Window, app: ^App) -> Window_Id{
    iter := Pool_Array.iter(app.ui.windows);
    for it in Pool_Array.next(&iter){
        x, y := id_to_xy(it.count - 1, self.width);
        if self.x == x && self.y == y{
            return cast(Window_Id) it.id;
        }
    }

    return cast(Window_Id) Pool_Array.Null_Id;
}

SELECT_CURRENT :: Key_Bind{Key{key = .ENTER}};
CLOSE_CURRENT  :: Key_Bind{Key{key = .C}};

