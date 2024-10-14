package main

import "core:os"
import "core:fmt"
import s "core:strings"
import "core:mem"
import "core:strings"
import "core:path/filepath"

File_Explorer :: struct{
    using window_data: Window_Data,
    app: ^App,
    dir: File,
    open_dirs: map[string]string,
    cursor: struct{
        pos: [dynamic]int,
        file: ^File,
        drawn_y: f32,
        drawn_height: f32,
    },
    camera: Camera,
    mode: File_Explorer_Mode,
}

File_Explorer_Mode :: enum{
    Normal,
    Delete,
    Create,
    Rename,
}

open_file_explorer :: proc(app: ^App){
    id, ok := app.ui.file_explorer.?;
    if ok {
        set_active(id, app);
        return;
    }

    w := new(File_Explorer, app.gpa);
    init_file_explorer(w, app);
    id = add_window(app, file_explorer_to_window(w));
    set_active(id, app);
    app.ui.file_explorer = id;
    w.mode = .Normal;
}

init_file_explorer :: proc(self: ^File_Explorer, app: ^App){
    self.app = app;
    self.cursor.pos = make([dynamic]int, allocator = app.gpa);
    self.open_dirs  = make(map[string]string, allocator = app.gpa);
    self.title = "File Explorer";
}

destroy_file_explorer :: proc(self: ^File_Explorer, app: ^App){
    delete(self.cursor.pos);
    delete(self.open_dirs);
}

update_file_explorer :: proc(self: ^File_Explorer, app: ^App){
    cur_dir := os.get_current_directory(self.app.fa);
    init_file(self, &self.dir, cur_dir, self.app.fa);
    sync_cursor(self);

    cmd := &app.ui.cmd;
    text: string;

    context.allocator = self.app.fa;
    context.temp_allocator = self.app.fa;

    parent, ok := get_cursor_parent(self);
    cursor_dir := cur_dir;
    if ok do cursor_dir = parent.fullpath;

    switch self.mode{
    case .Normal: update_normal(self);
    case .Delete:
        if state := input_mode_state(cmd, self.app.fa, &text); state != .Ongoing{
            if state == .Ended{
                if text == "y" || text == "Y"{
                    remove(self.cursor.file^);
                }
            }
            go_to(self, .Normal);
        }
    case .Create:
        if state := input_mode_state(cmd, self.app.fa, &text); state != .Ongoing{
            if state == .Ended && text != ""{
                if s.contains(text, "/"){
                    path := cursor_dir;
                    for {
                        i := s.index(text, "/");
                        if i == -1 do break;
                        substr := text[:i];
                        path = filepath.join({path, substr}, self.app.fa);
                        os.make_directory(path, 0o771);
                        text = text[i + 1:];
                    }
                    if text != "" {
                        path = filepath.join({path, text}, self.app.fa);
                        create_file(path);
                    }
                } else {
                    path := filepath.join({cursor_dir, text}, self.app.fa);
                    create_file(path);
                }
            }
         
            go_to(self, .Normal);
        }
    case .Rename:
        if state := input_mode_state(cmd, self.app.fa, &text); state != .Ongoing{
            if state == .Ended && text != ""{
                path := filepath.join({cursor_dir, text}, self.app.fa);
                os.rename(self.cursor.file.fullpath, path);
            }
         
            go_to(self, .Normal);
        }
    }

    remove :: proc(file: File){
        if file.is_dir{
            for f in file.dir.files{
                remove(f);
            }

            err := os.remove_directory(file.fullpath);
            if err != os.ERROR_NONE do fmt.println(err);
        } else {
            err := os.remove(file.fullpath);
            if err != os.ERROR_NONE do fmt.println(err);
        }
    }

    create_file :: proc(path: string){
        hd, err := os.open(path, os.O_CREATE, 0o661);
        if err == os.ERROR_NONE do os.close(hd);
    }
}

go_to :: proc(self: ^File_Explorer, mode: File_Explorer_Mode){
    cmd := &self.app.ui.cmd;
    self.mode = mode;

    switch mode{
    case .Normal: 
    case .Delete:
        start_input_mode(cmd);
        set_response(cmd, "Confirm Deletion (y/n)");
    case .Create:
        start_input_mode(cmd);
        set_response(cmd, "Create a new file");
    case .Rename:
        start_input_mode(cmd);
        set_response(cmd, "Rename the file");
    }
}

update_normal :: proc(self: ^File_Explorer){
    app := self.app;
    cur := os.get_current_directory(self.app.fa);

    counter: int;
    if match_key_bind(app, FE_MOVE_UP, &counter){
        for _ in 0..<counter{
            move_cursor_up(self);
        }
    }
    if match_key_bind(app, FE_MOVE_DOWN, &counter){
        for _ in 0..<counter{
            move_cursor_down(self);
        }
    }
    if match_key_bind(app, FE_DELETE_FILE) do go_to(self, .Delete);
    if match_key_bind(app, FE_CREATE_FILE) do go_to(self, .Create);
    if match_key_bind(app, FE_RENAME_FILE) do go_to(self, .Rename);

    if match_key_bind(app, FE_GO_FILE, &counter){
        fp := self.cursor.file.fullpath;
        if self.cursor.file.is_dir{
            if fp in self.open_dirs {
                cfp := self.open_dirs[fp];
                delete(cfp, allocator = app.gpa);
                delete_key(&self.open_dirs, fp);
            } else {
                cfp := strings.clone(fp, app.gpa);
                self.open_dirs[cfp] = cfp;
            }
        } else {
            s := fp[len(cur) + 1:];
            open_to_text_window(s, app);
        }
    }

    if self.cursor.drawn_y < self.camera.pos.y{
        self.camera.pos.y = self.cursor.drawn_y;
    }
    bottom := self.cursor.drawn_y + self.cursor.drawn_height;
    if bottom >= self.camera.pos.y + cast(f32) app.settings.window.size.y{
        self.camera.pos.y = bottom - cast(f32) app.settings.window.size.y;
    }
}

draw_file_explorer :: proc(self: ^File_Explorer, app: ^App){
    color_scheme := app.settings.color_scheme;
    ctx := Draw_Context{box = self.box};
    ctx.camera = self.camera;

    fill(ctx, color_scheme.background1);
    draw_file(ctx, self, self.dir, {0, 0});
}

file_explorer_to_window :: proc(self: ^File_Explorer) -> Window{
    return generic_to_window(self, update_file_explorer, draw_file_explorer, destroy_file_explorer);
}

sync_cursor :: proc(self: ^File_Explorer){
    file, ok := get_file(self, self.cursor.pos[:]);
    if !ok {
        move_cursor_up(self);
        //clear_cursor(self);
        return;
    }

    self.cursor.file = file;
}

get_file :: proc(self: ^File_Explorer, pos: []int) -> (^File, bool){
    file := &self.dir;

    for idx in pos{
        if !file.is_dir do return {}, false; 
        if idx < 0 || idx >= len(file.dir.files) do return {}, false;
        file = &file.dir.files[idx];
    }

    return file, true;
}

clear_cursor :: proc(self: ^File_Explorer){
    self.cursor.file = &self.dir;
    clear(&self.cursor.pos);
}

get_cursor_parent :: proc(self: ^File_Explorer) -> (^File, bool){
    if len(self.cursor.pos) == 0 do return {}, false;

    last_pos := len(self.cursor.pos) - 1;
    return get_file(self, self.cursor.pos[:last_pos]);
}

move_cursor_up :: proc(self: ^File_Explorer, enter_dir := true){
    if len(self.cursor.pos) == 0 do return;

    last_pos := len(self.cursor.pos) - 1;
    parent, ok1 := get_cursor_parent(self);
    if !ok1 do return;

    pos := self.cursor.pos[last_pos] - 1;
    if pos < 0 || pos >= len(parent.dir.files){
        pop(&self.cursor.pos);
        self.cursor.file = parent;
    } else {
        self.cursor.pos[last_pos] = pos;
        self.cursor.file = &parent.dir.files[pos];

        if self.cursor.file.is_dir && 
           self.cursor.file.dir.open && 
           enter_dir{
            move_cursor_down(self);
        }
    }
}

move_cursor_down :: proc(self: ^File_Explorer, enter_dir := true){
    if self.cursor.file.is_dir && 
       self.cursor.file.dir.open &&
       enter_dir &&
       len(self.cursor.file.dir.files) > 0{
        append(&self.cursor.pos, 0);
        return;
    }
    if len(self.cursor.pos) == 0 do return;

    last_pos := len(self.cursor.pos) - 1;
    parent, ok1 := get_file(self, self.cursor.pos[:last_pos]);
    if !ok1 do return;

    pos := self.cursor.pos[last_pos] + 1;
    if pos < 0 || pos >= len(parent.dir.files){
        pop(&self.cursor.pos);
        self.cursor.file = parent;
        if self.cursor.file != &self.dir do move_cursor_down(self, false);
    } else {
        self.cursor.pos[last_pos] = pos;
        self.cursor.file = &parent.dir.files[pos];
    }
}

draw_file :: proc(ctx: Draw_Context, self: ^File_Explorer, file: File, pos: v2) -> f32{
    pos := pos;
    color_scheme := self.app.settings.color_scheme;
    font := self.app.settings.font;

    icon_size := font.size;

    if file.is_dir{
        if file.dir.open{
            draw_rune(
                ctx   = ctx, 
                r     = '+', 
                size  = icon_size,
                pos   = pos, 
                font  = font.font,
                color = color_scheme.text,
            );
        } else{
            draw_rune(
                ctx   = ctx, 
                r     = '-', 
                size  = icon_size,
                pos   = pos, 
                font  = font.font,
                color = color_scheme.text,
            );
        }
    } else {
        draw_rune(
            ctx   = ctx, 
            r     = ' ', 
            size  = icon_size,
            pos   = pos, 
            font  = font.font,
            color = color_scheme.text,
        );
    }

    height: f32 = 0;
    box := draw_text(
        ctx  = ctx,
        text = file.name,
        pos  = pos + {icon_size + 5, 0},
        size = font.size,
        font = font.font,
        color = color_scheme.text,
        hspacing = 1,
        vspacing = 1,
    );
    height += box.size.y;
    pos.y += height;

    red := color_scheme.red;
    red.a = 128;
    if file.fullpath == self.cursor.file.fullpath{
        draw_box(ctx, box, red);
        self.cursor.drawn_y = box.pos.y;
        self.cursor.drawn_height = box.size.y;
    }

    if file.is_dir && file.dir.open{
        indent: f32 = 20;
        pos.x += indent;
        defer pos.x -= indent;

        for f in file.dir.files{
            draw_height := draw_file(ctx, self, f, pos);
            height += draw_height;
            pos.y += draw_height;
        }
    }
    return height;
}

File :: struct{
    using info: os.File_Info,

    dir: struct{
        files: []File,
        open:  bool,
    },
}

init_file :: proc(self: ^File_Explorer, file: ^File, path: string, fa: mem.Allocator) -> (bool){
    context.allocator = fa;
    context.temp_allocator = fa;
    file.name = "[ERROR AT LOADING FILES]";

    info, err1 := os.stat(path, fa);
    if err1 != os.ERROR_NONE do return false;
    file.info = info;

    if file.is_dir {
        if file.fullpath in self.open_dirs{
            file.dir.open = true;
        } 

        hd, err2 := os.open(file.fullpath, os.O_RDONLY);
        if err2 != os.ERROR_NONE do return false;
        defer os.close(hd);

        infos, err3 := os.read_dir(hd, 0, fa);
        if err3 != os.ERROR_NONE do return false;
        
        file.dir.files = make([]File, len(infos), allocator = fa);
        for info, idx in infos{
            init_file(self, &file.dir.files[idx], info.fullpath, fa);
        }
    }

    return true;
}

FE_MOVE_UP     :: Key_Bind{Key{key = .K}};
FE_MOVE_DOWN   :: Key_Bind{Key{key = .J}};
FE_GO_FILE     :: Key_Bind{Key{key = .ENTER}};
FE_CREATE_FILE :: Key_Bind{Key{key = .A}};
FE_DELETE_FILE :: Key_Bind{Key{key = .D}};
FE_RENAME_FILE :: Key_Bind{Key{key = .R}};






