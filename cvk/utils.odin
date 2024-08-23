package cvk

import vk "vendor:vulkan"

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

current_frame :: proc(vctx: ^VulkanContext) -> ^FrameData {
    return &vctx.frames[vctx.frame_number % FRAME_OVERLAP]
}