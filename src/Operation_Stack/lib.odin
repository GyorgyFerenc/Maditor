package Operation_Array

import "core:mem"

Operation_Stack :: struct ($T: typeid){
    array: [dynamic]T,
    pos: int,
}

create :: proc($T: typeid, allocator: mem.Allocator) -> Operation_Stack(T){
    return Operation_Stack(T){
        array = make([dynamic]T, allocator = allocator),
        pos   = 0,
    };
}

destroy :: proc(self: Operation_Stack($T)){
    delete(self.array);
}

push :: proc(self: ^Operation_Stack($T), value: T){
    if self.pos < len(self.array) {
        remove_range(&self.array, self.pos, len(self.array));
    }
    self.pos += 1;
    append(&self.array, value);
}

silent_push :: proc(self: ^Operation_Stack($T), value: T){
    append(&self.array, value);
}

back :: proc(self: ^Operation_Stack($T)) -> (T, bool){
    if self.pos == 0 do return {}, false;
    self.pos -= 1;
    return self.array[self.pos], true;
}

forward :: proc(self: ^Operation_Stack($T)) -> (T, bool){
    self.pos += 1;
    if self.pos >= len(self.array) {
        self.pos = len(self.array);
        return {}, false;
    }
    return self.array[self.pos], true;
}



