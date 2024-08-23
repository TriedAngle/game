package shaderc

import "core:testing"
import "core:fmt"

@(test)
test_shaderc :: proc(t: ^testing.T) {
    compiler := compiler_initialize()
    source :cstring= "#version 310 es\n void main() {}"
    result := compile_into_spv(compiler,source,len(source),.FragmentShader,"shader.frag","main",nil)
    if result_get_compilation_status(result) != compilationStatus.Success {
        panic(string(result_get_error_message(result)))
    }

    lenn := result_get_length(result)
    bytes := result_get_bytes(result)
    shadercode := transmute([]u8)bytes[:lenn]

    fmt.println(shadercode)
}