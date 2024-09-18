package cvk
import vk "vendor:vulkan"
import "core:math"
import la "core:math/linalg"

render_background :: proc(using vctx: ^VulkanContext, cmd: vk.CommandBuffer, frame: ^FrameData) {
    // flash: f32 = math.abs(math.sin(f32(frame_number) / 120.0)) 
    // clear_color := vk.ClearColorValue { float32={ 0.0, 0.0, flash, 0.0 }}

    // clear_range := make_subresource_range({.COLOR})
    // vk.CmdClearColorImage(cmd, swapchain.draw.image, .GENERAL, &clear_color, 1, &clear_range)

    vk.CmdBindPipeline(cmd, .COMPUTE, gradient_pipeline)
    vk.CmdBindDescriptorSets(cmd, .COMPUTE, gradient_pipeline_layout, 0, 1, &draw_descriptor, 0, nil)
    
    pc := ComputePushConstants{
        data0 = {1, 0, 0, 1},
        data1 = {0, 0, 1, 1},
    }

    vk.CmdPushConstants(cmd, gradient_pipeline_layout, {.COMPUTE}, 0, size_of(ComputePushConstants), &pc)
    
    vk.CmdDispatch(cmd, u32(math.ceil(f32(swapchain.draw_extent.width) / 16.0)), u32(math.ceil(f32(swapchain.draw_extent.height) / 16.0)), 1)
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
    render_imgui_prepare(vctx)
    return
}

render_finalize :: proc(using vctx: ^VulkanContext, cmd: vk.CommandBuffer, frame: ^FrameData, img_idx: u32) {
    draw := swapchain.draw 
    imdx := img_idx
    transition_image(cmd, draw.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
    transition_image(cmd, swapchain.images[imdx], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

    copy_simple_image_to_image(cmd, draw.image, swapchain.images[imdx], swapchain.draw_extent, swapchain.extent)

    transition_image(cmd, swapchain.images[imdx], .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL)

    render_imgui_finalize(vctx, cmd, swapchain.views[imdx])

    transition_image(cmd, swapchain.images[imdx], .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR)
    
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

render_geometry :: proc(using vctx: ^VulkanContext, cmd: vk.CommandBuffer,  frame: ^FrameData) {
    draw := swapchain.draw 

    transition_image(cmd, draw.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)

    color_attachment := make_attachment_info(draw.view, nil, .COLOR_ATTACHMENT_OPTIMAL)

    draw_extent2d := vk.Extent2D {draw.extent.width, draw.extent.height}
    rinfo := make_rendering_info(draw_extent2d, &color_attachment, nil)
    vk.CmdBeginRendering(cmd, &rinfo)
    vk.CmdBindPipeline(cmd, .GRAPHICS, triangle_pipeline)

    viewport := vk.Viewport {
        x = 0,
        y = 0,
        width = auto_cast draw_extent2d.width,
        height = auto_cast draw_extent2d.height,
        minDepth = 0,
        maxDepth = 1,
    }

    vk.CmdSetViewport(cmd, 0, 1, &viewport)

    scissor := vk.Rect2D {
        offset = {0, 0},
        extent = draw_extent2d,
    }

    vk.CmdSetScissor(cmd, 0, 1, &scissor)

    vk.CmdDraw(cmd, 3, 1, 0, 0)

    vk.CmdBindPipeline(cmd, .GRAPHICS, mesh_pipeline)
    world := la.MATRIX4F32_IDENTITY
    push_constants := GPUPushConstants {
        world = world,
        vertex = rectangle.address,
    }

    vk.CmdPushConstants(cmd, mesh_pipeline_layout, {.VERTEX}, 0, size_of(GPUPushConstants), &push_constants)
    vk.CmdBindIndexBuffer(cmd, rectangle.index.buffer, 0, .UINT32)
    vk.CmdDrawIndexed(cmd, 6, 1, 0, 0, 0)

    vk.CmdEndRendering(cmd)

    transition_image(cmd, draw.image, .COLOR_ATTACHMENT_OPTIMAL, .GENERAL)
}