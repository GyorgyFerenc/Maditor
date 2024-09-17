package main

import "core:fmt"

import "src:Pool_Array"

Window_Id :: Pool_Array.Id;
Window_Proc :: proc(rawptr, ^App);

Window :: struct{
    using window_data: ^Window_Data,

    kind: typeid,
    data: rawptr,
    update:  Window_Proc,
    draw:    Window_Proc,
    destroy: Window_Proc,
}

Window_Data :: struct{
    id: Window_Id,
    box: Box,
}

update_window :: proc(w: Window, app: ^App){
    if w.update != nil do w.update(w.data, app);
}

draw_window :: proc(w: Window, app: ^App){
    if w.draw != nil do w.draw(w.data, app);
}

destroy :: proc(w: Window, app: ^App){
    if w.destroy != nil do w.destroy(w.data, app);
}

is_active :: proc(id: Window_Id, app: ^App) -> bool{
    return app.ui.active_window == id;
}

set_active :: proc(id: Window_Id, app: ^App) {
    app.ui.active_window = id;
}

add_window :: proc(app: ^App, w: Window) -> Window_Id{
    w.id = Pool_Array.alloc(&app.ui.windows, w);
    return w.id;
}

close_window :: proc(app: ^App, id: Window_Id){
    w, ok := get_window(app, id);
    if ok{
        destroy(w, app);
        Pool_Array.free(&app.ui.windows, id);
    }
    if id == app.ui.active_window do app.ui.active_window = Pool_Array.Null_Id;
}

get_window :: proc(app: ^App, id: Window_Id) -> (Window, bool){
    return Pool_Array.get(app.ui.windows, id);
}

get_active_window :: proc(app: ^App) -> (Window, bool){
    return get_window(app, app.ui.active_window);
}

/*
   Generic to window
*/
generic_to_window :: proc(self: ^$T, $update_proc, $draw_proc,$destroy_proc: proc(^T, ^App)) -> Window{
    return {
        window_data = &self.window_data,
        kind = T,
        data = self,
        update = proc(data: rawptr, app: ^App){
            update_proc(cast(^T) data, app);
        },
        draw = proc(data: rawptr, app: ^App){
            draw_proc(cast(^T) data, app);
        },
        destroy = proc(data: rawptr, app: ^App){
            destroy_proc(cast(^T) data, app);
        },
    };
}
