package gpu

import "base:intrinsics"
import "core:log"
import "core:os"
import "core:strings"
import "core:terminal"
import "core:terminal/ansi"
import "core:time"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

import "vma"

TITLE :: "Vulkan Renderer"

// NOTE: this combination is guaranteed to be available everywhere
@rodata color_format := vk.Format.B8G8R8A8_SRGB
@rodata color_space  := vk.ColorSpaceKHR.SRGB_NONLINEAR

@rodata vertex_shader   := #load("shader.vert.spv")
@rodata fragment_shader := #load("shader.frag.spv")

Queue :: struct {
	handle: vk.Queue,
	family: u32
}

Swapchain :: struct {
	handle: vk.SwapchainKHR,
	images: [dynamic]vk.Image,
	views: [dynamic]vk.ImageView,
	size: vk.Extent2D
}

Window :: struct {
	handle: ^sdl.Window,
	surface: vk.SurfaceKHR,
	queue: Queue,
	swapchain: Swapchain,
	image_available: vk.Semaphore
}

Renderer :: struct {
	queue: Queue,
	pool: vk.CommandPool,
	buffer: vk.CommandBuffer,
	pipeline: vk.Pipeline,
	done: vk.Semaphore,
}

Buffer :: struct {
	handle: vk.Buffer,
	allocation: vma.Allocation
}

Vertex :: struct {
	position: [2]f32,
	color: [3]f32
}

instance:        vk.Instance
physical_device: vk.PhysicalDevice
device:          vk.Device
gpu_allocator:   vma.Allocator

window:    Window
renderer:  Renderer

@rodata vertecies := [?]Vertex{
	{{0, -0.5},   {1, 0, 0}},
	{{-0.5, 0.5}, {0, 1, 0}},
	{{0.5, 0.5},  {0, 0, 1}}
}
vertex_buffer: Buffer

when ODIN_DEBUG {
	global_context: runtime.Context
	debug_messenger: vk.DebugUtilsMessengerEXT
}

main :: proc() {
	// NOTE: context setup
	context.logger = {
		procedure = proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
			PREFIX_WARNING :: ansi.CSI + ansi.FG_YELLOW + ansi.SGR
			PREFIX_ERROR   :: ansi.CSI + ansi.FG_RED + ansi.SGR
			PREFIX_FATAL   :: ansi.CSI + ansi.FG_RED + ";" + ansi.BOLD + ansi.SGR
			SUFFIX_COLORED :: ansi.CSI + ansi.RESET + ansi.SGR

			// NOTE: the temp allocator is (and should be kept) an arena
			// so the allocation is resized for free when the builder grows
			builder := strings.builder_make_none(context.temp_allocator)

			color := false
			if .Terminal_Color in options {
				#partial switch level {
					case .Warning: strings.write_string(&builder, PREFIX_WARNING); color = true
					case .Error:   strings.write_string(&builder, PREFIX_ERROR);   color = true
					case .Fatal:   strings.write_string(&builder, PREFIX_FATAL);   color = true
				}
			}

			strings.write_string(&builder, text)
			if color { strings.write_string(&builder, SUFFIX_COLORED) }
			strings.write_byte(&builder, '\n')

			os.write(os.stderr, builder.buf[:])

			if level == .Fatal {
				os.exit(1)
			}
		},
		lowest_level = .Debug when ODIN_DEBUG else .Warning,
		options = terminal.color_enabled ? {.Terminal_Color} : {}
	}

	when ODIN_DEBUG {
		global_context = context
	}


	// NOTE: SDL setup
	{
		ok := sdl.Init({.VIDEO})
		if !ok { log.fatal("Failed to initialize SDL:", sdl.GetError()) }

		ok = sdl.Vulkan_LoadLibrary(nil)
		if !ok { log.fatal("Failed to load system Vulkan loader library:", sdl.GetError()) }

		GetInstaceProcAddr := sdl.Vulkan_GetVkGetInstanceProcAddr()
		if GetInstaceProcAddr == nil { log.fatal("Failed to get the address of vkGetInstanceProcAddr:", sdl.GetError()) }
		vk.load_proc_addresses_global(rawptr(GetInstaceProcAddr))
	}


	// NOTE: instance creation
	{
		application_info := vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			apiVersion = vk.API_VERSION_1_3,
			pApplicationName = TITLE
		}
		create_info := vk.InstanceCreateInfo {
			sType = .INSTANCE_CREATE_INFO,
			pApplicationInfo = &application_info
		}

		extension_count: u32 = ---
		extensions := sdl.Vulkan_GetInstanceExtensions(&extension_count)
		if extensions == nil { log.fatal("Failed to get instance extensions:", sdl.GetError()) }

		when !ODIN_DEBUG {
			create_info.ppEnabledExtensionNames = &extensions[0]
			create_info.enabledExtensionCount = extension_count
		} else {
			all_extension_count := extension_count + 1
			all_extensions := make([]cstring, all_extension_count, context.temp_allocator)

			i: u32 = 0
			for ; i < extension_count; i += 1 { all_extensions[i] =  extensions[i] }
			all_extensions[i] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME

			create_info.ppEnabledExtensionNames = &all_extensions[0]
			create_info.enabledExtensionCount = all_extension_count

			layers := [1]cstring{"VK_LAYER_KHRONOS_validation"}
			create_info.ppEnabledLayerNames = &layers[0]
			create_info.enabledLayerCount = 1
		}

		result := vk.CreateInstance(&create_info, nil, &instance)
		if result != .SUCCESS { log.fatal("Failed to create Vulkan instance:", result) }

		vk.load_proc_addresses_instance(instance)

		when ODIN_DEBUG {
			debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
				sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
				messageSeverity = {.WARNING, .ERROR},
				messageType = {.VALIDATION},
				pfnUserCallback = proc "c" (severity: vk.DebugUtilsMessageSeverityFlagsEXT, types: vk.DebugUtilsMessageTypeFlagsEXT, data: ^vk.DebugUtilsMessengerCallbackDataEXT, _: rawptr) -> b32 {
					context = global_context

					switch {
					case .ERROR in severity: log.error("Vulkan error:", data.pMessage)
					case .WARNING in severity: log.warn("Vulkan warning:", data.pMessage)
					}

					return false
				}
			}

			result = vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &debug_messenger)
			if result != .SUCCESS { log.warn("Failed to create Vulkan debug messenger:", result) }
		}
	}


	// NOTE: window creation
	{
		window.handle = sdl.CreateWindow(TITLE, 0, 0, {.VULKAN, .RESIZABLE})
		if window.handle == nil { log.fatal("Failed to open window:", sdl.GetError()) }

		ok := sdl.Vulkan_CreateSurface(window.handle, instance, nil, &window.surface)
		if !ok { log.fatal("Failed to create Vulkan surface:", sdl.GetError()) }
	}


	// NOTE: device selection
	{
		device_count: u32
		vk.EnumeratePhysicalDevices(instance, &device_count, nil)
		if device_count == 0 { log.fatal("No Vulkan device") }

		devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
		vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0])

		device_properties := make([]vk.PhysicalDeviceProperties, device_count, context.temp_allocator)
		for i in 0..<device_count { vk.GetPhysicalDeviceProperties(devices[i], &device_properties[i]) }

		type_preferences := [?]bit_set[vk.PhysicalDeviceType]{
			{.DISCRETE_GPU, .VIRTUAL_GPU},
			{.INTEGRATED_GPU},
			{.CPU}
		}
		found := false
		outer: for types in type_preferences {
			for i in 0..<device_count {
				properties := device_properties[i]
				if properties.deviceType in types {
					device := devices[i]
					if try_device(device, cstring(&properties.deviceName[0])) {
						physical_device = device
						found = true
						break outer
					}
				}
			}
		}
		if !found { log.fatal("No suitable device") }
	}


	// NOTE: VMA setup
	{
		vulkan_functions := vma.VulkanFunctions {
			GetPhysicalDeviceProperties           = vk.GetPhysicalDeviceProperties,
			GetPhysicalDeviceMemoryProperties     = vk.GetPhysicalDeviceMemoryProperties,
			AllocateMemory                        = vk.AllocateMemory,
			FreeMemory                            = vk.FreeMemory,
			MapMemory                             = vk.MapMemory,
			UnmapMemory                           = vk.UnmapMemory,
			FlushMappedMemoryRanges               = vk.FlushMappedMemoryRanges,
			InvalidateMappedMemoryRanges          = vk.InvalidateMappedMemoryRanges,
			BindBufferMemory                      = vk.BindBufferMemory,
			BindImageMemory                       = vk.BindImageMemory,
			GetBufferMemoryRequirements           = vk.GetBufferMemoryRequirements,
			GetImageMemoryRequirements            = vk.GetImageMemoryRequirements,
			CreateBuffer                          = vk.CreateBuffer,
			DestroyBuffer                         = vk.DestroyBuffer,
			CreateImage                           = vk.CreateImage,
			DestroyImage                          = vk.DestroyImage,
			CmdCopyBuffer                         = vk.CmdCopyBuffer,
			GetBufferMemoryRequirements2KHR       = vk.GetBufferMemoryRequirements2KHR,
			GetImageMemoryRequirements2KHR        = vk.GetImageMemoryRequirements2KHR,
			BindBufferMemory2KHR                  = vk.BindBufferMemory2KHR,
			BindImageMemory2KHR                   = vk.BindImageMemory2KHR,
			GetPhysicalDeviceMemoryProperties2KHR = vk.GetPhysicalDeviceMemoryProperties2KHR
		}
		allocator_create_info := vma.AllocatorCreateInfo {
			physicalDevice = physical_device,
			device = device,
			instance = instance,
			pVulkanFunctions = &vulkan_functions
		}
		vma.CreateAllocator(&allocator_create_info, &gpu_allocator)
	}


	// NOTE: swapchain creation
	// NOTE: hopefully the window manager instantly provides the size through currentExtents,
	// if not, we create the smallest possible swapchain and rely on a resize event.
	create_swapchain(1, 1)


	// NOTE: rendering resource creation
	{
		pool_create_info := vk.CommandPoolCreateInfo {
			sType = .COMMAND_POOL_CREATE_INFO,
			queueFamilyIndex = renderer.queue.family,
			flags = {.RESET_COMMAND_BUFFER, .TRANSIENT}
		}
		vk.CreateCommandPool(device, &pool_create_info, nil, &renderer.pool)

		buffer_allocate_info := vk.CommandBufferAllocateInfo {
			sType = .COMMAND_BUFFER_ALLOCATE_INFO,
			level = .PRIMARY,
			commandPool = renderer.pool,
			commandBufferCount = 1
		}
		vk.AllocateCommandBuffers(device, &buffer_allocate_info, &renderer.buffer)


		semaphore_create_info := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
		vk.CreateSemaphore(device, &semaphore_create_info, nil, &window.image_available)
		vk.CreateSemaphore(device, &semaphore_create_info, nil, &renderer.done)


		buffer_create_info := vk.BufferCreateInfo {
			sType = .BUFFER_CREATE_INFO,
			size = size_of(vertecies),
			usage = {.VERTEX_BUFFER}
		}
		allocation_create_info := vma.AllocationCreateInfo {
			flags = {.MAPPED, .HOST_ACCESS_SEQUENTIAL_WRITE},
			usage = .AUTO
		}
		allocation_info: vma.AllocationInfo = ---
		vma.CreateBuffer(gpu_allocator, &buffer_create_info, &allocation_create_info, &vertex_buffer.handle, &vertex_buffer.allocation, &allocation_info)

		data: rawptr
		vma.MapMemory(gpu_allocator, vertex_buffer.allocation, &data)
		defer vma.UnmapMemory(gpu_allocator, vertex_buffer.allocation)

		intrinsics.mem_copy(data, &vertecies[0], size_of(vertecies))
	}


	// NOTE: pipeline creation
	{
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
		vk.CreateShaderModule(device, &vertex_create_info, nil, &vertex_module)
		vk.CreateShaderModule(device, &fragment_create_info, nil, &fragment_module)
		defer {
			vk.DestroyShaderModule(device, vertex_module, nil)
			vk.DestroyShaderModule(device, fragment_module, nil)
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


		vertex_binding_description := vk.VertexInputBindingDescription {
			binding = 0,
			stride = size_of(Vertex),
			inputRate = .VERTEX
		}
		// NOTE: the binding fields here to which vertex buffer binding the data comes from,
		// not the binding you would specify for textures in shader code
		vertex_attribute_descriptions := [?]vk.VertexInputAttributeDescription{
			{ binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = 0 },
			{ binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = auto_cast offset_of(Vertex, color) }
		}
		vertex_input_state := vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			vertexBindingDescriptionCount = 1,
			pVertexBindingDescriptions = &vertex_binding_description,
			vertexAttributeDescriptionCount = len(vertex_attribute_descriptions),
			pVertexAttributeDescriptions = &vertex_attribute_descriptions[0]
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
		vk.CreatePipelineLayout(device, &layout_create_info, nil, &layout)
		defer vk.DestroyPipelineLayout(device, layout, nil)

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
		vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_create_info, nil, &renderer.pipeline)
	}


	last := time.now()
	for {
		free_all(context.temp_allocator)


		for event: sdl.Event = ---; sdl.PollEvent(&event); {
			#partial switch event.type {
			case .WINDOW_RESIZED:
				create_swapchain(u32(event.window.data1), u32(event.window.data2))
			case .QUIT, .WINDOW_CLOSE_REQUESTED:
				return
			}
		}


		image_index: u32 = ---
		vk.AcquireNextImageKHR(device, window.swapchain.handle, max(u64), window.image_available, 0, &image_index)
		render(window.swapchain.images[image_index], window.swapchain.views[image_index])
		present(image_index)


		now := time.now()
		elapsed := time.diff(last, now)
		last = now

		ms := time.duration_milliseconds(elapsed)
		log.debugf("%.2f -> %.0f", ms, 1000 / ms)
	}
}

try_device :: proc(physical_device: vk.PhysicalDevice, name: cstring) -> bool {
	family_count: u32 = ---
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, nil)

	families := make([]vk.QueueFamilyProperties, family_count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, &families[0])

	// NOTE: if possible, we use the same queue family for rendering and presentation.
	// In reality, most devices have the first family support both graphics and presentation.
	found_graphics := false
	found_presentation := false
	match := false
	loop: for i in 0..<family_count {
		family := &families[i]

		_presentation_support: b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, i, window.surface, &_presentation_support)

		graphics_support := .GRAPHICS in family.queueFlags
		presentation_support := bool(_presentation_support)

		switch {
		case graphics_support:
			renderer.queue.family = i
			found_graphics = true
			fallthrough
		case presentation_support:
			window.queue.family = i
			found_presentation = true
			fallthrough
		case found_graphics && found_presentation:
			match = true
			break loop
		}
	}
	if !found_graphics || !found_presentation { return false }

	priority: f32 = 1
	queue_create_infos: [2]vk.DeviceQueueCreateInfo = ---
	queue_create_info_count: u32 = ---
	queue_create_infos[0] = {
		sType = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = renderer.queue.family,
		queueCount = 1,
		pQueuePriorities = &priority
	}
	if match {
		queue_create_info_count = 1
	} else {
		queue_create_infos[1] = {
			sType = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = window.queue.family,
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
	result := vk.CreateDevice(physical_device, &device_create_info, nil, &device)
	if result != .SUCCESS {
		log.warnf("Failed to create logical device for %s: %s", name, result)
		return false
	}

	vk.GetDeviceQueue(device, renderer.queue.family, 0, &renderer.queue.handle)
	if match {
		window.queue.handle = renderer.queue.handle
	} else {
		vk.GetDeviceQueue(device, window.queue.family, 0, &window.queue.handle)
	}

	log.info("Device:", name)
	return true
}

create_swapchain :: proc(width, height: u32) {
	swapchain := &window.swapchain

	capabilities: vk.SurfaceCapabilitiesKHR = ---
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, window.surface, &capabilities)

	image_count := capabilities.minImageCount

	// NOTE: max(u32) means that the window manager is letting us decide the swapchain size.
	// We will use the window size in that case.
	swapchain.size = capabilities.currentExtent.width != max(u32) ? capabilities.currentExtent : {
		clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
		clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = window.surface,
		minImageCount = image_count,
		imageFormat = color_format,
		imageColorSpace = color_space,
		imageExtent = swapchain.size,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		preTransform = capabilities.currentTransform,
		compositeAlpha = {.OPAQUE},
		// NOTE: FIFO = V-Sync, and it's guaranteed to be available
		presentMode = .FIFO,
		// NOTE: if this is the first swapchain, this will be 0, which is ignored
		oldSwapchain = swapchain.handle
	}
	vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain.handle)

	// NOTE: according to spec, the old swapchain is "retired" and we "can" destroy it
	if create_info.oldSwapchain != vk.SwapchainKHR(0) {
		vk.DestroySwapchainKHR(device, create_info.oldSwapchain, nil)
	}

	for view in swapchain.views {
		vk.DestroyImageView(device, view, nil)
	}

	vk.GetSwapchainImagesKHR(device, swapchain.handle, &image_count, nil)
	if image_count != u32(len(swapchain.images)) {
		resize(&swapchain.images, image_count)
		resize(&swapchain.views,  image_count)
	}
	vk.GetSwapchainImagesKHR(device, swapchain.handle, &image_count, &swapchain.images[0])

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
		vk.CreateImageView(device, &view_create_info, nil, &swapchain.views[i])
	}
}

render :: proc(output: vk.Image, output_view: vk.ImageView) {
	buffer := renderer.buffer

	command_buffer_begin_info := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO}
	vk.BeginCommandBuffer(buffer, &command_buffer_begin_info)
	defer vk.EndCommandBuffer(buffer)

	size := window.swapchain.size
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
		srcQueueFamilyIndex = window.queue.family,
		dstQueueFamilyIndex = renderer.queue.family,
		image = output,
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
		srcQueueFamilyIndex = renderer.queue.family,
		dstQueueFamilyIndex = window.queue.family,
		image = output,
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
		imageView = output_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0, 0, 0, 1}}}
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = window.swapchain.size},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &output_attachment
	}
	vk.CmdBeginRendering(buffer, &rendering_info)
	defer vk.CmdEndRendering(buffer)

	vk.CmdBindPipeline(buffer, .GRAPHICS, renderer.pipeline)

	offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(buffer, 0, 1, &vertex_buffer.handle, &offset)

	vk.CmdDraw(buffer, len(vertecies), 1, 0, 0)
}

present :: proc(index: u32) {
	index := index

	stage_mask := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &window.image_available,
		pWaitDstStageMask = &stage_mask,
		commandBufferCount = 1,
		pCommandBuffers = &renderer.buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores = &renderer.done
	}

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &renderer.done,
		swapchainCount = 1,
		pSwapchains = &window.swapchain.handle,
		pImageIndices = &index
	}

	vk.QueueSubmit(renderer.queue.handle, 1, &submit_info, 0)
	vk.QueuePresentKHR(window.queue.handle, &present_info)

	// NOTE: acts as V-Sync with the FIFO present mode
	vk.QueueWaitIdle(window.queue.handle)
}
