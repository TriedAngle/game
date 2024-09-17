package cvk

import "core:fmt"
import la "core:math/linalg"

import vk "vendor:vulkan"
import vma "../vma"


Vertex :: struct {
    position, normal, color: la.Vector3f32
}

GPUMeshBuffer :: struct {
    index: Buffer,
    vertex: Buffer,
    address: vk.DeviceAddress,
}

GPUPushConstants :: struct {
    world: la.Matrix4x4f32,
    vertex: vk.DeviceAddress,
}

upload_mesh :: proc(using vctx: ^VulkanContext, indices: []u32, verticies: []Vertex) -> GPUMeshBuffer {
    size_vertex: u64 = auto_cast len(verticies) * size_of(Vertex)
    size_index: u64 = auto_cast len(indices) * size_of(u32)

    mesh: GPUMeshBuffer

    mesh.vertex = create_buffer(
        vmalloc,
        size_vertex, 
        {.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
        .GPU_ONLY
    )

    adinfo := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        pNext = nil,
        buffer = mesh.vertex.buffer // should be 0 ??
    }
    
    mesh.address = vk.GetBufferDeviceAddress(device, &adinfo)
    
    mesh.index = create_buffer(
        vmalloc,
        size_index,
        {.INDEX_BUFFER, .TRANSFER_DST},
        .GPU_ONLY
    )

    staging := create_buffer(vmalloc, size_vertex + size_index, {.TRANSFER_DST}, .CPU_ONLY)
    data_ptr: rawptr
    vma.MapMemory(vmalloc,staging.allocation, &data_ptr)

    SubmitInfo :: struct {
        size_vertex: u64,
        size_index: u64,
    }

    submit := submit_info {
        size_vertex = size_vertex,
        size_index = size_index,
    }

    immidiate_submit(vctx, &submit, proc(vctx: ^VulkanContext, cmd: vk.CommandBuffer, other: rawptr) {
        submit := cast(^SubmitInfo) other
        vertex_copy := vk.BufferCopy {
            size = submit.
        }
    })


    return mesh
}