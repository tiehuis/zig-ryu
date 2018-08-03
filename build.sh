#!/bin/sh

mkdir -p build

echo "building double-conversion dependency"
cd ryu/third_party/double-conversion
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release > /dev/null
make -j4 > /dev/null
cp double-conversion/libdouble-conversion.a ../../../../build
cd ../../../..

echo "building reference benchmark"
g++ -O2 -Iryu ryu/ryu/*.c ryu/ryu/benchmark/benchmark.cc build/libdouble-conversion.a -o bench-reference

echo "building zig benchmark"
zig build-obj ryu_c.zig --release-fast --output build/ryu.zig.o --output-h build/ryu.zig.h --cache-dir build
g++ -O2 -Iryu build/ryu.zig.o ryu/ryu/benchmark/benchmark.cc build/libdouble-conversion.a -o bench-zig
