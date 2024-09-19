package cuber

import "core:fmt"
import "core:strings"

import "cvk"
import "gltf"

load_gltf :: proc(path: string) {
    data, error := gltf.load_from_file(path)
    defer gltf.unload(data)

    indices: [dynamic]u32
    vertices: [dynamic]cvk.Vertex

    for mesh in data.meshes[0:1] {
        name := mesh.name.? or_else ""
        defer delete(name)
        
        new: cvk.Mesh
        
        new.name = strings.clone(name)
        fmt.println("name: ", name)

        for primitive in mesh.primitives {
            surface := cvk.MeshSurface {
                start = auto_cast len(indices),
                count = auto_cast (primitive.indices.? or_else 0)
            }

            accessor := data.accessors[primitive.indices.(gltf.Integer)]
            reserve(&indices, len(indices) + auto_cast accessor.count)
            
            fmt.println("surface: ", surface)
            fmt.println("acessor: ", accessor)
        }
    }

}