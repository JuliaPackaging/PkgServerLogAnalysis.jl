#!/usr/bin/env julia
using PkgServerLogAnalysis

hll_keyfile = popfirst!(ARGS)
PkgServerLogAnalysis.load_hll_key!(hll_keyfile)

work_queue = Channel{String}(length(ARGS))
put!.(Ref(work_queue), ARGS)
close(work_queue)
Threads.foreach(work_queue; ntasks=2*Threads.nthreads()) do f
    PkgServerLogAnalysis.parse_file(f)
end
