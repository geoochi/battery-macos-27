CC = clang
CFLAGS = -O2 -Wall -Wextra -Werror -fobjc-arc
.PHONY: all test clean
all: build/battctl build/smc-probe
build/battctl: Sources/main.m Sources/version.h Sources/native.m Sources/persistent.m Sources/persistent.h Sources/native.h Sources/smc.h Sources/policy.h Sources/telemetry.h
	mkdir -p build
	$(CC) $(CFLAGS) -framework Foundation -framework IOKit Sources/main.m Sources/native.m Sources/persistent.m -o $@
build/smc-probe: Sources/probe.m Sources/smc.h
	mkdir -p build
	$(CC) -Wall -Wextra -Wno-unused-function -framework Foundation -framework IOKit Sources/probe.m -o $@
test: all
	$(CC) -Wall -Wextra -Werror tests/policy.c -o build/policy-test
	./build/policy-test
	$(CC) $(CFLAGS) -framework Foundation tests/telemetry.m -o build/telemetry-test
	./build/telemetry-test
	$(CC) $(CFLAGS) -framework Foundation tests/native.m Sources/native.m -o build/native-test
	./build/native-test
	$(CC) $(CFLAGS) -framework Foundation tests/persistent.m Sources/persistent.m Sources/native.m -o build/persistent-test
	./build/persistent-test
	./build/battctl --help
	./build/battctl --version
	@for script in scripts/*.sh; do bash -n "$$script" || exit; done
	! ./build/battctl run 0
	! ./build/battctl run 50oops
clean:
	rm -rf build
