package cvk

import "core:os"
import "core:fmt"
import "core:slice"

import vk "vendor:vulkan"

load_shader_module :: proc(device: vk.Device, path: string) -> (module: vk.ShaderModule) {
    raw, success := os.read_entire_file(path)
    defer delete(raw)

    if !success {
        fmt.eprintln("Error: File :\"", path, "\" not found")
        os.exit(1)
    }

    data := slice.reinterpret([]u32, raw)

    info := vk.ShaderModuleCreateInfo {
        sType = .SHADER_MODULE_CREATE_INFO,
        pNext = nil,
        flags = {},
        codeSize = len(raw), // lol, vulkan wants size in bytes
        pCode = raw_data(data),
    }

    if vk.CreateShaderModule(device, &info, nil, &module) != .SUCCESS {
        fmt.eprintln("Error: Creating Shadermodule")
        os.exit(1)
    }

    return
}

create_pipelines :: proc(using vctx: ^VulkanContext) {
    create_background_pipelines(vctx, size_of(ComputePushConstants))
}

create_background_pipelines :: proc(using vctx: ^VulkanContext, push_constant_size: Maybe(u32)) {
    pucor := vk.PushConstantRange {
        offset = 0,
        size = push_constant_size.? or_else 0,
        stageFlags = {.COMPUTE},
    }

    linfo := vk.PipelineLayoutCreateInfo {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        pNext = nil,
        setLayoutCount = 1,
        pSetLayouts = &draw_descriptor_layout,
        pPushConstantRanges = &pucor,
        pushConstantRangeCount = push_constant_size == nil ? 0 : 1,
    }

    if vk.CreatePipelineLayout(device, &linfo, nil, &gradient_pipeline_layout) != .SUCCESS {
        fmt.eprintln("Error: Creating Pipeline Layout")
        os.exit(1)
    }

    shader_module := load_shader_module(vctx.device, "assets/gradient_color.comp.spv")
    defer vk.DestroyShaderModule(device, shader_module, nil)

    sinfo := vk.PipelineShaderStageCreateInfo {
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        pNext = nil,
        stage = {.COMPUTE},
        module = shader_module,
        pName = "main",
        flags = {},
    }

    cinfo := vk.ComputePipelineCreateInfo {
        sType = .COMPUTE_PIPELINE_CREATE_INFO,
        pNext = nil,
        layout = gradient_pipeline_layout,
        stage = sinfo,
    }

    if vk.CreateComputePipelines(device, 0, 1, &cinfo, nil, &gradient_pipeline) != .SUCCESS {
        fmt.eprintln("Error: Creating Pipeline Layout")
        os.exit(1)
    }

}