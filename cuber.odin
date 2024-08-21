package kette

import "core:fmt"
import "core:time"
import "core:thread"
import "core:os"
import "core:mem"
import "core:math"

import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"

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

Context :: struct {
    initialized: bool,
    frame_number: u64,
    pause_render: bool,
    window_extent: vk.Extent2D,
    window: glfw.WindowHandle,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
    framebuffer_resized: bool,
    frames: [FRAME_OVERLAP]FrameData,
    qf_ids: [QueueType]int,
    queues: [QueueType]vk.Queue,
    instance: vk.Instance,
    pdevice: vk.PhysicalDevice,
    device: vk.Device,
    
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
        render(&ctx)
    }
}

init_ctx :: proc(ctx: ^Context) {
    init_window(ctx, 1280, 720)
    init_vulkan(ctx)
    create_swapchain(ctx)
    create_image_views(ctx)
    create_commands(ctx)
    create_sync_structures(ctx)
    ctx.initialized = true
}

deinit_ctx :: proc(using ctx: ^Context) {
    if !initialized {
        return
    }
    vk.DeviceWaitIdle(device)
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
    glfw.DestroyWindow(window)
    glfw.Terminate()
}

render :: proc(using ctx: ^Context) {
    frame := current_frame(ctx)
    vk.WaitForFences(device, 1, &frame.render_fence, true, 1000000000)
    vk.ResetFences(device, 1, &frame.render_fence)
    
    image_index: u32
    vk.AcquireNextImageKHR(device, swapchain.handle, 1000000000, frame.swapchain_semaphore, {}, &image_index)

    cmd := frame.cmdbuffer
    vk.ResetCommandBuffer(cmd, {})

    binfo := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }
    vk.BeginCommandBuffer(cmd, &binfo)

    transition_image(cmd, swapchain.images[image_index], .UNDEFINED, .GENERAL)

    flash: f32 = math.abs(math.sin(f32(frame_number) / 120.0)) 
    clear_color := vk.ClearColorValue { float32={ 0.0, 0.0, flash, 0.0 }}

    clear_range := make_subresource_range({.COLOR})
    vk.CmdClearColorImage(cmd, swapchain.images[image_index], .GENERAL, &clear_color, 1, &clear_range)

    transition_image(cmd, swapchain.images[image_index], .GENERAL, .PRESENT_SRC_KHR)
    
    vk.EndCommandBuffer(cmd)

    cmdinfo := make_command_buffer_submit_info(cmd)
    waitinfo := make_semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)
    signalinfo := make_semaphore_submit_info({.ALL_GRAPHICS}, frame.render_semaphore)
    submitinfo := make_submit_info(&cmdinfo, &signalinfo, &waitinfo)

    vk.QueueSubmit2(queues[.GCT], 1, &submitinfo, frame.render_fence)

    prenfo := vk.PresentInfoKHR {
        sType = .PRESENT_INFO_KHR,
        swapchainCount = 1,
        pSwapchains = &swapchain.handle,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &frame.render_semaphore,
        pImageIndices = &image_index
    }
    vk.QueuePresentKHR(queues[.Present], &prenfo)
    frame_number += 1
}

init_window :: proc(using ctx: ^Context, width, height: u32) {
    glfw.Init();
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, 0)

    window_extent = vk.Extent2D { width = width, height = height }
	window = glfw.CreateWindow(auto_cast width, auto_cast height, "Vulkan", nil, nil)
	glfw.SetWindowUserPointer(window, ctx);
	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)
    glfw.SetKeyCallback(window, key_callback)
    glfw.SetWindowUserPointer(window, auto_cast ctx)
    
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	using ctx := cast(^Context)glfw.GetWindowUserPointer(window)
	framebuffer_resized = true;
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    using ctx := cast(^Context)glfw.GetWindowUserPointer(window)
    if key == glfw.KEY_ESCAPE && action == glfw.RELEASE {
        glfw.SetWindowShouldClose(window, true)
    }
}

init_vulkan :: proc(using ctx: ^Context) {
	context.user_ptr = &instance
	get_proc_address :: proc(p: rawptr, name: cstring) 
	{
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}
	vk.load_proc_addresses(get_proc_address)


    create_instance(ctx)
    create_surface(ctx)
    create_device(ctx)
    create_queues(ctx)
    init_swapchain_details(ctx)
    create_swapchain(ctx)
}

create_instance :: proc(using ctx: ^Context) {
    app_info := vk.ApplicationInfo {
        sType = .APPLICATION_INFO,
        pApplicationName = "Cuber",
        applicationVersion = vk.MAKE_VERSION(0, 1, 0),
        pEngineName = "Cuber Engine",
        engineVersion = vk.MAKE_VERSION(0, 1, 0),
        apiVersion = vk.API_VERSION_1_3,
    }


	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	layers := make([]vk.LayerProperties, layer_count)
	defer delete(layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers))

    outer: for name in VALIDATION_LAYERS {
        for &layer in layers {
            layer_name := cstring(&layer.layerName[0])
            fmt.printfln("layer:", layer_name)
            if name == layer_name do continue outer;
        }
        fmt.eprintf("ERROR: validation layer %q not available\n", name);
        os.exit(1);
    }
    

    extensions := glfw.GetRequiredInstanceExtensions();

    fmt.printfln("--- Loaded Instance Extensions ---")
    for ex in extensions {
        fmt.println("Extension: ", ex)
    }

    debug_callback := proc "c" (
        messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, 
        messageTypes: vk.DebugUtilsMessageTypeFlagsEXT, 
        pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT, 
    pUserData: rawptr) -> b32 {
        context = runtime.default_context()
        fmt.println("Validation layer: ", pCallbackData.pMessage)
        return false
    }

    debug_messenger_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
        sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        messageSeverity = {.WARNING, .ERROR},
        messageType = {.PERFORMANCE, .VALIDATION, .GENERAL},
        pfnUserCallback = debug_callback,
    }
    

    instance_info := vk.InstanceCreateInfo {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = &app_info,
        enabledExtensionCount = auto_cast len(extensions),
        ppEnabledExtensionNames = raw_data(extensions),
        enabledLayerCount = auto_cast len(VALIDATION_LAYERS),
        ppEnabledLayerNames = raw_data(VALIDATION_LAYERS),
        pNext = &debug_messenger_create_info,
    }

    if vk.CreateInstance(&instance_info, nil, &instance) != vk.Result.SUCCESS {
        fmt.eprintfln("ERROR: Failed to create instance");
		return;
    }
}

create_surface :: proc(using ctx: ^Context) {
    glfw.CreateWindowSurface(instance, window, nil, &surface)
}

create_device :: proc(using ctx: ^Context) {
    features12 := vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        bufferDeviceAddress = true,
        descriptorIndexing = true,
        timelineSemaphore = true,
    }
    features13 := vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        pNext = &features12,
        dynamicRendering = true,
        synchronization2 = true,
    }

    pd_count: u32
    vk.EnumeratePhysicalDevices(instance, &pd_count, nil)
    pdevices := make([]vk.PhysicalDevice, pd_count)
    defer delete(pdevices)
    vk.EnumeratePhysicalDevices(instance, &pd_count, raw_data(pdevices))

    pdevice_suitability :: proc(using ctx: ^Context, pdev: vk.PhysicalDevice) -> bool {
        properties: vk.PhysicalDeviceProperties
        features: vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(pdev, &properties)
        vk.GetPhysicalDeviceFeatures(pdev, &features)
        
        features12: vk.PhysicalDeviceVulkan12Features = {
            sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            bufferDeviceAddress = true,
            descriptorIndexing = true,
            timelineSemaphore = true,
        }
        features13: vk.PhysicalDeviceVulkan13Features = {
            sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            dynamicRendering = true,
            synchronization2 = true,
        }
        features2: vk.PhysicalDeviceFeatures2
        features2.sType = .PHYSICAL_DEVICE_FEATURES_2
        features2.pNext = &features13
        features13.pNext = &features12

        vk.GetPhysicalDeviceFeatures2(pdev, &features2)

        if (features13.dynamicRendering && features13.synchronization2 &&
            features12.bufferDeviceAddress && features12.descriptorIndexing) {
            return true
        }

        return false
    }

    found := false
    for pdev in pdevices {
        if pdevice_suitability(ctx, pdev) {
            pdevice = pdev
            found = true
        }
    }
    if !found {
        // TODO handle error
    }

    find_queue_families(ctx)

    queue_priority: f32 = 1.0
    unique_ids: map[int]b8
    defer delete(unique_ids)
    tmp_ids := [2]int{qf_ids[.GCT], qf_ids[.Present]}
    for index in tmp_ids do unique_ids[index] = true 

    queue_infos: [dynamic]vk.DeviceQueueCreateInfo

    for index, _ in unique_ids {
        queue_info := vk.DeviceQueueCreateInfo {
            sType = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = auto_cast index,
            queueCount = 1,
            pQueuePriorities = &queue_priority,
        }
        append(&queue_infos, queue_info)
    }

    features: vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceFeatures(pdevice, &features)

    info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        pNext = &features13,
        pEnabledFeatures = &features,
        enabledExtensionCount = auto_cast len(DEVICE_EXTENSIONS),
        ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
        enabledLayerCount = auto_cast len(VALIDATION_LAYERS),
        ppEnabledLayerNames = raw_data(VALIDATION_LAYERS),
        queueCreateInfoCount = auto_cast len(queue_infos),
        pQueueCreateInfos = &queue_infos[0],
    }

    if vk.CreateDevice(pdevice, &info, nil, &device) != .SUCCESS {
        fmt.eprintfln("ERROR: Failed to create logical device")
        os.exit(1)
    }
}

find_queue_families :: proc(using ctx: ^Context) {
    count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &count, nil);
    families := make([]vk.QueueFamilyProperties, count)
    defer delete(families)
    vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &count, raw_data(families));

    qf_ids = [QueueType]int{
        .GCT = -1,
        .Graphics = -1,
        .Compute = -1,
        .Transfer = -1,
        .Present = -1,
    }

    for fam, idx in families {
        if .TRANSFER in fam.queueFlags && .GRAPHICS in fam.queueFlags && .COMPUTE in fam.queueFlags {
            if qf_ids[.GCT] == -1 {
                qf_ids[.GCT] = idx
            }
        }

        present_support: b32
        vk.GetPhysicalDeviceSurfaceSupportKHR(pdevice, u32(idx), surface, &present_support)
        if present_support && qf_ids[.Present] == -1 {
            qf_ids[.Present] = idx
        }
        if qf_ids[.GCT] != -1 && qf_ids[.Present] != -1 { 
            break 
        }
    }
}

create_queues :: proc(using ctx: ^Context) {
    vk.GetDeviceQueue(device, auto_cast qf_ids[.GCT], 0, &queues[.GCT])
    vk.GetDeviceQueue(device, auto_cast qf_ids[.Present], 0, &queues[.Present])
}

init_swapchain_details :: proc(using ctx: ^Context) {
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(pdevice, surface, &swapchain.capabilities)

    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(pdevice, surface, &format_count, nil)
    if format_count <= 0 {
        // TODO handle error
    }
    swapchain.formats = make([]vk.SurfaceFormatKHR, format_count)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(pdevice, surface, &format_count, raw_data(swapchain.formats))

    present_mode_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(pdevice, surface, &present_mode_count, nil)
    if present_mode_count <= 0 {
        // TODO handle error
    }
    swapchain.present_modes = make([]vk.PresentModeKHR, present_mode_count)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(pdevice, surface, &present_mode_count, raw_data(swapchain.present_modes))
    
}

pick_surface_format :: proc(using ctx: ^Context) -> vk.SurfaceFormatKHR {
    for f in swapchain.formats {
        if f.format == .R8G8B8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR do return f
    }
    return swapchain.formats[0]
}

pick_present_mode :: proc(using ctx: ^Context) -> vk.PresentModeKHR {
    for m in swapchain.present_modes {
        if m == .MAILBOX do return m
    }
    return .FIFO
}

pick_swap_extent :: proc(using ctx: ^Context) -> vk.Extent2D {
    width, height := glfw.GetFramebufferSize(window)
    extent := vk.Extent2D{u32(width), u32(height)}
    extent.width = clamp(extent.width, swapchain.capabilities.minImageExtent.width, swapchain.capabilities.maxImageExtent.width);
    extent.height = clamp(extent.height, swapchain.capabilities.minImageExtent.height, swapchain.capabilities.maxImageExtent.height);
    return extent
}

create_swapchain :: proc(using ctx: ^Context) {
    swapchain.format = pick_surface_format(ctx)
    swapchain.present_mode = pick_present_mode(ctx)
    swapchain.extent = pick_swap_extent(ctx)
    swapchain.image_count = swapchain.capabilities.minImageCount + 1

    if swapchain.capabilities.maxImageCount > 0 && swapchain.image_count > swapchain.capabilities.maxImageCount {
        swapchain.image_count = swapchain.capabilities.maxImageCount
    }

    info: vk.SwapchainCreateInfoKHR
    info.sType = .SWAPCHAIN_CREATE_INFO_KHR
    info.surface = surface
    info.minImageCount = swapchain.image_count
    info.imageFormat = swapchain.format.format
    info.imageColorSpace = swapchain.format.colorSpace
    info.imageExtent = swapchain.extent
    info.imageArrayLayers = 1
    info.imageUsage = {.COLOR_ATTACHMENT,.TRANSFER_DST}
    qf_indices := [2]u32{u32(qf_ids[.GCT]), u32(qf_ids[.Present])};

    if qf_ids[.GCT] != qf_ids[.Present] {
        info.imageSharingMode = .CONCURRENT
        info.queueFamilyIndexCount = 2
        info.pQueueFamilyIndices = &qf_indices[0]
    } else {
        info.imageSharingMode = .EXCLUSIVE
        info.queueFamilyIndexCount = 0
        info.pQueueFamilyIndices = nil
    }

    info.preTransform = swapchain.capabilities.currentTransform
    info.compositeAlpha = {.OPAQUE}
    info.presentMode = swapchain.present_mode
    info.clipped = true
    info.oldSwapchain = swapchain.handle

    if vk.CreateSwapchainKHR(device, &info, nil, &swapchain.handle) != .SUCCESS {
        fmt.eprintfln("Error: failed to create swapchain!")
        os.exit(1)
    }

    vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.image_count, nil)
    swapchain.images = make([]vk.Image, swapchain.image_count)
    vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.image_count, raw_data(swapchain.images))
}

create_image_views :: proc(using ctx: ^Context) {
    using ctx.swapchain
    views = make([]vk.ImageView, len(images))

    for _img, i in images {
        info: vk.ImageViewCreateInfo
        info.sType = .IMAGE_VIEW_CREATE_INFO
        info.image = images[i]
        info.viewType = .D2
        info.format = format.format
        info.components.r = .IDENTITY
        info.components.g = .IDENTITY
        info.components.b = .IDENTITY
        info.components.a = .IDENTITY
        info.subresourceRange.aspectMask = {.COLOR }
        info.subresourceRange.baseMipLevel = 0
        info.subresourceRange.levelCount = 1
        info.subresourceRange.baseArrayLayer = 0
        info.subresourceRange.layerCount = 1

        if vk.CreateImageView(device, &info, nil, &views[i]) != .SUCCESS {
            fmt.eprintfln("Error: failed to create ImageView!")
            os.exit(0)
        }
    }
}

create_commands :: proc(using ctx: ^Context) {
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

create_sync_structures :: proc(using ctx: ^Context) {
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

current_frame :: proc(ctx: ^Context) -> ^FrameData {
    return &ctx.frames[ctx.frame_number % FRAME_OVERLAP]
}

make_subresource_range :: proc(aspect_mask: vk.ImageAspectFlags) -> vk.ImageSubresourceRange {
    subresource_range := vk.ImageSubresourceRange {
        aspectMask = aspect_mask,
        baseMipLevel = 0,
        levelCount = vk.REMAINING_MIP_LEVELS,
        baseArrayLayer = 0,
        layerCount = vk.REMAINING_ARRAY_LAYERS,
    }
    return subresource_range
}

transition_image :: proc(cmd: vk.CommandBuffer, image: vk.Image, oldLayout: vk.ImageLayout, newLayout: vk.ImageLayout) {
    barrier := vk.ImageMemoryBarrier2 {
        sType = .IMAGE_MEMORY_BARRIER_2,
        srcStageMask = {.ALL_COMMANDS},
        srcAccessMask = {.MEMORY_WRITE},
        dstStageMask = {.ALL_COMMANDS},
        dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ},
        oldLayout = oldLayout,
        newLayout = newLayout,
        subresourceRange = make_subresource_range(newLayout == .DEPTH_ATTACHMENT_OPTIMAL ? {.DEPTH } : {.COLOR}),
        image = image,
    }

    dependency_info := vk.DependencyInfo {
        sType = .DEPENDENCY_INFO,
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = &barrier,
    }

    vk.CmdPipelineBarrier2(cmd, &dependency_info)
}

make_semaphore_submit_info :: proc(stage_mask: vk.PipelineStageFlags2, sempaphore: vk.Semaphore) -> vk.SemaphoreSubmitInfo {
    info := vk.SemaphoreSubmitInfo {
        sType = .SEMAPHORE_SUBMIT_INFO,
        semaphore = sempaphore,
        stageMask = stage_mask,
        deviceIndex = 0,
        value = 1
    }
    return info
}

make_command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
    info := vk.CommandBufferSubmitInfo {
        sType = .COMMAND_BUFFER_SUBMIT_INFO,
        commandBuffer = cmd,
        deviceMask = 0,
    }
    return info
}

make_submit_info :: proc(cmd: ^vk.CommandBufferSubmitInfo, ssinfo, wsinfo: ^vk.SemaphoreSubmitInfo) -> vk.SubmitInfo2 {
    info := vk.SubmitInfo2 {
        sType = .SUBMIT_INFO_2,
        commandBufferInfoCount = 1,
        pCommandBufferInfos = cmd,
        signalSemaphoreInfoCount = ssinfo == nil ? 0 : 1,
        pSignalSemaphoreInfos = ssinfo,
        waitSemaphoreInfoCount = wsinfo == nil ? 0 : 1,
        pWaitSemaphoreInfos = wsinfo,
    }
    return info
}