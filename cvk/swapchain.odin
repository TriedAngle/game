package cvk

import "core:os"
import "core:fmt"

import vk "vendor:vulkan"

import vma "../vma"

query_swapchain_details :: proc(using vctx: ^VulkanContext) {
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

pick_surface_format :: proc(using vctx: ^VulkanContext) -> vk.SurfaceFormatKHR {
    for f in swapchain.formats {
        if f.format == .R8G8B8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR do return f
    }
    return swapchain.formats[0]
}

pick_present_mode :: proc(using vctx: ^VulkanContext) -> vk.PresentModeKHR {
    for m in swapchain.present_modes {
        if m == .MAILBOX do return m
    }
    return .FIFO
}

pick_swap_extent :: proc(using vctx: ^VulkanContext, width, height: u32) -> vk.Extent2D {
    extent := vk.Extent2D{width, height}
    extent.width = clamp(extent.width, swapchain.capabilities.minImageExtent.width, swapchain.capabilities.maxImageExtent.width);
    extent.height = clamp(extent.height, swapchain.capabilities.minImageExtent.height, swapchain.capabilities.maxImageExtent.height);
    return extent
}

create_swapchain :: proc(using vctx: ^VulkanContext, width, height: u32) {
    sc := &swapchain

    sc.format = pick_surface_format(vctx)
    sc.present_mode = pick_present_mode(vctx)
    sc.extent = pick_swap_extent(vctx, width, height)
    sc.image_count = swapchain.capabilities.minImageCount + 1

    if sc.capabilities.maxImageCount > 0 && sc.image_count > sc.capabilities.maxImageCount {
        sc.image_count = sc.capabilities.maxImageCount
    }

    info: vk.SwapchainCreateInfoKHR
    info.sType = .SWAPCHAIN_CREATE_INFO_KHR
    info.surface = surface
    info.minImageCount = sc.image_count
    info.imageFormat = sc.format.format
    info.imageColorSpace = sc.format.colorSpace
    info.imageExtent = sc.extent
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

    info.preTransform = sc.capabilities.currentTransform
    info.compositeAlpha = {.OPAQUE}
    info.presentMode = sc.present_mode
    info.clipped = true
    info.oldSwapchain = sc.handle

    if vk.CreateSwapchainKHR(device, &info, nil, &sc.handle) != .SUCCESS {
        fmt.eprintfln("Error: failed to create swapchain!")
        os.exit(1)
    }

    vk.GetSwapchainImagesKHR(device, sc.handle, &sc.image_count, nil)
    sc.images = make([]vk.Image, swapchain.image_count)
    vk.GetSwapchainImagesKHR(device, sc.handle, &sc.image_count, raw_data(swapchain.images))

    sc.views = make([]vk.ImageView, len(sc.images))

    for _img, i in sc.images {
        info := make_image_view_info(sc.format.format, sc.images[i], {.COLOR})

        if vk.CreateImageView(device, &info, nil, &sc.views[i]) != .SUCCESS {
            fmt.eprintfln("Error: failed to create ImageView!")
            os.exit(1)
        }
    }

    sc.draw.extent = vk.Extent3D {
        width = width,
        height = height,
        depth = 1,
    }
    sc.draw.format = .R16G16B16A16_SFLOAT
    
    draw_img_info := make_image_info(sc.draw.format, {.TRANSFER_SRC, .TRANSFER_DST, .STORAGE, .COLOR_ATTACHMENT}, sc.draw.extent)
    draw_img_alloc_info := vma.AllocationCreateInfo {
        usage = .GPU_ONLY,
        requiredFlags = {.DEVICE_LOCAL},
    }
    
    if vma.CreateImage(vmalloc, &draw_img_info, &draw_img_alloc_info, &sc.draw.image, &sc.draw.allocation, nil) != .SUCCESS {
        fmt.eprintfln("Error: failed to allocate Draw Image")
        os.exit(1)
    }

    draw_img_view_info := make_image_view_info(sc.draw.format, sc.draw.image, {.COLOR})

    if vk.CreateImageView(device, &draw_img_view_info, nil, &sc.draw.view) != .SUCCESS {
        fmt.eprintfln("Error: failed to allocate Draw Image View")
        os.exit(1)
    }

}
