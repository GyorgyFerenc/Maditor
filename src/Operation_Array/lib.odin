package Operation_Array

import "src:mem"

Operation_Array :: struct ($T: typeid){
    array: [dynamic]T,
    pos: int,
}

make :: proc($T: typeid, allocator: mem.Allocator){
}

