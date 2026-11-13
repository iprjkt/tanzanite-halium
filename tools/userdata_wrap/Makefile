CC ?= aarch64-linux-gnu-gcc
CFLAGS ?= -Os -Wall -Wextra -static -s

all: userdata_wrap

userdata_wrap: userdata_wrap.c
	@if command -v zig >/dev/null 2>&1; then \
		echo "Building with zig cc (aarch64-linux-musl)..."; \
		zig cc -target aarch64-linux-musl -static -Os -s -Wall -o $@ $<; \
	elif command -v $(CC) >/dev/null 2>&1; then \
		echo "Building with $(CC)..."; \
		$(CC) $(CFLAGS) -o $@ $<; \
	else \
		echo "Error: Neither zig nor $(CC) found to compile userdata_wrap" >&2; \
		exit 1; \
	fi

clean:
	rm -f userdata_wrap

.PHONY: all clean
