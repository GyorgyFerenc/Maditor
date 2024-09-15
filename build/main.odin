package main

import "core:os"
import "core:c/libc"
import "core:fmt"
import "core:strings"

// Do not care about memory allocation
// this is a script kinda
main :: proc(){
    /* 
        Self rebuild only works on linux
        because windows is a fucking terrible os
    */
    when ODIN_OS == .Linux {
        self_rebuild();
    }

    args := parse_args();
    switch args.kind{
    case .Build:
        build(args);
    case.Help:
        fmt.println(HELP);
    }
}

Args :: struct{
    kind: enum{
        Help,
        Build,
    },
    build: struct{
        mode: enum{
            Debug,
            Release,
            Playground,
        },
        full: bool,
        run:  bool,
        playground: bool,
    },
}

parse_args :: proc() -> Args{
    os_args := os.args[1:];
    args: Args;

    for arg in os_args{
        switch arg{
        case "build":
            args.kind = .Build;
        case "help":
            args.kind = .Help;
        case "-release":
            assert(args.kind == .Build);
            args.build.mode = .Release;
        case "-full":
            assert(args.kind == .Build);
            args.build.full = true;
        case "-run":
            assert(args.kind == .Build);
            args.build.run = true;
        case "-playground":
            assert(args.kind == .Build);
            args.build.mode = .Playground;
        case: 
            fmt.println("Unkown argument", arg);
            panic("");
        }
    }

    return args;
}

build :: proc(args: Args){
    build := args.build;

    switch build.mode{
    case .Debug:
        run(`odin build src -collection:src=src -debug -out:main.exe`);
    case .Release:
        run(`odin build src -collection:src=src -o:speed -out:main.exe`);
    case .Playground:
        run(`odin build src -collection:src=src -debug -define:PLAYGROUND=true -out:main.exe`);
    }

    if args.build.run{
        when ODIN_OS == .Windows {
            run(`.\main.exe`);
        } else when ODIN_OS == .Linux {
            run(`./main.exe`);
        } else {
            panic("Unkown OS");
        }
    }
}


self_rebuild :: proc(){
    main_str  := read_file_or_empty("build/main.odin");
    cache_str := read_file_or_empty("build/cache.tmp");

    cache_hd, err := os.open("build/cache.tmp", os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o700);
    assert(err == os.ERROR_NONE);
    os.write_string(cache_hd, main_str);
    os.close(cache_hd);

    if main_str != cache_str{
        fmt.println("Rebuilding self");
        when ODIN_OS == .Windows {
            fmt.println("Self rebuild is not working on windows becuase it is a fucking terrible os");
            fmt.println("Run 'odin build build -out:build.exe' manualy from the command line");
        } else when  ODIN_OS == .Linux{
            run(`rm build.exe`);
            run(`odin build build -out:build.exe`);
            os.execvp(os.args[0], os.args[1:]);
            os.exit(0);
        } else {
            panic("Unkown OS");
        }
    }

    read_file_or_empty :: proc(path: string) -> string{
        hd, err := os.open(path, os.O_RDONLY);
        if err != os.ERROR_NONE do return "";

        size, err2 := os.file_size(hd);
        if err2 != os.ERROR_NONE do return "";

        buffer := make([]u8, size);
        os.read_full(hd, buffer[:]);
        str := cast(string) buffer;
        return str;
    }
}

run :: proc(str: string){
    fmt.println("[Running]", str);
    cstr := strings.clone_to_cstring(str);
    libc.system(cstr);
}

HELP :: \
`
It is a tool for building the game or other stuff

Usage:
    build [arguments]

Argument:
    help
        Prints this message.

    build
        It builds the game, by default it builds in debug mode.

        -run:
            Runs the game after build

        -release:
            Builds the game in release mode

        -full:
            Builds the dependencies. Currently no dependencies.

        -playground
            Runs the playground instead of the main game

`
