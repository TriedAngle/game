package world

ThiccTreeData :: struct {
    data: [u64]^ThiccTree
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

// thicc_set :: proc(ot, ot2: ^ThiccTree, index: u8) {
//     ot.children[index] = ot2
// }

// thicc_get :: proc(ot: ^ThiccTree, index: u8) -> ^ThiccTree {
//     return ot.children[index]
// }