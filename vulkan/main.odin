package gpu

import "core:os"
import "core:fmt"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

WIDTH :: 800
HEIGHT :: 600
TARGET_FRAME_TIME :: time.Second / 30.0

// This combination is guaranteed to be available everywhere
color_format := vk.Format.B8G8R8A8_SRGB
color_space := vk.ColorSpaceKHR.SRGB_NONLINEAR

vertex_shader := #load("vert.spv")
fragment_shader := #load("frag.spv")

when ODIN_DEBUG {
	debug_messenger: vk.DebugUtilsMessengerEXT
}

Queue :: struct {
	handle: vk.Queue,
	family: u32
}

Swapchain :: struct {
	handle: vk.SwapchainKHR,
	count: u32,
	images: [dynamic]vk.Image,
	views: [dynamic]vk.ImageView,
	size: vk.Extent2D
}

Render_State :: struct {
	queue: Queue,
	pool: vk.CommandPool,
	buffer: vk.CommandBuffer,
	pipeline: vk.Pipeline,
	image: vk.Image,
	image_view: vk.ImageView,
	image_index: u32,
	image_available: vk.Semaphore,
	finished: vk.Semaphore
}

Presentation_State :: struct {
	queue: Queue,
	surface: vk.SurfaceKHR,
	swapchain: Swapchain
}

State :: struct {
	instance: vk.Instance,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,

	window: glfw.WindowHandle,
	render: Render_State,
	presentation: Presentation_State
}

main :: proc() {
	state: State

	init_glfw()
	defer glfw.Terminate()

	init_instance(&state, glfw.GetRequiredInstanceExtensions())
	defer deinit_instance(&state)

	create_window(&state)
	defer destroy_window(&state)

	select_device(&state)
	defer deinit_device(&state)

	create_swapchain(&state, false)
	defer destroy_swapchain(&state)

	init_render_state(&state)
	defer deinit_render_state(&state)

	create_pipeline(&state)
	defer destroy_pipeline(&state)

	last: time.Time
	for !glfw.WindowShouldClose(state.window) {
		free_all(context.temp_allocator)

		glfw.PollEvents()

		acquire_image(&state)
		render(&state)
		present(&state)

		// TODO: erm this is probably not ideal
		vk.DeviceWaitIdle(state.device)

		now := time.now()
		delta := time.diff(last, now)
		wait := TARGET_FRAME_TIME - delta
		if wait > 0 {
			time.sleep(wait)
			last = time.time_add(now, wait)
		} else {
			last = now
		}
	}
}

fatal :: proc(args: ..any) {
	fmt.fprintln(os.stderr, ..args)
	os.exit(1)
}
fatalf :: proc(format: string, args: ..any) {
	fmt.fprintfln(os.stderr, format, ..args)
	os.exit(1)
}
warn :: proc(args: ..any) {
	fmt.fprintln(os.stderr, ..args)
}
warnf :: proc(format: string, args: ..any) {
	fmt.fprintfln(os.stderr, format, ..args)
}

init_glfw :: proc() {
	glfw.SetErrorCallback(proc "c" (_: i32, description: cstring) {
		// Print functions aren't contextless
		// But they don't actually use the context...?
		context = {}

		fmt.fprintln(os.stderr, "GLFW:", description)
	})

	glfw.Init()
}

init_instance :: proc(state: ^State, required_extensions: []cstring) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	application_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		apiVersion = vk.API_VERSION_1_3,
		pApplicationName = "Vulkan Renderer"
	}
	create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &application_info
	}

	extra_extensions := [?]cstring{}

	extension_count := u32(len(required_extensions) + len(extra_extensions))
	when ODIN_DEBUG do extension_count += 1
	extensions := make([]cstring, extension_count, context.temp_allocator)

	start := 0
	for extension, i in required_extensions do extensions[start + i] = extension
	start += len(required_extensions)

	for extension, i in extra_extensions do extensions[start + i] = extension
	when ODIN_DEBUG do start += len(extra_extensions)

	when ODIN_DEBUG {
		extensions[start] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME

		layers := [1]cstring{"VK_LAYER_KHRONOS_validation"}
		create_info.ppEnabledLayerNames = &layers[0]
		create_info.enabledLayerCount = 1
	}

	create_info.ppEnabledExtensionNames = &extensions[0]
	create_info.enabledExtensionCount = extension_count

	result := vk.CreateInstance(&create_info, nil, &state.instance)
	if result != .SUCCESS do fatal("Failed to create Vulkan instance:", result)

	vk.load_proc_addresses_instance(state.instance)

	when ODIN_DEBUG {
		debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.WARNING, .ERROR},
			messageType = {.VALIDATION},
			pfnUserCallback = proc "c" (severity: vk.DebugUtilsMessageSeverityFlagsEXT, types: vk.DebugUtilsMessageTypeFlagsEXT, data: ^vk.DebugUtilsMessengerCallbackDataEXT, _: rawptr) -> b32 {
				// Print functions aren't contextless
				// But they don't actually use the context...?
				context = {}

				switch {
				case .ERROR in severity:   fmt.fprintln(os.stderr, "Vulkan error:", data.pMessage)
				case .WARNING in severity: fmt.fprintln(os.stderr, "Vulkan warning:", data.pMessage)
				}

				return false
			}
		};

		result = vk.CreateDebugUtilsMessengerEXT(state.instance, &debug_create_info, nil, &debug_messenger)
		if result != .SUCCESS do fatal("Failed to create Vulkan debug messenger:", result)
	}
}

create_window :: proc(state: ^State) {
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	state.window = glfw.CreateWindow(WIDTH, HEIGHT, "Vulkan Renderer", nil, nil)
	if state.window == nil do fatal("Failed to open window")

	result := glfw.CreateWindowSurface(state.instance, state.window, nil, &state.presentation.surface)
	if result != .SUCCESS do fatal("Failed to create surface:", result)
}

select_device :: proc(state: ^State) {
	count: u32 = 0
	vk.EnumeratePhysicalDevices(state.instance, &count, nil)
	if count == 0 do fatal("No Vulkan device")

	physical_devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(state.instance, &count, &physical_devices[0])

	found := false
	for i in 0..<count {
		state.physical_device = physical_devices[i]
		if init_device(state) {
			found = true
			break
		}
	}
	if !found do fatal("No suitable GPU")
}

init_device :: proc(state: ^State) -> bool {
	properties: vk.PhysicalDeviceProperties = ---
	vk.GetPhysicalDeviceProperties(state.physical_device, &properties)

	#partial switch properties.deviceType {
	case .DISCRETE_GPU, .INTEGRATED_GPU, .VIRTUAL_GPU:
		break
	case:
		return false
	}

	count: u32 = ---
	vk.GetPhysicalDeviceQueueFamilyProperties(state.physical_device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(state.physical_device, &count, &families[0])

	found_graphics := false
	found_presentation := false
	match := false
	loop: for i in 0..<count {
		family := &families[i]

		_presentation_support: b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(state.physical_device, i, state.presentation.surface, &_presentation_support)

		graphics_support := .GRAPHICS in family.queueFlags
		presentation_support := bool(_presentation_support)

		switch {
			case graphics_support:
				state.render.queue.family = i
				found_graphics = true
				fallthrough
			case presentation_support:
				state.presentation.queue.family = i
				found_presentation = true
				fallthrough
			case found_graphics && found_presentation:
				match = true
				break loop
		}
	}
	if !found_graphics || !found_presentation do return false

	priority: f32 = 1
	queue_create_infos: [2]vk.DeviceQueueCreateInfo = ---
	queue_create_info_count: u32 = ---

	queue_create_infos[0] = {
		sType = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = state.render.queue.family,
		queueCount = 1,
		pQueuePriorities = &priority
	}
	if match {
		queue_create_info_count = 1
	} else {
		queue_create_infos[1] = {
			sType = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = state.presentation.queue.family,
			queueCount = 1,
			pQueuePriorities = &priority
		}
		queue_create_info_count = 2
	}

	extensions := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	features12 := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	}
	features13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext = &features12,
		synchronization2 = true,
		dynamicRendering = true
	}
	device_create_info := vk.DeviceCreateInfo {
		sType = .DEVICE_CREATE_INFO,
		pNext = &features13,
		pQueueCreateInfos = &queue_create_infos[0],
		queueCreateInfoCount = queue_create_info_count,
		ppEnabledExtensionNames = &extensions[0],
		enabledExtensionCount = len(extensions)
	}
	result := vk.CreateDevice(state.physical_device, &device_create_info, nil, &state.device)
	if result != .SUCCESS {
		warnf("Failed to create logical device for %s: %s", cstring(&properties.deviceName[0]), result)
		return false
	}

	vk.GetDeviceQueue(state.device, state.render.queue.family, 0, &state.render.queue.handle)
	if match {
		state.presentation.queue.handle = state.render.queue.handle
	} else {
		vk.GetDeviceQueue(state.device, state.presentation.queue.family, 0, &state.presentation.queue.handle)
	}

	return true
}

create_swapchain :: proc(state: ^State, re: bool) {
	swapchain := &state.presentation.swapchain

	capabilities: vk.SurfaceCapabilitiesKHR = ---
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(state.physical_device, state.presentation.surface, &capabilities)

	image_count := capabilities.minImageCount
	// re means that we have presented at least once, so the window size should be available
	swapchain.size = re ? capabilities.currentExtent : {WIDTH, HEIGHT}

	create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = state.presentation.surface,
		minImageCount = image_count,
		imageFormat = color_format,
		imageColorSpace = color_space,
		imageExtent = swapchain.size,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		preTransform = capabilities.currentTransform,
		compositeAlpha = {.OPAQUE},
		presentMode = .FIFO, // V-Sync, guaranteed to be available
		oldSwapchain = re ? swapchain.handle : 0
	}
	vk.CreateSwapchainKHR(state.device, &create_info, nil, &swapchain.handle)

	if re {
		for view in swapchain.views {
			vk.DestroyImageView(state.device, view, nil)
		}

		// According to spec, the old swapchain is "retired" and we "can" destroy it
		vk.DestroySwapchainKHR(state.device, create_info.oldSwapchain, nil)
	}

	vk.GetSwapchainImagesKHR(state.device, swapchain.handle, &image_count, nil)
	if image_count != swapchain.count {
		resize(&swapchain.images, image_count)
		resize(&swapchain.views, image_count)

		swapchain.count = image_count
	}
	vk.GetSwapchainImagesKHR(state.device, swapchain.handle, &image_count, &swapchain.images[0])

	view_create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		format = color_format,
		subresourceRange = {
			aspectMask = {.COLOR},
			levelCount = 1,
			layerCount = 1
		}
	}
	for i in 0..<image_count {
		view_create_info.image = swapchain.images[i]
		vk.CreateImageView(state.device, &view_create_info, nil, &swapchain.views[i])
	}
}

init_render_state :: proc(state: ^State) {
	pool_create_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = state.render.queue.family,
		flags = {.RESET_COMMAND_BUFFER, .TRANSIENT}
	}
	vk.CreateCommandPool(state.device, &pool_create_info, nil, &state.render.pool)

	buffer_allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = state.render.pool,
		commandBufferCount = 1
	}
	vk.AllocateCommandBuffers(state.device, &buffer_allocate_info, &state.render.buffer)

	semaphore_create_info := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
	vk.CreateSemaphore(state.device, &semaphore_create_info, nil, &state.render.image_available)
	vk.CreateSemaphore(state.device, &semaphore_create_info, nil, &state.render.finished)
}

create_pipeline :: proc(state: ^State) {
	vertex_create_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(vertex_shader),
		pCode = cast(^u32)&vertex_shader[0]
	}
	fragment_create_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(fragment_shader),
		pCode = cast(^u32)&fragment_shader[0]
	}
	vertex_module: vk.ShaderModule = ---
	fragment_module: vk.ShaderModule = ---
	vk.CreateShaderModule(state.device, &vertex_create_info, nil, &vertex_module)
	vk.CreateShaderModule(state.device, &fragment_create_info, nil, &fragment_module)
	defer {
		vk.DestroyShaderModule(state.device, vertex_module, nil)
		vk.DestroyShaderModule(state.device, fragment_module, nil)
	}

	stages := [?]vk.PipelineShaderStageCreateInfo{
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vertex_module,
			pName = "main"
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = fragment_module,
			pName = "main"
		}
	}

	vertex_input_state := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	}
	input_assembly_state := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST
	}
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount = 1
	}
	rasterization_state := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode = {.BACK},
		frontFace = .COUNTER_CLOCKWISE,
		lineWidth = 1
	}
	multisample_state := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1}
	}

	attachment_blend_state := vk.PipelineColorBlendAttachmentState{colorWriteMask = {.R, .G, .B}}
	color_blend_state := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &attachment_blend_state
	}

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates = &dynamic_states[0]
	}

	layout_create_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO
	}
	layout: vk.PipelineLayout = ---
	vk.CreatePipelineLayout(state.device, &layout_create_info, nil, &layout)
	defer vk.DestroyPipelineLayout(state.device, layout, nil)

	rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &color_format
	}
	pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext = &rendering_create_info,
		stageCount = 2,
		pStages = &stages[0],
		pVertexInputState = &vertex_input_state,
		pInputAssemblyState = &input_assembly_state,
		pViewportState = &viewport_state,
		pRasterizationState = &rasterization_state,
		pMultisampleState = &multisample_state,
		pColorBlendState = &color_blend_state,
		pDynamicState = &dynamic_state,
		layout = layout
	}
	vk.CreateGraphicsPipelines(state.device, 0, 1, &pipeline_create_info, nil, &state.render.pipeline)
}

acquire_image :: proc(state: ^State) -> vk.Result {
	render := &state.render
	swapchain := &state.presentation.swapchain

	result := vk.AcquireNextImageKHR(state.device, swapchain.handle, max(u64), render.image_available, 0, &render.image_index)
	render.image = swapchain.images[render.image_index]
	render.image_view = swapchain.views[render.image_index]

	return result
}

render :: proc(state: ^State) {
	buffer := state.render.buffer

	command_buffer_begin_info := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO}
	vk.BeginCommandBuffer(buffer, &command_buffer_begin_info)
	defer vk.EndCommandBuffer(buffer)

	// TODO: this is not updated on resizes
	size := state.presentation.swapchain.size
	viewport := vk.Viewport {
		width = f32(size.width),
		height = f32(size.height),
		minDepth = 0,
		maxDepth = 1
	}
	scissor := vk.Rect2D{extent = size}
	vk.CmdSetViewport(buffer, 0, 1, &viewport)
	vk.CmdSetScissor(buffer, 0,1, &scissor)

	subresource_range := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = 1,
		layerCount = 1
	}
	to_draw_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = {.TOP_OF_PIPE},
		dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {.MEMORY_READ},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .COLOR_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = state.presentation.queue.family,
		dstQueueFamilyIndex = state.render.queue.family,
		image = state.render.image,
		subresourceRange = subresource_range
	}
	to_draw := vk.DependencyInfo {
		sType = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers = &to_draw_barrier
	}
	draw_to_present_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
		dstStageMask = {.BOTTOM_OF_PIPE},
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		dstAccessMask = {.MEMORY_READ},
		oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
		newLayout = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = state.render.queue.family,
		dstQueueFamilyIndex = state.presentation.queue.family,
		image = state.render.image,
		subresourceRange = subresource_range,
	}
	draw_to_present := vk.DependencyInfo {
		sType = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers = &draw_to_present_barrier
	}
	vk.CmdPipelineBarrier2(buffer, &to_draw)
	defer vk.CmdPipelineBarrier2(buffer, &draw_to_present)

	output_attachment := vk.RenderingAttachmentInfo{
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = state.render.image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0, 0, 0, 1}}}
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = state.presentation.swapchain.size},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &output_attachment
	}
	vk.CmdBeginRendering(buffer, &rendering_info)
	defer vk.CmdEndRendering(buffer)

	vk.CmdBindPipeline(buffer, .GRAPHICS, state.render.pipeline)
	vk.CmdDraw(buffer, 3, 1, 0, 0)
}

present :: proc(state: ^State) -> vk.Result {
	stage_mask := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &state.render.image_available,
		pWaitDstStageMask = &stage_mask,
		commandBufferCount = 1,
		pCommandBuffers = &state.render.buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores = &state.render.finished
	}

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &state.render.finished,
		swapchainCount = 1,
		pSwapchains = &state.presentation.swapchain.handle,
		pImageIndices = &state.render.image_index
	}

	vk.QueueSubmit(state.render.queue.handle, 1, &submit_info, 0)
	return vk.QueuePresentKHR(state.presentation.queue.handle, &present_info)
}

destroy_window :: proc(state: ^State) {
	vk.DestroySurfaceKHR(state.instance, state.presentation.surface, nil)
	glfw.DestroyWindow(state.window)
}

deinit_instance :: proc(state: ^State) {
	when ODIN_DEBUG do vk.DestroyDebugUtilsMessengerEXT(state.instance, debug_messenger, nil)
	vk.DestroyInstance(state.instance, nil)
}

deinit_device :: proc(state: ^State) {
	vk.DestroyDevice(state.device, nil)
}

destroy_swapchain :: proc(state: ^State) {
	presentation := &state.presentation

	for view in presentation.swapchain.views {
		vk.DestroyImageView(state.device, view, nil)
	}
	delete(presentation.swapchain.images)
	vk.DestroySwapchainKHR(state.device, presentation.swapchain.handle, nil)
}

deinit_render_state :: proc(state: ^State) {
	vk.DestroySemaphore(state.device, state.render.image_available, nil)
	vk.DestroySemaphore(state.device, state.render.finished, nil)

	vk.DestroyCommandPool(state.device, state.render.pool, nil)
}

destroy_pipeline :: proc(state: ^State) {
	vk.DestroyPipeline(state.device, state.render.pipeline, nil)
}
