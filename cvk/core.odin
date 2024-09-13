package cvk

import "core:fmt"
import "core:os"
import mla "core:math/linalg"

import glfw "vendor:glfw"
import vk "vendor:vulkan"
import vma "../vma"


DEVICE_EXTENSIONS := []cstring{
	"VK_KHR_swapchain",
    "VK_KHR_buffer_device_address",
    "VK_EXT_descriptor_indexing",
    "VK_KHR_timeline_semaphore",
    "VK_KHR_synchronization2",
    "VK_KHR_dynamic_rendering",
}

VALIDATION_LAYERS := []cstring{
    "VK_LAYER_KHRONOS_validation"
}

FRAME_OVERLAP :: 2

VulkanContext :: struct {
    instance: vk.Instance,
    pdevice: vk.PhysicalDevice,
    device: vk.Device,
    vmalloc: vma.Allocator,
    lambdas: LambdaStack,

    frame_number: u64,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
    frames: [FRAME_OVERLAP]FrameData,
    qf_ids: [QueueType]int,
    queues: [QueueType]vk.Queue,

    imm_fence: vk.Fence,
    imm_cmd: vk.CommandBuffer,
    imm_cmdpool: vk.CommandPool,

    imgui_descriptor_pool: vk.DescriptorPool,

    descriptor_allocator: DescriptorAllocator,
    draw_descriptor: vk.DescriptorSet,
    draw_descriptor_layout: vk.DescriptorSetLayout,

    gradient_pipeline: vk.Pipeline,
    gradient_pipeline_layout: vk.PipelineLayout,
}

QueueType :: enum {
    GCT,
    Graphics,
    Compute,
    Transfer,
    Present,
}

Swapchain :: struct {
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    views: []vk.ImageView,
    draw: Image,
    draw_extent: vk.Extent2D,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    present_mode: vk.PresentModeKHR,
    image_count: u32,
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

FrameData :: struct {
    lambdas: LambdaStack,
    cmdpool: vk.CommandPool,
    cmdbuffer: vk.CommandBuffer,
    swapchain_semaphore, render_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
}

Image :: struct {
    image: vk.Image,
    view: vk.ImageView,
    allocation: vma.Allocation,
    extent: vk.Extent3D,
    format: vk.Format,
}

ComputePushConstants :: struct {
    data0, data1, data2, data3: mla.Vector4f32,
}

current_frame :: proc(vctx: ^VulkanContext) -> ^FrameData {
    return &vctx.frames[vctx.frame_number % FRAME_OVERLAP]
}

init_vulkan_ctx :: proc(using vctx: ^VulkanContext, window: glfw.WindowHandle) {
	context.user_ptr = &instance
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}
	vk.load_proc_addresses(get_proc_address)

    window_extensions := glfw.GetRequiredInstanceExtensions();

    width, height := glfw.GetFramebufferSize(window)

    create_instance(vctx, window_extensions)
    create_surface(vctx, window)
    create_device(vctx)
    create_vma(vctx)
    create_queues(vctx)
    query_swapchain_details(vctx)
    create_swapchain(vctx, auto_cast width, auto_cast height)
    create_commands(vctx)
    create_sync_structures(vctx)
    create_descriptors(vctx)
    create_pipelines(vctx)
    init_imgui(vctx, window)
}

deinit_vulkan_ctx :: proc(using vctx: ^VulkanContext) {
    vk.DeviceWaitIdle(device)

    vk.DestroyPipelineLayout(device, gradient_pipeline_layout, nil)
    vk.DestroyPipeline(device, gradient_pipeline, nil)

    deinit_descriptor_allocator(&descriptor_allocator, device)
    vk.DestroyDescriptorSetLayout(device, draw_descriptor_layout, nil)

    vk.DestroyDescriptorPool(device, imgui_descriptor_pool, nil)

    vk.DestroyImageView(device, swapchain.draw.view, nil)
    vma.DestroyImage(vmalloc, swapchain.draw.image, swapchain.draw.allocation)

    flush(&lambdas, vctx)
    for &frame in frames {
        vk.DestroyFence(device, frame.render_fence, nil)
        vk.DestroySemaphore(device, frame.render_semaphore, nil)
        vk.DestroySemaphore(device, frame.swapchain_semaphore, nil)
        vk.DestroyCommandPool(device, frame.cmdpool, nil)
        flush(&frame.lambdas, vctx)
        delete(frame.lambdas.lambdas)
    }

    vk.DestroyFence(device, imm_fence, nil)
    vk.DestroyCommandPool(device, imm_cmdpool, nil)

    for view in swapchain.views {
        vk.DestroyImageView(device, view, nil)
    }

    
    delete(lambdas.lambdas)
    delete(swapchain.images)
    delete(swapchain.formats)
    delete(swapchain.views)
    delete(swapchain.present_modes)
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)
    vk.DestroySurfaceKHR(instance, surface, nil)
    vma.DestroyAllocator(vmalloc)
    vk.DestroyDevice(device, nil)
    vk.DestroyInstance(instance, nil)
}

create_vma :: proc(using vctx: ^VulkanContext) {
    vkfns := vma.create_vulkan_functions()

    info := vma.AllocatorCreateInfo {
        instance = instance,
        physicalDevice = pdevice,
        device = device,
        vulkanApiVersion = vk.API_VERSION_1_3,
        flags = {.BUFFER_DEVICE_ADDRESS},
        pVulkanFunctions = &vkfns
    }

    if vma.CreateAllocator(&info, &vmalloc) != .SUCCESS {
        fmt.eprintfln("Error: failed to create vulkan allocator")
    }
}

create_surface :: proc(using vctx: ^VulkanContext, window: glfw.WindowHandle) {
    glfw.CreateWindowSurface(instance, window, nil, &surface)
}

create_commands :: proc(using vctx: ^VulkanContext) {
    pinfo: vk.CommandPoolCreateInfo
    pinfo.sType = .COMMAND_POOL_CREATE_INFO
    pinfo.flags = {.RESET_COMMAND_BUFFER}
    pinfo.queueFamilyIndex = auto_cast qf_ids[.GCT]

    for i in 0..<FRAME_OVERLAP {
        if vk.CreateCommandPool(device, &pinfo, nil, &frames[i].cmdpool) != .SUCCESS {
            fmt.eprintfln("Error: failed to create CommandPool!")
            os.exit(0)
        }

        binfo: vk.CommandBufferAllocateInfo
        binfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
        binfo.commandPool = frames[i].cmdpool
        binfo.commandBufferCount = 1
        binfo.level = .PRIMARY

        if vk.AllocateCommandBuffers(device, &binfo, &frames[i].cmdbuffer) != .SUCCESS {
            fmt.eprintfln("Error: failed to create CommandBuffer!")
            os.exit(0)
        }
    }

    if vk.CreateCommandPool(device, &pinfo, nil, &imm_cmdpool) != .SUCCESS {
        fmt.eprintfln("Error: failed to create CommandPool!")
        os.exit(0)
    }

    binfo: vk.CommandBufferAllocateInfo
    binfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    binfo.commandPool = imm_cmdpool
    binfo.commandBufferCount = 1
    binfo.level = .PRIMARY

    if vk.AllocateCommandBuffers(device, &binfo, &imm_cmd) != .SUCCESS {
        fmt.eprintfln("Error: failed to create CommandBuffer!")
        os.exit(0)
    }
}

create_sync_structures :: proc(using vctx: ^VulkanContext) {
    finfo := vk.FenceCreateInfo {
        sType = .FENCE_CREATE_INFO,
        pNext = nil,
        flags = {.SIGNALED },
    }
    sinfo := vk.SemaphoreCreateInfo {
        sType = .SEMAPHORE_CREATE_INFO,
        pNext = nil,
    }

    for &frame in frames {
        vk.CreateFence(device, &finfo, nil, &frame.render_fence)
        vk.CreateSemaphore(device, &sinfo, nil, &frame.render_semaphore)
        vk.CreateSemaphore(device, &sinfo, nil, &frame.swapchain_semaphore)
    }

    vk.CreateFence(device, &finfo, nil, &imm_fence)
}

create_descriptors :: proc(using vctx: ^VulkanContext) {
    sizes := [1]PoolSizeRatio{{.STORAGE_IMAGE, 1}}
    init_descriptor_pool(&descriptor_allocator, device, 10, sizes[:])

    {
        builder: DescriptorLayoutBuilder
        add_binding(&builder, 0, .STORAGE_IMAGE)
        draw_descriptor_layout = build_descriptor_set(&builder, device, {.COMPUTE})
        clear_bindings(&builder)
        delete(builder.bindings)
    }

    draw_descriptor = allocate_descriptor_set(&descriptor_allocator, device, &draw_descriptor_layout)

    img_info := vk.DescriptorImageInfo {
        imageLayout = .GENERAL,
        imageView = swapchain.draw.view,
    }

    draw_write := vk.WriteDescriptorSet {
        sType = .WRITE_DESCRIPTOR_SET,
        pNext = nil,
        dstBinding = 0,
        dstSet = draw_descriptor,
        descriptorCount = 1,
        descriptorType = .STORAGE_IMAGE,
        pImageInfo = &img_info,
    }
    vk.UpdateDescriptorSets(device, 1, &draw_write, 0, nil)

}

immidiate_submit :: proc(using vctx: ^VulkanContext, other: rawptr, p: proc(vctx: ^VulkanContext, cmd: vk.CommandBuffer, other: rawptr)) {
    vk.ResetFences(device, 1, &imm_fence)
    vk.ResetCommandBuffer(imm_cmd, {})

    cmd := imm_cmd
    binfo := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }

    vk.BeginCommandBuffer(cmd, &binfo)
    
    p(vctx, cmd, other)

    vk.EndCommandBuffer(cmd)

    cmdinfo := make_command_buffer_submit_info(cmd)
    submitinfo := make_submit_info(&cmdinfo, nil, nil)

    vk.QueueSubmit2(queues[.GCT], 1, &submitinfo, imm_fence)
    vk.WaitForFences(device, 1, &imm_fence, true, 1000000000)
}