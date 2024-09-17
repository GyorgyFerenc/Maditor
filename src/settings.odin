package main

import "core:c"
import "core:strings"

import rl "vendor:raylib"

Settings :: struct{
    window: struct{
        size: v2i,
        fullscreen: bool,
    },
    key_binds: struct{
        max_wait: f32, // ms
    },
    color_scheme: Color_Scheme,
    font: struct{
        size: f32,
        path: string,
        font: rl.Font,
        loaded: bool,
    },

    tab_size: int,
    autosave: bool,
}

init_settings :: proc(s: ^Settings, app: ^App){
    s.window.size        = {1080, 720};
    s.window.fullscreen  = false;
    s.key_binds.max_wait = 1000 / 4; 
    s.color_scheme       = DEFAULT_COLOR_SCHEME;

    s.font.size = 20;
    s.font.path = "font/InconsolataNerdFont-Regular.ttf";

    s.tab_size = 4;
    s.autosave = true;

    apply(s, app);
}

apply :: proc(s: ^Settings, app: ^App){
    if s.window.fullscreen{
        rl.SetWindowState({.FULLSCREEN_MODE});
    } else {
        rl.ClearWindowState({.FULLSCREEN_MODE});
    }

    rl.SetWindowSize(cast(c.int) s.window.size.x, cast(c.int) s.window.size.y);

    app.key_binds.max_wait = s.key_binds.max_wait;

    if s.font.loaded{
        rl.UnloadFont(s.font.font);
    }
    s.font.font = rl.LoadFontEx(
        strings.clone_to_cstring(s.font.path, app.fa),
        cast(c.int) s.font.size,
        nil,
        0,
    );
    s.font.loaded = true;
}

Color_Scheme :: struct{
    gray:   rl.Color,
    red:    rl.Color,
    green:  rl.Color,
    blue:   rl.Color,
    yellow: rl.Color,
    orange: rl.Color,
    pink:   rl.Color,
    purple: rl.Color,
    brown:  rl.Color,
    white:  rl.Color,
    black:  rl.Color,

    background1: rl.Color,
    background2: rl.Color,
    background3: rl.Color,

    foreground1: rl.Color,
    foreground2: rl.Color,
    foreground3: rl.Color,

    text:    rl.Color,
    error:   rl.Color,
    warning: rl.Color,
    note:    rl.Color,

    keyword:     rl.Color,
    identifier:  rl.Color,
    variable:    rl.Color,
    parameter:   rl.Color,
    field:       rl.Color,
    enum_member: rl.Color,
    type:        rl.Color,
    constant:    rl.Color,
    str:         rl.Color,
    number:      rl.Color,
    operator:    rl.Color,
    separator:   rl.Color,
    punctuation: rl.Color,
}

DEFAULT_COLOR_SCHEME :: Color_Scheme{
    gray =   rl.GRAY,
    red =    rl.RED,
    green =  rl.GREEN,
    blue =   rl.BLUE,
    yellow = rl.YELLOW,
    orange = rl.ORANGE,
    pink =   rl.PINK,
    purple = rl.PURPLE,
    brown =  rl.BROWN,
    white =  rl.WHITE,
    black =  rl.BLACK,

    background1 = rl.BLACK,
    background2 = rl.Color{20, 20, 20, 255},
    background3 = rl.Color{40, 40, 40, 255 },

    foreground1 = rl.WHITE,
    foreground2 = rl.Color{0xEE, 0xEE, 0xEE, 255 },
    foreground3 = rl.Color{0xDD, 0xDD, 0xDD, 255 },

    text =    rl.WHITE,
    error =   rl.RED,
    warning = rl.YELLOW,
    note =    rl.GRAY,

    keyword =     rl.PURPLE,
    identifier =  rl.RED,
    variable =    rl.RED,
    parameter =   rl.RED,
    field =       rl.RED,
    enum_member = rl.ORANGE,
    type =        rl.GREEN,
    constant =    rl.ORANGE,
    str =         rl.GREEN,
    number =      rl.YELLOW,
    operator =    rl.WHITE,
    separator =   rl.WHITE,
    punctuation = rl.WHITE,
}
