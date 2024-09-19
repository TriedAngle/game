package cvk

import "core:fmt"
import "core:mem"
import la "core:math/linalg"

import vk "vendor:vulkan"
import vma "../vma"


Vertex :: struct {
    position: la.Vector3f32,
    pad0: f32, 
    normal: la.Vector3f32,
    pad1: f32, 
    color: la.Vector4f32
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

MeshSurface :: struct {
    start, count: u32,
}

Mesh :: struct {
    name: string,
    surfaces: [dynamic]MeshSurface,
    buffer: GPUMeshBuffer,
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
        buffer = mesh.vertex.buffer
    }
    
    mesh.address = vk.GetBufferDeviceAddress(device, &adinfo)
    
    mesh.index = create_buffer(
        vmalloc,
        size_index,
        {.INDEX_BUFFER, .TRANSFER_DST},
        .GPU_ONLY
    )

    staging := create_buffer(vmalloc, size_vertex + size_index, {.TRANSFER_SRC}, .CPU_ONLY)
    defer vma.DestroyBuffer(vmalloc, staging.buffer, staging.allocation)

    staging_ptr: rawptr
    vma.MapMemory(vmalloc, staging.allocation, &staging_ptr)

    // defer vma.UnmapMemory(vmalloc, staging.allocation)
    
    mem.copy(staging_ptr, raw_data(verticies), auto_cast size_vertex)
    mem.copy(auto_cast (uintptr(staging_ptr) + auto_cast size_vertex), raw_data(indices), auto_cast size_index)

    SubmitInfo :: struct {
        size_vertex: u64,
        size_index: u64, 
        staging: ^Buffer,
        mesh: ^GPUMeshBuffer
    }

    submit := SubmitInfo {
        size_vertex = size_vertex,
        size_index = size_index,
        staging = &staging,
        mesh = &mesh,
    }

    immidiate_submit(vctx, &submit, proc(vctx: ^VulkanContext, cmd: vk.CommandBuffer, other: rawptr) {
        using submit := cast(^SubmitInfo) other
        
        vertex_copy := vk.BufferCopy {
            size = auto_cast size_vertex,
            dstOffset = 0,
            srcOffset = 0,
        }

        vk.CmdCopyBuffer(cmd, staging.buffer, mesh.vertex.buffer, 1, &vertex_copy)
        
        index_copy := vk.BufferCopy {
            size = auto_cast size_index,
            dstOffset = 0,
            srcOffset = auto_cast size_vertex,
        }
        
        vk.CmdCopyBuffer(cmd, staging.buffer, mesh.index.buffer, 1, &index_copy)
    })
    
    
    return mesh
}