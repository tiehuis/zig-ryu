#!/bin/sh

set -e

mkdir -p build

echo "building double-conversion dependency"
cd ryu/third_party/double-conversion
mkdir -p build-ryu
cd build-ryu
cmake .. -DCMAKE_BUILD_TYPE=Release > /dev/null
make -j4 > /dev/null
cp double-conversion/libdouble-conversion.a ../../../../build
cd ../../../..

echo "building reference benchmark"
g++ -std=c++11 -O2 -Iryu ryu/ryu/*.c ryu/ryu/benchmark/benchmark.cc build/libdouble-conversion.a -o bench-reference

echo "building zig benchmark"
zig build-obj src/ryu_c.zig --release-fast --output-dir build --name ryu.zig --cache-dir build --library c
g++ -std=c++11 -O2 -Iryu build/ryu.zig.o ryu/ryu/benchmark/benchmark.cc build/libdouble-conversion.a -o bench-zig
