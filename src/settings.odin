package main

import "core:c"
import "core:fmt"
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

    tab_size:    int, // number of spaces
    space_width: f32,
    autosave:    bool,
}

init_settings :: proc(s: ^Settings, app: ^App){
    s.window.size        = {1080, 720};
    s.window.fullscreen  = false;
    s.key_binds.max_wait = 1000 / 4; 
    s.color_scheme       = DEFAULT_COLOR_SCHEME;

    s.font.size = 25;
    s.font.path = "font/InconsolataNerdFont-Regular.ttf";
    //s.font.path = "font/Anonymous Pro.ttf";
    //s.font.path = "font/noto.ttf";


    s.tab_size = 4;
    s.autosave = true;

    apply(s, app);
}

apply :: proc(s: ^Settings, app: ^App){
    if s.window.fullscreen{
        //rl.MaximizeWindow();
    } else {
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
    s.space_width = measure_rune_draw_width(' ', size = s.font.size, font = s.font.font);
}

detect_window_size_change :: proc(app: ^App){
    s := &app.settings;
    size := &s.window.size;
    
    w := cast(int) rl.GetScreenWidth();
    h := cast(int) rl.GetScreenHeight();
    if size.x != w || size.y != h{
        size.x = w;
        size.y = h;
    }
}

window_box :: proc(s: Settings) -> Box{
    return {
        pos = {0, 0},
        size = to_v2(s.window.size),
    }
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
    string:      rl.Color,
    number:      rl.Color,
    operator:    rl.Color,
    separator:   rl.Color,
    punctuation: rl.Color,
    procedure:   rl.Color,
    comment:     rl.Color,
    namespace:   rl.Color,
}

DEFAULT_COLOR_SCHEME  :: ONE_DARK_COLOR_SCHEME;
//DEFAULT_COLOR_SCHEME  :: CONTRAST_COLOR_SCHEME;


CONTRAST_COLOR_SCHEME :: Color_Scheme{
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
    identifier =  rl.WHITE,
    variable =    rl.RED,
    parameter =   rl.RED,
    field =       rl.RED,
    enum_member = rl.ORANGE,
    type =        rl.GREEN,
    constant =    rl.ORANGE,
    string =      rl.GREEN,
    number =      rl.YELLOW,
    operator =    rl.WHITE,
    separator =   rl.WHITE,
    punctuation = rl.WHITE,
    procedure   = rl.BLUE,
    comment     = rl.GRAY,
    namespace   = rl.YELLOW,

}

ONE_DARK_RED    :: rl.Color{0xE0, 0x6C, 0x75, 0xFF};
ONE_DARK_GREEN  :: rl.Color{0x98, 0xC3, 0x79, 0xFF};
ONE_DARK_BLUE   :: rl.Color{0x62, 0xAF, 0xEE, 0xFF};
//ONE_DARK_WHITE  :: rl.Color{0xAA, 0xB2, 0xBF, 0xFF};
ONE_DARK_WHITE  :: rl.Color{0xBA, 0xC2, 0xCF, 0xFF};
ONE_DARK_PURPLE :: rl.Color{0xC6, 0x78, 0xDD, 0xFF};
ONE_DARK_ORANGE :: rl.Color{0xD1, 0x9A, 0x66, 0xFF};
ONE_DARK_YELLOW :: rl.Color{0xD6, 0xB9, 0x6F, 0xFF};

// Todo(Ferenc): Do the rest
ONE_DARK_COLOR_SCHEME :: Color_Scheme{
    gray   = rl.GRAY,
    red    = ONE_DARK_RED,
    green  = ONE_DARK_GREEN,
    blue   = ONE_DARK_BLUE, 
    yellow = ONE_DARK_YELLOW,
    orange = rl.ORANGE,
    pink   = rl.PINK,
    purple = ONE_DARK_PURPLE, 
    brown  = rl.BROWN,
    white  = ONE_DARK_WHITE,
    black  = rl.BLACK,

    background1 = rl.Color{0x28, 0x2c, 0x34, 0xFF},
    background2 = rl.Color{0x28, 0x2c, 0x34, 0xFF},
    background3 = rl.Color{0x28, 0x2c, 0x34, 0xFF},

    foreground1 = ONE_DARK_WHITE, 
    foreground2 = rl.Color{0xEE, 0xEE, 0xEE, 255 },
    foreground3 = rl.Color{0xDD, 0xDD, 0xDD, 255 },

    text =    ONE_DARK_WHITE,
    error =   ONE_DARK_RED,
    warning = ONE_DARK_YELLOW,
    note =    rl.GRAY,

    keyword =     ONE_DARK_PURPLE, 
    identifier =  ONE_DARK_RED,
    variable =    ONE_DARK_RED,
    parameter =   ONE_DARK_RED,
    field =       ONE_DARK_RED,
    enum_member = ONE_DARK_ORANGE, 
    type =        ONE_DARK_YELLOW,
    constant =    ONE_DARK_ORANGE, 
    string =      ONE_DARK_GREEN, 
    number =      ONE_DARK_YELLOW,
    operator =    ONE_DARK_WHITE, 
    separator =   ONE_DARK_WHITE, 
    punctuation = ONE_DARK_WHITE, 
    procedure   = ONE_DARK_BLUE,
    comment     = rl.GRAY,
    namespace   = ONE_DARK_YELLOW,
}

