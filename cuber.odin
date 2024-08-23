package cuber

import "core:fmt"
import "core:mem"
import "vendor:glfw"
import cvk "cvk"

Context :: struct {
    window: glfw.WindowHandle,
    initialized: bool,
    vctx: cvk.VulkanContext,
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    fmt.println("Hello!")
    using ctx: Context
    
    init_ctx(&ctx)
    defer deinit_ctx(&ctx)

    for !glfw.WindowShouldClose(window) { 
        glfw.PollEvents()
        cvk.render(&vctx)
    }
}

init_ctx :: proc(using ctx: ^Context) {
    create_window(ctx, 1280, 720)
    cvk.init_vulkan_ctx(&vctx, window)
    initialized = true
}

deinit_ctx :: proc(using ctx: ^Context) {
    if !initialized do return
    
    cvk.deinit_vulkan_ctx(&vctx)
    glfw.DestroyWindow(window)
    glfw.Terminate()
}

create_window :: proc(using ctx: ^Context, width, height: i32) {
    glfw.Init()
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, 1)

    window = glfw.CreateWindow(width, height, "Cuber", nil, nil)
    glfw.SetWindowUserPointer(window, ctx)
    glfw.SetKeyCallback(window, key_callback)
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	using ctx := cast(^Context)glfw.GetWindowUserPointer(window)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    using ctx := cast(^Context)glfw.GetWindowUserPointer(window)
    if key == glfw.KEY_ESCAPE && action == glfw.RELEASE {
        glfw.SetWindowShouldClose(window, true)
    }
}
