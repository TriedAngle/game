package world

ThiccTreeData :: struct {
    data: [64]^ThiccTree
}

// 3 level Octree for 64x64x64
// 4x4x4 cubes instead of 2x2x2 cubes
ThiccTree :: struct {
    children: u64,
    data: ^ThiccTreeData,
}

thicc_traverse :: proc(t1: ^ThiccTree, x, y, z: u8) -> rawptr {
    x1, y1, z1 := x / 16, y / 16, z / 16 // layer 1 index
    xs2, ys2, zs2 := x % 16, y % 16, z % 16 
    x2, y2, z2 := xs2 / 4, ys2 / 4, zs2 / 4 // layer 2 index
    x3, y3, z3 := xs2 % 4, ys2 % 4, zs2 % 4 // layer 3 index

    idx1 := thicc_pos_to_index(x1, y1, z1)
    idx2 := thicc_pos_to_index(x2, y2, z2)
    idx3 := thicc_pos_to_index(x3, y3, z3)

    t2: ^ThiccTree
    t3: ^ThiccTree
    value: rawptr

    if t2 = thicc_get_by_index(t1, idx1); t2 == nil do return nil
    if t3 = thicc_get_by_index(t2, idx2); t3 == nil do return nil
    if value = thicc_get_by_index(t3, idx3); value == nil do return nil
    
    return value
}

// expects a coordinate within (0, 0, 0) to (3, 3, 3)
thicc_pos_to_index :: proc(x, y, z: u8) -> u8 {
    assert(x + y + z >= 0 && x + y + z < 64)
    index := x + (y * 4) + (z * 4 * 4)
    return index
}



thicc_set_by_index :: proc(t, t2: ^ThiccTree, index: u8) {
    if t2 == nil {
        t.children &= ~(1 << index)
    } else {
        t.children |= (1 << index)
    }
    t.data.data[index] = t2
}

// can be nil
thicc_get_by_index :: proc(t: ^ThiccTree, index: u8) -> ^ThiccTree {
    if t.children & (1 << index) != 1 do return nil

    return t.data.data[index]
}



// thicc_get :: proc(ot: ^ThiccTree, index: u8) -> ^ThiccTree {
//     return ot.children[index]
// }