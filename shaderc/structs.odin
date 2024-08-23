package shaderc

import "core:c"

compiler :: struct {};

compileOptions :: struct {};

includeResult :: struct {
    sourceName : cstring,
    sourceNameLength : c.size_t,
    content : cstring,
    contentLength : c.size_t,
    userData : rawptr,
};

compilationResult :: struct {};