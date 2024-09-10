package world

import "core:testing"
import "core:fmt"

Brick :: struct {
    data: [8]u64 // each 
}

brick_get :: proc(b: ^Brick, x, y, z: u8) -> bool {
    slice := b.data[z]
    index := x + (y * 8)
    value := slice & (1 << index) != 0
    return value
}

brick_set :: proc(b: ^Brick, x, y, z: u8, value: bool) {
    index := x + (y * 8)

    if value {
        b.data[z] |= (1 << index)
    } else {
        b.data[z] &= ~(1 << index)
    } 
}

BrickGrid :: struct {
    x1, y1, z1: u64,
    x2, y2, z2: u64,
    grid: []Brick
}

grid_get :: proc(b: ^BrickGrid, x, y, z: u64) -> ^Brick {
    index := x + (y * b.x2) + (z * b.x2 * b.y2)
    brick := &b.grid[index]
    return brick
}

grid_set :: proc(b: ^BrickGrid, x, y, z: u64, brick: ^Brick) {
    index := x + (y * b.x2) + (z * b.x2 * b.y2)
    b.grid[index] = brick^
}


@(test)
test_bm :: proc(t: ^testing.T) {
    bm: Brick

    brick_set(&bm, 0, 4, 5, true)
    value := brick_get(&bm, 0, 4, 5)

    testing.expect(t, value == true)
}