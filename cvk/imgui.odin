package cvk

import "core:fmt"
import "core:os"

import glfw "vendor:glfw"
import vk "vendor:vulkan"
import imgui "../odin-imgui"
import imgui_vk "../odin-imgui/imgui_impl_vulkan"
import imgui_glfw "../odin-imgui/imgui_impl_glfw"

init_imgui :: proc(using vctx: ^VulkanContext, window: glfw.WindowHandle) {
    pool_sizes := []vk.DescriptorPoolSize {
        { .SAMPLER, 1000 },
        { .COMBINED_IMAGE_SAMPLER, 1000 },
        { .SAMPLED_IMAGE, 1000 },
        { .STORAGE_IMAGE, 1000 },
        { .UNIFORM_TEXEL_BUFFER, 1000 },
        { .STORAGE_TEXEL_BUFFER, 1000 },
        { .UNIFORM_BUFFER, 1000 },
        { .STORAGE_BUFFER, 1000 },
        { .UNIFORM_BUFFER_DYNAMIC, 1000 },
        { .STORAGE_BUFFER_DYNAMIC, 1000 },
        { .INPUT_ATTACHMENT, 1000 },
    }

    pinfo := vk.DescriptorPoolCreateInfo {
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        pNext = nil,
        flags = {.FREE_DESCRIPTOR_SET },
        maxSets = 1000,
        poolSizeCount = auto_cast len(pool_sizes),
        pPoolSizes = raw_data(pool_sizes),
    }

    if vk.CreateDescriptorPool(device, &pinfo, nil, &imgui_descriptor_pool) != .SUCCESS {
        fmt.println("Error: Creating IMGUI descriptor pool")
        os.exit(1)
    }

    imgui.CreateContext()

    imgui_vk.LoadFunctions(proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
		return vk.GetInstanceProcAddr(auto_cast user_data, function_name)
	}, auto_cast vctx.instance)


    imgui_glfw.InitForVulkan(window, true)


    imvkprcinfo := vk.PipelineRenderingCreateInfo {
        sType = .PIPELINE_RENDERING_CREATE_INFO,
        pNext = nil,
        colorAttachmentCount = 1,
        pColorAttachmentFormats = &swapchain.format.format,
    }

    imvkinfo := imgui_vk.InitInfo {
        Instance = instance,
        PhysicalDevice = pdevice,
        Device = device,
        Queue = queues[.GCT],
        DescriptorPool = imgui_descriptor_pool,
        MinImageCount = 3,
        ImageCount = 3,
        MSAASamples = {._1},
        UseDynamicRendering = true,
        PipelineRenderingCreateInfo = imvkprcinfo,

    }

    imgui_vk.Init(&imvkinfo)
    imgui_vk.CreateFontsTexture()

    // TODO: fix clearing up imgui
    // lambda(&lambdas, {cast(u64)vctx.imgui_descriptor_pool, proc(vctx: ^VulkanContext, raw: LambdaValue) {
    //     pool := cast(vk.DescriptorPool)raw.(u64)
    //     vk.DestroyDescriptorPool(vctx.device, pool, nil)
    //     imgui_vk.Shutdown()
    //     fmt.println("LOL")
    //     // imgui_glfw.Shutdown()
    // }})
}

@private
render_imgui_prepare :: proc(using vctx: ^VulkanContext) {
    imgui_vk.NewFrame()
    imgui_glfw.NewFrame()
}

@private
render_imgui_finalize :: proc(using vctx: ^VulkanContext, cmd: vk.CommandBuffer, target: vk.ImageView) {
    ainfo := make_attachment_info(target, nil)
    rinfo := make_rendering_info(swapchain.extent, &ainfo, nil)

    vk.CmdBeginRendering(cmd, &rinfo)
    draw := imgui.GetDrawData()
    imgui_vk.RenderDrawData(draw, cmd)
    vk.CmdEndRendering(cmd)
}