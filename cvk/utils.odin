package cvk

import vk "vendor:vulkan"

current_frame :: proc(vctx: ^VulkanContext) -> ^FrameData {
    return &vctx.frames[vctx.frame_number % FRAME_OVERLAP]
}

make_subresource_range :: proc(
    aspect: vk.ImageAspectFlags, 
    base_mip: u32 = 0, mip_levels: u32 = vk.REMAINING_MIP_LEVELS,
    base_array: u32 = 0, array_layers: u32 = vk.REMAINING_ARRAY_LAYERS,
) -> vk.ImageSubresourceRange {
    subresource_range := vk.ImageSubresourceRange {
        aspectMask = aspect,
        baseMipLevel = base_mip,
        levelCount = mip_levels,
        baseArrayLayer = base_array,
        layerCount = array_layers,
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

make_image_info :: proc(
    format: vk.Format, usage: vk.ImageUsageFlags, extent: vk.Extent3D, 
    dimension: vk.ImageType = .D2, mip_levels: u32 = 1, array_layers: u32 = 1,
    samples: vk.SampleCountFlags = {._1}, tiling: vk.ImageTiling = .OPTIMAL,
) -> vk.ImageCreateInfo {
    info := vk.ImageCreateInfo {
        sType = .IMAGE_CREATE_INFO,
        pNext = nil,
        imageType = dimension,
        format = format,
        extent = extent,
        mipLevels = mip_levels,
        arrayLayers = array_layers,
        samples = samples,
        tiling = tiling,
        usage = usage,
    }
    return info
}

make_image_view_info :: proc(
    format: vk.Format, image: vk.Image, aspect: vk.ImageAspectFlags,
    dimension: vk.ImageViewType = .D2,
) -> vk.ImageViewCreateInfo {
    sr_range := make_subresource_range(aspect, mip_levels=1, array_layers=1)

    info := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        pNext = nil,
        viewType = dimension,
        format = format,
        image = image,
        subresourceRange = sr_range,
    }
    return info
}

copy_simple_image_to_image :: proc(cmd: vk.CommandBuffer, src_image, dst_image: vk.Image, src, dst: vk.Extent2D) {
    blit := vk.ImageBlit2 {
        sType = .IMAGE_BLIT_2,
        pNext = nil
    }

    blit.srcOffsets[1] = {auto_cast src.width, auto_cast src.height, 1}
    blit.dstOffsets[1] = {auto_cast dst.width, auto_cast dst.height, 1}

    blit.srcSubresource = vk.ImageSubresourceLayers {
        aspectMask = {.COLOR},
        baseArrayLayer = 0,
        layerCount = 1,
        mipLevel = 0,
    }

    blit.dstSubresource = vk.ImageSubresourceLayers {
        aspectMask = {.COLOR},
        baseArrayLayer = 0,
        layerCount = 1,
        mipLevel = 0,
    }

    info := vk.BlitImageInfo2 {
        sType = .BLIT_IMAGE_INFO_2,
        pNext = nil,
        srcImage = src_image,
        srcImageLayout = .TRANSFER_SRC_OPTIMAL,
        dstImage = dst_image,
        dstImageLayout = .TRANSFER_DST_OPTIMAL,
        filter = .LINEAR,
        regionCount = 1,
        pRegions = &blit
    }

    vk.CmdBlitImage2(cmd, &info)
}

make_rendering_info :: proc(extent: vk.Extent2D, color, depth: ^vk.RenderingAttachmentInfo,stencil: ^vk.RenderingAttachmentInfo = nil) -> vk.RenderingInfo {
    info := vk.RenderingInfo {
        sType = .RENDERING_INFO,
        pNext = nil,
        renderArea = vk.Rect2D{{0, 0}, extent},
        layerCount = 1,
        colorAttachmentCount = 1,
        pColorAttachments = color,
        pDepthAttachment = depth,
        pStencilAttachment = stencil
    }

    return info
}

make_attachment_info :: proc(view: vk.ImageView, clear: Maybe(vk.ClearValue), layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL) -> vk.RenderingAttachmentInfo {
    clear_value, has_clear := clear.?
    info := vk.RenderingAttachmentInfo {
        sType = .RENDERING_ATTACHMENT_INFO,
        pNext = nil,
        imageView = view,
        imageLayout = layout,
        loadOp = has_clear ? .CLEAR : .LOAD,
        storeOp = .STORE,
        clearValue = clear.? or_else vk.ClearValue{},
    }

    return info
}