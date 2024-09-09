package cvk

import "base:runtime"

import "core:os"
import "core:fmt"

import vk "vendor:vulkan"

create_instance :: proc(using vctx: ^VulkanContext, window_extensions: []cstring) {
    app_info := vk.ApplicationInfo {
        sType = .APPLICATION_INFO,
        pApplicationName = "Cuber",
        applicationVersion = vk.MAKE_VERSION(0, 1, 0),
        pEngineName = "Cuber Engine",
        engineVersion = vk.MAKE_VERSION(0, 1, 0),
        apiVersion = vk.API_VERSION_1_3,
    }


	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	layers := make([]vk.LayerProperties, layer_count)
	defer delete(layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers))

    outer: for name in VALIDATION_LAYERS {
        for &layer in layers {
            layer_name := cstring(&layer.layerName[0])
            fmt.printfln("layer:", layer_name)
            if name == layer_name do continue outer;
        }
        fmt.eprintf("ERROR: validation layer %q not available\n", name);
        os.exit(1);
    }
    


    debug_messenger_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
        sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        messageSeverity = {.WARNING, .ERROR},
        messageType = {.PERFORMANCE, .VALIDATION, .GENERAL},
        pfnUserCallback = debug_callback,
    }
    

    instance_info := vk.InstanceCreateInfo {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = &app_info,
        enabledExtensionCount = auto_cast len(window_extensions),
        ppEnabledExtensionNames = raw_data(window_extensions),
        enabledLayerCount = auto_cast len(VALIDATION_LAYERS),
        ppEnabledLayerNames = raw_data(VALIDATION_LAYERS),
        // pNext = &debug_messenger_create_info,
    }

    if vk.CreateInstance(&instance_info, nil, &instance) != vk.Result.SUCCESS {
        fmt.eprintfln("ERROR: Failed to create instance");
		return;
    }
}


create_device :: proc(using vctx: ^VulkanContext) {
    features12 := vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        bufferDeviceAddress = true,
        descriptorIndexing = true,
        timelineSemaphore = true,
    }
    features13 := vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        pNext = &features12,
        dynamicRendering = true,
        synchronization2 = true,
    }

    pd_count: u32
    vk.EnumeratePhysicalDevices(instance, &pd_count, nil)
    pdevices := make([]vk.PhysicalDevice, pd_count)
    defer delete(pdevices)
    vk.EnumeratePhysicalDevices(instance, &pd_count, raw_data(pdevices))

    pdevice_suitability :: proc(using vctx: ^VulkanContext, pdev: vk.PhysicalDevice) -> bool {
        properties: vk.PhysicalDeviceProperties
        features: vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(pdev, &properties)
        vk.GetPhysicalDeviceFeatures(pdev, &features)
        
        features12: vk.PhysicalDeviceVulkan12Features = {
            sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            bufferDeviceAddress = true,
            descriptorIndexing = true,
            timelineSemaphore = true,
        }
        features13: vk.PhysicalDeviceVulkan13Features = {
            sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            dynamicRendering = true,
            synchronization2 = true,
        }
        features2: vk.PhysicalDeviceFeatures2
        features2.sType = .PHYSICAL_DEVICE_FEATURES_2
        features2.pNext = &features13
        features13.pNext = &features12

        vk.GetPhysicalDeviceFeatures2(pdev, &features2)

        if (features13.dynamicRendering && features13.synchronization2 &&
            features12.bufferDeviceAddress && features12.descriptorIndexing) {
            return true
        }

        return false
    }

    found := false
    for pdev in pdevices {
        if pdevice_suitability(vctx, pdev) {
            pdevice = pdev
            found = true
        }
    }
    if !found {
        // TODO handle error
    }

    find_queue_families(vctx)

    queue_priority: f32 = 1.0
    unique_ids: map[int]b8
    defer delete(unique_ids)
    tmp_ids := [2]int{qf_ids[.GCT], qf_ids[.Present]}
    for index in tmp_ids do unique_ids[index] = true 

    queue_infos: [dynamic]vk.DeviceQueueCreateInfo
    defer delete(queue_infos)

    for index, _ in unique_ids {
        queue_info := vk.DeviceQueueCreateInfo {
            sType = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = auto_cast index,
            queueCount = 1,
            pQueuePriorities = &queue_priority,
        }
        append(&queue_infos, queue_info)
    }

    features: vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceFeatures(pdevice, &features)

    info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        pNext = &features13,
        pEnabledFeatures = &features,
        enabledExtensionCount = auto_cast len(DEVICE_EXTENSIONS),
        ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
        enabledLayerCount = auto_cast len(VALIDATION_LAYERS),
        ppEnabledLayerNames = raw_data(VALIDATION_LAYERS),
        queueCreateInfoCount = auto_cast len(queue_infos),
        pQueueCreateInfos = &queue_infos[0],
    }

    if vk.CreateDevice(pdevice, &info, nil, &device) != .SUCCESS {
        fmt.eprintfln("ERROR: Failed to create logical device")
        os.exit(1)
    }
}

when ODIN_OS == .Windows {
    debug_callback :: proc "stdcall" (
        messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, 
        messageTypes: vk.DebugUtilsMessageTypeFlagsEXT, 
        pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT, 
    pUserData: rawptr) -> b32 {
        context = runtime.default_context()
        fmt.println("Validation layer: ", pCallbackData.pMessage)
        return false
    }

} else {
    debug_callback :: proc "c" (
        messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, 
        messageTypes: vk.DebugUtilsMessageTypeFlagsEXT, 
        pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT, 
    pUserData: rawptr) -> b32 {
        context = runtime.default_context()
        fmt.println("Validation layer: ", pCallbackData.pMessage)
        return false
    }
}


find_queue_families :: proc(using vctx: ^VulkanContext) {
    count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &count, nil);
    families := make([]vk.QueueFamilyProperties, count)
    defer delete(families)
    vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &count, raw_data(families));

    qf_ids = [QueueType]int{
        .GCT = -1,
        .Graphics = -1,
        .Compute = -1,
        .Transfer = -1,
        .Present = -1,
    }

    for fam, idx in families {
        if .TRANSFER in fam.queueFlags && .GRAPHICS in fam.queueFlags && .COMPUTE in fam.queueFlags {
            if qf_ids[.GCT] == -1 {
                qf_ids[.GCT] = idx
            }
        }

        present_support: b32
        vk.GetPhysicalDeviceSurfaceSupportKHR(pdevice, u32(idx), surface, &present_support)
        if present_support && qf_ids[.Present] == -1 {
            qf_ids[.Present] = idx
        }
        if qf_ids[.GCT] != -1 && qf_ids[.Present] != -1 { 
            break 
        }
    }
}

create_queues :: proc(using vctx: ^VulkanContext) {
    vk.GetDeviceQueue(device, auto_cast qf_ids[.GCT], 0, &queues[.GCT])
    vk.GetDeviceQueue(device, auto_cast qf_ids[.Present], 0, &queues[.Present])
}
