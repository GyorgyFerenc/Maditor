package main

import s "core:strings"
import "core:mem"
import "core:fmt"
import "core:c"
import "core:os"

import rl "vendor:raylib"

import p "src:parser"
import "src:Buffer"

Command_Line :: struct{
    builder: s.Builder,
    active: bool,
    response: string,
    allocator: mem.Allocator,
}

init_command_line :: proc(self: ^Command_Line, allocator: mem.Allocator){
    self.builder = s.builder_make(allocator);
    self.allocator = allocator;
}

update_command_line :: proc(self: ^Command_Line, app: ^App){
    if !self.active{
        if match_key_bind(app, {{key = .SEMICOLON, ctrl = true}}){
            self.active = true;
            //discard_next_rune(app);
            s.builder_reset(&self.builder);
            self.response = "";
        }
        return;
    }

    if match_key_bind(app, {{key = .C, ctrl = true}}) {
        self.active = false;
    }

    for {
        if match_key_bind(app, {{key = .BACKSPACE}}){
            s.pop_rune(&self.builder);
        }
        if match_key_bind(app, {{key = .ENTER}}){
            defer s.builder_reset(&self.builder);

            text := s.to_string(self.builder);
            eval_command(self, app, text);
        }

        r := poll_rune(app);
        if r == 0 do break;

        s.write_rune(&self.builder, r);
    }
}

draw_command_line :: proc(self: ^Command_Line, app: ^App){
    if !self.active do return;

    s.write_rune(&self.builder, '_');
    defer s.pop_rune(&self.builder); 

    window_size := to_v2(app.settings.window.size);
    color_scheme := app.settings.color_scheme;

    box := Box{
        window_size / 10,
        window_size / 10 * 8,
    };
    text_outline :: 2;
    text_padding :: 2;
    help_box, input_line := remove_padding_side(box, app.settings.font.size + text_outline + text_padding, .Top);

    draw_box(input_line, color_scheme.background1);
    draw_box_outline(input_line, text_outline, color_scheme.foreground1);
    input_line = remove_padding(input_line, text_outline + text_padding);
    cstr := s.to_cstring(&self.builder);

    font := app.settings.font;
    style := Text_Style{
        font = font.font,
        size = font.size,
        spacing = 1,
        color = color_scheme.text,
    };
    draw_scrissored_text(cstr, input_line, style);

    draw_box(help_box, color_scheme.background2);
    draw_box_outline(help_box, 2, color_scheme.foreground1);

    inner := remove_padding(help_box, 4);
    cstr = s.clone_to_cstring(self.response, app.fa);
    {
        begin_box_draw_mode(inner);
        rl.DrawTextEx(style.font, cstr, inner.pos, style.size, style.spacing, style.color);
        defer end_box_draw_mode();
    }
    
    draw_scrissored_text :: proc(cstr: cstring, box: Box, text_style: Text_Style){
        text_size := rl.MeasureTextEx(text_style.font, cstr, text_style.size, text_style.spacing);

        begin_box_draw_mode(box);
        defer end_box_draw_mode();

        text_pos := box.pos;
        size := box.size;
        text_pos.y += size.y / 2 - text_size.y / 2;
        if text_size.x > size.x{
            text_pos.x += size.x - text_size.x;
        } 
        rl.DrawTextEx(text_style.font, cstr, text_pos, text_style.size, text_style.spacing, text_style.color);

    }
}

empty_response :: proc(self: ^Command_Line){
    if self.response != ""{
        delete(self.response, self.allocator);
    }
}

set_response :: proc(self: ^Command_Line, str: string){
    empty_response(self);
    self.response = s.clone(str, self.allocator);
}

eval_command :: proc(self: ^Command_Line, app: ^App, text: string){
    sexpr, ok := p.parse_maybe_naked_sexpr(text, app.fa);
    if !ok {
        set_response(self, "Input could not be parse");
        return;
    }

    command, ok1 := get_el_sexpr(sexpr, 0, p.Symbol);
    if !ok {
        set_response(self, "First element must be a symbol");
        return;
    }

    switch command^{
    case "echo":
        str, ok := get_atomic(sexpr, 1, p.String);
        if !ok {
            set_response(self, "Echo expects a string");
            return;
        } else {
            set_response(self, str);
        }
    case "clear":
        empty_response(self);
    case "save", "s":
        window, ok := get_active_window(app);
        if !ok {
            set_response(self, "No active window");
            return;
        }

        if window.kind != Text_Window{
            set_response(self, "Active window is not text window");
            return;
        }
        tw := cast(^Text_Window) window.data;
        buffer := &tw.buffer;

        path, ok1 := get_atomic(sexpr, 1, p.String);
        if ok1 do buffer.path = path;
        Buffer.save(buffer, app.fa);
        set_response(self, "File was saved");
    case "open", "o":
        path, ok := get_atomic(sexpr, 1, p.String);
        if !ok{
            set_response(self, "Open expects a string as path");
            return;
        } 
        
        open_to_text_window(path, app);
    case "open-folder", "of":
        path, ok := get_atomic(sexpr, 1, p.String);
        if !ok{
            set_response(self, "open-folder expects a string as path");
            return;
        } 

        context.temp_allocator = app.fa;
        err := os.set_current_directory(path);
        if err != os.ERROR_NONE{
            set_response(self, "error at opening folder");
        } else {
            set_response(self, "folder succesfully opened");
        }
    case "close", "c":
        close_window(app, app.ui.active_window);
    case "exit", "e":
        app.running = false;
    case:
        set_response(self, "Unkown command");
    }
    
}

get_el_sexpr :: proc(sexpr: ^p.Sexpr, pos: int, $T: typeid) -> (value: ^T, ok: bool){
    moved := sexpr;
    for i in 0..<pos{
        moved = moved.rhs.(^p.Sexpr) or_return;
    }

    return moved.lhs.(^T);
}

get_atomic :: proc(sexpr: ^p.Sexpr, pos: int, $T: typeid) -> (value: T, ok: bool){
    atomic := get_el_sexpr(sexpr, pos, p.Atomic) or_return;
    return atomic^.(T);
}
