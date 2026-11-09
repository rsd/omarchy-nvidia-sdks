# Builds the os-release shim. The Makefile installs nothing: the maxine-vfx
# package (maxine-vfx/PKGBUILD) installs the result (see README.md).
#
#   make                 # -> <repo>/target/os-release-shim/os-release-shim.so
#   make OUT=/some/dir   # -> /some/dir/os-release-shim.so
#   make test            # builds, then runs test.sh against the build

HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
OUT ?= $(abspath $(HERE)../../target/os-release-shim)
CC ?= gcc
CFLAGS ?= -O2
LDFLAGS ?=
SHIM_CFLAGS := -shared -fPIC -fvisibility=hidden -Wall -Wextra -Werror -std=gnu11

SHIM := $(OUT)/os-release-shim.so

.PHONY: all test clean
all: $(SHIM)

$(SHIM): $(HERE)os-release-shim.c $(HERE)Makefile
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(SHIM_CFLAGS) $(LDFLAGS) -o $@ $< -ldl -lpthread

test: $(SHIM)
	OUT=$(OUT) CC=$(CC) $(HERE)test.sh $(SHIM)

clean:
	rm -f $(SHIM) $(OUT)/shim-test
