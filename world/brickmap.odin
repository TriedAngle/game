package world

import "core:testing"
import "core:fmt"

BrickMap :: struct {
    data: [8]u64 // each 
}

brickmap_get :: proc(bm: ^BrickMap, x, y, z: u8) -> bool {
    slice := bm.data[z]
    index := x + (y * 8)
    value := slice & (1 << index) != 0
    return value
}

brickmap_set :: proc(bm: ^BrickMap, x, y, z: u8, value: bool) {
    index := x + (y * 8)

    if value {
        bm.data[z] |= (1 << index)
    } else {
        bm.data[z] &= ~(1 << index)
    } 
}


@(test)
test_bm :: proc(t: ^testing.T) {
    bm: BrickMap

    brickmap_set(&bm, 0, 4, 5, true)
    value := brickmap_get(&bm, 0, 4, 5)

    testing.expect(t, value == true)
}