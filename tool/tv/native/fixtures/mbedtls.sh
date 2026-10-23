#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	make clean
	exit 0
else
	exit 255
fi

$0 clean # separate building not supported, always clean

# since 3.6.6 mbedTLS reads entropy from /dev/random when getrandom() is not used,
# which is always the case on bionic, and that blocks on kernels older than 5.6
./scripts/config.py set MBEDTLS_PLATFORM_DEV_RANDOM '"/dev/urandom"'

if [ "$ndk_suffix" == "-arm64" ]; then
	make CFLAGS="-fPIC -march=armv8-a+crypto" CXXFLAGS="-fPIC -march=armv8-a+crypto" -j$cores no_test
else
	make CFLAGS="-fPIC" CXXFLAGS="-fPIC" -j$cores no_test
fi

make CFLAGS=-fPIC CXXFLAGS=-fPIC DESTDIR="$prefix_dir" install
