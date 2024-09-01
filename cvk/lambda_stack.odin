package cvk

import "core:testing"
LambdaValue :: union {rawptr, u64}
Lambda :: struct {
    data: LambdaValue,
    fun: proc(^VulkanContext, LambdaValue),
}

LambdaStack :: struct {
    lambdas: [dynamic]Lambda,
}

deinit_lambda_stack :: proc(stack: ^LambdaStack) {
    delete(stack.lambdas)
}

lambda :: proc(using dq: ^LambdaStack, lambda: Lambda) {
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
    test_proc := proc(vctx: ^VulkanContext, data: LambdaValue) {
        value := cast(^u32)data.(rawptr)
        value^ += 1
    }

    lambda(&ls, {cast(rawptr)&value, test_proc})

    flush(&ls, nil)

    testing.expect(t, value == 11)
}