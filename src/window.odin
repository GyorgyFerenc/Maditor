package main

Window_Proc :: proc(rawptr, ^App);

Window :: struct{
    using window_data: ^Window_Data,

    data: rawptr,
    procedure: Window_Proc,
}

Window_Data :: struct{
    box: Box,
}

do_window :: proc(w: Window, app: ^App){
    w.procedure(w.data, app);
}

