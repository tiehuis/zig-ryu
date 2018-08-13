Conversion of https://github.com/ulfjack/ryu to [zig](https://ziglang.org/).

## Install

```
git clone --recurse-submodules https://github.com/tiehuis/zig-ryu
```

## Benchmarks

Requires `sh`, `make`, `cmake`, `c++`, `zig`

```
./build.sh
./bench-reference # reference timing
./bench-zig       # zig timing
```

## Todo

 - [ ] Review all manual casts
 - [x] Make more idiomatic
 - [x] Add f16 variant
 - [x] Add f128 variant (Use partial table set)
 - [ ] Add specified precision argument (current errol does this after but this is
   slows things down a fair bit).
 - [x] Benchmark against current float printing code (memory
   consumption/performance).

