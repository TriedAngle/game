package cvk
import vk "vendor:vulkan"
import "core:math"

render :: proc(using vctx: ^VulkanContext) {
    frame := current_frame(vctx)
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