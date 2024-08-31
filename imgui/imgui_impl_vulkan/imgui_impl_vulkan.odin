package imgui_impl_vulkan

import imgui "../"
import vk "vendor:vulkan"

when      ODIN_OS == .Windows do foreign import lib "../imgui_windows_x64.lib"
else when ODIN_OS == .Linux   do foreign import lib "../imgui_linux_x64.a"
else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 { foreign import lib "../imgui_darwin_x64.a" } else { foreign import lib "../imgui_darwin_arm64.a" }
}

// imgui_impl_vulkan.h
// Last checked 4778560
InitInfo :: struct {
	Instance:        vk.Instance,
	PhysicalDevice:  vk.PhysicalDevice,
	Device:          vk.Device,
	QueueFamily:     u32,
	Queue:           vk.Queue,
	PipelineCache:   vk.PipelineCache,
	DescriptorPool:  vk.DescriptorPool,
	Subpass:         u32,
	MinImageCount:   u32,
	ImageCount:      u32,
	MSAASamples:     vk.SampleCountFlags,
	UseDynamicRendering:   bool, 
	ColorAttachmentFormat: vk.Format,

	// Allocation, Debugging
	Allocator:         ^vk.AllocationCallbacks,
	CheckVkResultFn:   proc "c" (err: vk.Result),
	MinAllocationSize: vk.DeviceSize,
}

@(link_prefix="ImGui_ImplVulkan_")
foreign lib {
	// Called by user code
	Init                     :: proc(info: ^InitInfo, render_pass: vk.RenderPass) -> bool ---
	Shutdown                 :: proc() ---
	NewFrame                 :: proc() ---
	RenderDrawData           :: proc(draw_data: ^imgui.DrawData, command_buffer: vk.CommandBuffer, pipeline: vk.Pipeline = {}) ---
	CreateFontsTexture       :: proc() -> bool ---
	DestroyFontsTexture      :: proc() ---
	SetMinImageCount         :: proc(min_image_count: u32) ---

	LoadFunctions :: proc(loader_func: proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction, user_data: rawptr = nil) -> bool ---
}

