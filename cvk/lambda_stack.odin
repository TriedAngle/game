package cvk

import "core:testing"

Lambda :: struct {
    data: rawptr,
    fun: proc(^VulkanContext, rawptr),
}

LambdaStack :: struct {
    lambdas: [dynamic]Lambda,
}

deinit_lambda_stack :: proc(stack: ^LambdaStack) {
    delete(stack.lambdas)
}

push :: proc(using dq: ^LambdaStack, lambda: Lambda) {
    append(&lambdas, lambda)
} 

flush :: proc(using dq: ^LambdaStack, vctx: ^VulkanContext) {
    #reverse for lamda in lambdas {
        lamda.fun(vctx, lamda.data)
    }
    clear(&lambdas)
}


@(test)
test_dq :: proc(t: ^testing.T) {
    ls: LambdaStack
    defer deinit_lambda_stack(&ls)

    value := 10 
    test_proc := proc(vctx: ^VulkanContext, data: rawptr) {
        value := cast(^u32)data
        value^ += 1
    }

    push(&ls, {&value, test_proc})

    flush(&ls, nil)

    testing.expect(t, value == 11)
}