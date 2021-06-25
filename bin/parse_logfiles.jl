#!/usr/bin/env julia
using PkgServerLogAnalysis

work_queue = Channel{String}(length(ARGS))
put!.(Ref(work_queue), ARGS)
close(work_queue)
Threads.foreach(work_queue; ntasks=2*Threads.nthreads()) do f
    PkgServerLogAnalysis.parse_file(f)
end
