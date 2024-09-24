package main

import "core:c"
import "core:math"


v2  :: [2]f32;
v2i :: [2]int;
v2ci:: [2]c.int;

v2_to_v2ci :: proc(v: v2) -> v2ci{
    return {cast(c.int) v.x, cast(c.int) v.y};
}

// Todo(Ferenc): add rest
to_v2ci :: proc{
    v2_to_v2ci,
}

v2i_to_v2 :: proc(v: v2i) -> v2{
    return v2{cast(f32) v.x, cast(f32) v.y};
}

to_v2 :: proc{
    v2i_to_v2,
}

floor_v2 :: proc(p: v2) -> v2{
    return {
        math.floor(p.x),
        math.floor(p.y),
    }
}

