package cvk

import "core:os"
import "core:fmt"

import vk "vendor:vulkan"

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
    swapchain.format = pick_surface_format(vctx)
    swapchain.present_mode = pick_present_mode(vctx)
    swapchain.extent = pick_swap_extent(vctx, width, height)
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

create_image_views :: proc(using vctx: ^VulkanContext) {
    using vctx.swapchain
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