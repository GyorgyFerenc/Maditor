package main

File_Explorer :: struct{
    using window_data: Window_Data,
    app: ^App,
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
}

init_file_explorer :: proc(self: ^File_Explorer, app: ^App){
    self.app = app;
}

update_file_explorer :: proc(self: ^File_Explorer, app: ^App){
}

draw_file_explorer :: proc(self: ^File_Explorer, app: ^App){
    color_scheme := app.settings.color_scheme;
    ctx := Draw_Context{box = self.box};

    fill(ctx, color_scheme.background1);
}

destroy_file_explorer :: proc(self: ^File_Explorer, app: ^App){
}

file_explorer_to_window :: proc(self: ^File_Explorer) -> Window{
    return generic_to_window(self, update_file_explorer, draw_file_explorer, destroy_file_explorer);
}




