package logger

import "core:os"
import "core:log"
import "core:strings"
import "core:terminal"
import "core:terminal/ansi"

get :: proc() -> log.Logger {
	return {
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
}
