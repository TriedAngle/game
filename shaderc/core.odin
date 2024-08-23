package shaderc

import _c "core:c"

H_ :: 1;
ENV_H_ :: 1;
STATUS_H_ :: 1;

compilerT :: ^compiler;
compileOptionsT :: ^compileOptions;
includeResolveFn :: #type proc(userData : rawptr, requestedSource : cstring, type : _c.int, requestingSource : cstring, includeDepth : _c.size_t) -> ^includeResult;
includeResultReleaseFn :: #type proc(userData : rawptr, includeResult : ^includeResult);
compilationResultT :: ^compilationResult;