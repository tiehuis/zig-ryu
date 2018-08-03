Conversion of https://github.com/ulfjack/ryu to [zig](https://ziglang.org/).

## Install

```
git clone --recurse-submodules https://github.com/tiehuis/zig-ryu
```

## Todo

 - [ ] Review all manual casts
 - [ ] Make more idiomatic
 - [ ] Add f16 variant
 - [ ] Add f128 variant (Use partial table set)
 - [ ] Add specified precision argument (current errol does this after but this is
   slows things down a fair bit).
 - [ ] Benchmark against current float printing code (memory
   consumption/performance).

