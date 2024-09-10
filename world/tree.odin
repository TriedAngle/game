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

// init_thicctree :: proc(ot: ^ThiccTree) {
//     for &child in ot.children {
//         child = nil
//     }
// }


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