package cvk

import "core:os"
import "core:fmt"

import vk "vendor:vulkan"

DescriptorLayoutBuilder :: struct {
    bindings: [dynamic]vk.DescriptorSetLayoutBinding,
}

PoolSizeRatio :: struct {
    type: vk.DescriptorType,
    ratio: f32,        
}

DescriptorAllocator :: struct {
    pool: vk.DescriptorPool,
}


add_binding :: proc(dlb: ^DescriptorLayoutBuilder, binding: u32, type: vk.DescriptorType, count: u32 = 1, flags: vk.ShaderStageFlags = {}) {
    new := vk.DescriptorSetLayoutBinding {
        binding = binding,
        descriptorCount = count,
        descriptorType = type,
        stageFlags = flags,
    }
    append(&dlb.bindings, new)
}

clear_bindings :: proc(dlb: ^DescriptorLayoutBuilder) {
    clear(&dlb.bindings)
}

build_descriptor_set :: proc(using dlb: ^DescriptorLayoutBuilder, device: vk.Device, shader_stages: vk.ShaderStageFlags, flags: vk.DescriptorSetLayoutCreateFlags = {}, next: rawptr = nil) -> vk.DescriptorSetLayout {
    for &binding in bindings {
        binding.stageFlags |= shader_stages
    }

    info := vk.DescriptorSetLayoutCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        pNext = next,
        bindingCount = auto_cast len(bindings),
        pBindings = raw_data(bindings),
        flags = flags
    }

    set: vk.DescriptorSetLayout
    vk.CreateDescriptorSetLayout(device, &info, nil, &set)
    return set
}

init_descriptor_pool :: proc(da: ^DescriptorAllocator, device: vk.Device, max_sets: u32, ratios: []PoolSizeRatio, flags: vk.DescriptorPoolCreateFlags = {}) {
    sizes := make([]vk.DescriptorPoolSize, len(ratios))
    defer delete(sizes)
    for ratio, idx in ratios {
        sizes[idx] = vk.DescriptorPoolSize {
            type = ratio.type,
            descriptorCount = auto_cast ratio.ratio * max_sets
        }
    }
    info := vk.DescriptorPoolCreateInfo {
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        pNext = nil,
        flags = flags,
        maxSets = max_sets,
        poolSizeCount = auto_cast len(sizes),
        pPoolSizes = raw_data(sizes),
    }
    vk.CreateDescriptorPool(device, &info, nil, &da.pool)
}

clear_descriptors :: proc(da: ^DescriptorAllocator, device: vk.Device) {
    vk.ResetDescriptorPool(device, da.pool, {})
}

deinit_descriptor_allocator :: proc(da: ^DescriptorAllocator, device: vk.Device) {
    vk.DestroyDescriptorPool(device, da.pool, nil)
}

allocate_descriptor_set :: proc(da: ^DescriptorAllocator, device: vk.Device, layout: ^vk.DescriptorSetLayout) -> vk.DescriptorSet {
    info := vk.DescriptorSetAllocateInfo {
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = da.pool,
        descriptorSetCount = 1,
        pSetLayouts = layout,
    }
    set: vk.DescriptorSet
    vk.AllocateDescriptorSets(device, &info, &set)
    return set
}