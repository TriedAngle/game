package cvk
import vk "vendor:vulkan"
import "core:math"

render_background :: proc(using vctx: ^VulkanContext, cmd: vk.CommandBuffer, frame: ^FrameData) {
    flash: f32 = math.abs(math.sin(f32(frame_number) / 120.0)) 
    clear_color := vk.ClearColorValue { float32={ 0.0, 0.0, flash, 0.0 }}

    clear_range := make_subresource_range({.COLOR})
    vk.CmdClearColorImage(cmd, swapchain.draw.image, .GENERAL, &clear_color, 1, &clear_range)
}


render_prepare :: proc(using vctx: ^VulkanContext) -> (frame: ^FrameData, cmd: vk.CommandBuffer, img_idx: u32) {
    frame = current_frame(vctx)
    vk.WaitForFences(device, 1, &frame.render_fence, true, 1000000000)
    flush(&frame.lambdas, vctx)
    vk.ResetFences(device, 1, &frame.render_fence)
    
    vk.AcquireNextImageKHR(device, swapchain.handle, 1000000000, frame.swapchain_semaphore, {}, &img_idx)

    draw := swapchain.draw
    swapchain.draw_extent.width = draw.extent.width
    swapchain.draw_extent.height = draw.extent.height

    cmd = frame.cmdbuffer
    vk.ResetCommandBuffer(cmd, {})

    binfo := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }

    vk.BeginCommandBuffer(cmd, &binfo)

    transition_image(cmd, draw.image, .UNDEFINED, .GENERAL)
    return
}

render_finalize :: proc(using vctx: ^VulkanContext, cmd: vk.CommandBuffer, frame: ^FrameData, img_idx: u32) {
    draw := swapchain.draw
    imdx := img_idx
    transition_image(cmd, draw.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
    transition_image(cmd, swapchain.images[imdx], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

    copy_simple_image_to_image(cmd, draw.image, swapchain.images[imdx], swapchain.draw_extent, swapchain.extent)

    transition_image(cmd, swapchain.images[imdx], .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR)
    
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
        pImageIndices = &imdx,
    }
    vk.QueuePresentKHR(queues[.Present], &prenfo)
    frame_number += 1
}