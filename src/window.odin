package main

import "src:Pool_Array"

Window_Id :: Pool_Array.Id;
Window_Proc :: proc(rawptr, ^App);

Window :: struct{
    using window_data: ^Window_Data,

    data: rawptr,
    procedure: Window_Proc,
    destroy: Window_Proc,
}

Window_Data :: struct{
    id: Window_Id,
    box: Box,
}

do_window :: proc(w: Window, app: ^App){
    if w.procedure != nil do w.procedure(w.data, app);
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
}

get_window :: proc(app: ^App, id: Window_Id) -> (Window, bool){
    return Pool_Array.get(app.ui.windows, id);
}

/*
   Generic to window
*/
generic_to_window :: proc(self: ^$T, $do_proc, $destroy_proc: proc(^T, ^App)) -> Window{
    return {
        window_data = &self.window_data,
        data = self,
        procedure = proc(data: rawptr, app: ^App){
            do_proc(cast(^T) data, app);
        },
        destroy = proc(data: rawptr, app: ^App){
            destroy_proc(cast(^T) data, app);
        },
    };
}
