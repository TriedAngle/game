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
    create_raster_pipeline(vctx)
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

    shader_module := load_shader_module(device, "assets/gradient_color.comp.spv")
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

create_raster_pipeline :: proc(using vctx: ^VulkanContext) {
    vertex_module := load_shader_module(device, "assets/colored_triangle.vert.spv")
    defer vk.DestroyShaderModule(device, vertex_module, nil)
    fragment_module := load_shader_module(device, "assets/colored_triangle.frag.spv")
    defer vk.DestroyShaderModule(device, fragment_module, nil)

    linfo := make_pipeline_layout_info()
    vk.CreatePipelineLayout(device, &linfo, nil, &traingle_pipeline_layout)

    pb: PipelineBuilder
    pb_init(&pb)
    pb.layout = traingle_pipeline_layout
    pb_set_shaders(&pb, vertex_module, fragment_module)
    pb_set_input_topology(&pb, .TRIANGLE_LIST)
    pb_set_cull_mode(&pb, {}, .CLOCKWISE)
    pb_set_multisampling_none(&pb)
    pb_disable_blending(&pb)
    pb_disable_depthtest(&pb)

    pb_set_color_attachment_format(&pb, swapchain.draw.format)
    pb_set_depth_format(&pb, .UNDEFINED)

    triangle_pipeline = pb_build(&pb, device)
}

PipelineBuilder :: struct {
    shader_stages: [dynamic]vk.PipelineShaderStageCreateInfo,
    input_assembly: vk.PipelineInputAssemblyStateCreateInfo,
    rasterizer: vk.PipelineRasterizationStateCreateInfo,
    color_blend_attachment: vk.PipelineColorBlendAttachmentState,
    multisampling: vk.PipelineMultisampleStateCreateInfo,
    layout: vk.PipelineLayout,
    depth_stencil: vk.PipelineDepthStencilStateCreateInfo,
    rendering: vk.PipelineRenderingCreateInfo,
    color_format: vk.Format,
}

pb_init :: proc(using pb: ^PipelineBuilder) {
    pb_clear(pb)
}

pb_clear :: proc(using pb: ^PipelineBuilder) {
    input_assembly = { sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO }
    rasterizer = { sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO }
    multisampling = { sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO }
    depth_stencil = { sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO }
    rendering = { sType = .PIPELINE_RENDERING_CREATE_INFO } 
    clear(&shader_stages)
}

pb_build :: proc(using pb: ^PipelineBuilder, device: vk.Device) -> vk.Pipeline {
    vpinfo := vk.PipelineViewportStateCreateInfo {
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        pNext = nil,
        viewportCount = 1,
        scissorCount = 1,
    }

    cbinfi := vk.PipelineColorBlendStateCreateInfo {
        sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        pNext = nil,
        logicOpEnable = false,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = &color_blend_attachment,
    }

    pvisinfo := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        pNext = nil,
    }

    dynamics := []vk.DynamicState{ .VIEWPORT, .SCISSOR }

    dsinfo := vk.PipelineDynamicStateCreateInfo {
        sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        pNext = nil,
        dynamicStateCount = auto_cast len(dynamics),
        pDynamicStates = raw_data(dynamics),
    }

    gpinfo := vk.GraphicsPipelineCreateInfo {
        sType = .GRAPHICS_PIPELINE_CREATE_INFO,
        pNext = &rendering,
        stageCount = auto_cast len(shader_stages),
        pStages = raw_data(shader_stages),
        pVertexInputState = &pvisinfo,
        pInputAssemblyState = &input_assembly,
        pViewportState = &vpinfo,
        pRasterizationState = &rasterizer,
        pMultisampleState = &multisampling,
        pColorBlendState = &cbinfi,
        pDepthStencilState = &depth_stencil,
        pDynamicState = &dsinfo,
        layout = layout,
    }

    pipeline: vk.Pipeline
    
    if vk.CreateGraphicsPipelines(device, {}, 1, &gpinfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintfln("Error: Failed to create Pipeline")
        os.exit(1)
    }

    return pipeline
}

pb_set_shaders :: proc(using pb: ^PipelineBuilder, vertex, fragment: vk.ShaderModule) {
    clear(&shader_stages)

    vertex_stage := make_shader_stage_info(vertex, {.VERTEX})
    fragment_stage := make_shader_stage_info(fragment, {.FRAGMENT})

    append(&shader_stages, vertex_stage)
    append(&shader_stages, fragment_stage)
}

pb_set_input_topology :: proc(using pb: ^PipelineBuilder, topology: vk.PrimitiveTopology) {
    input_assembly.topology = topology
    input_assembly.primitiveRestartEnable = false
}

pb_set_polygon_mode :: proc(using pb: ^PipelineBuilder, mode: vk.PolygonMode, line_wdith: f32 = 1) {
    rasterizer.polygonMode = mode
    rasterizer.lineWidth = line_wdith
}

pb_set_cull_mode :: proc(using pb: ^PipelineBuilder, cull: vk.CullModeFlags, face: vk.FrontFace) {
    rasterizer.cullMode = cull
    rasterizer.frontFace = face
}

pb_set_multisampling_none :: proc(using pb: ^PipelineBuilder) {
    multisampling.sampleShadingEnable = false
    multisampling.rasterizationSamples = {._1}
    multisampling.pSampleMask = nil
    multisampling.alphaToCoverageEnable = false
    multisampling.alphaToOneEnable = false
}

pb_set_color_attachment_format :: proc(using pb: ^PipelineBuilder, format: vk.Format) {
    color_format = format
    rendering.colorAttachmentCount = 1
    rendering.pColorAttachmentFormats = &color_format // this looks sus ? what if move
}

pb_disable_blending :: proc(using pb: ^PipelineBuilder) {
    color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
    color_blend_attachment.blendEnable = false
}

pb_set_depth_format :: proc(using pb: ^PipelineBuilder, format: vk.Format) {
    rendering.depthAttachmentFormat = format
}

pb_disable_depthtest :: proc(using pb: ^PipelineBuilder) {
    ds := &pb.depth_stencil
    ds.depthTestEnable = false
    ds.depthWriteEnable = false
    ds.depthCompareOp = .NEVER
    ds.stencilTestEnable = false
    ds.front = {}
    ds.back = {}
    ds.minDepthBounds = 0
    ds.maxDepthBounds = 1
}
