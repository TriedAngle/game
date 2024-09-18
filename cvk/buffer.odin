package cvk

import "core:fmt"

import vk "vendor:vulkan"
import vma "../vma"

Buffer :: struct {
    buffer: vk.Buffer,
    allocation: vma.Allocation,
    info: vma.AllocationInfo,
}

create_buffer :: proc(
    allocator: vma.Allocator,
    size: u64, usage: vk.BufferUsageFlags, memory_usage: vma.MemoryUsage,
    flags: vk.BufferCreateFlags = {}, sharing: vk.SharingMode = .EXCLUSIVE,
) -> Buffer {
    binfo := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        pNext = nil,
        size = auto_cast size,
        usage = usage,
        flags = flags,
        sharingMode = sharing
    }

    vmainfo := vma.AllocationCreateInfo {
        usage = memory_usage,
        flags = {.MAPPED},
    }

    buffer: Buffer

    vma.CreateBuffer(allocator, &binfo, &vmainfo, &buffer.buffer, &buffer.allocation, &buffer.info)
    
    return buffer
}

destroy_buffer :: proc(allocator: vma.Allocator, using buf: ^Buffer) {
    vma.DestroyBuffer(allocator, buffer, allocation)
}