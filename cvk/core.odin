package cvk

import "core:fmt"
import "core:os"

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

    frame_number: u64,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
    frames: [FRAME_OVERLAP]FrameData,
    qf_ids: [QueueType]int,
    queues: [QueueType]vk.Queue,
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
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    present_mode: vk.PresentModeKHR,
    image_count: u32,
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

FrameData :: struct {
    cmdpool: vk.CommandPool,
    cmdbuffer: vk.CommandBuffer,
    swapchain_semaphore, render_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
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
    create_image_views(vctx)
    create_commands(vctx)
    create_sync_structures(vctx)
}

deinit_vulkan_ctx :: proc(using vctx: ^VulkanContext) {
    vk.DeviceWaitIdle(device)
    vma.DestroyAllocator(vmalloc)
    for frame in frames {
        vk.DestroyFence(device, frame.render_fence, nil)
        vk.DestroySemaphore(device, frame.render_semaphore, nil)
        vk.DestroySemaphore(device, frame.swapchain_semaphore, nil)
        vk.DestroyCommandPool(device, frame.cmdpool, nil)
    }
    for view in swapchain.views {
        vk.DestroyImageView(device, view, nil)
    }
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)
    vk.DestroySurfaceKHR(instance, surface, nil)
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
}