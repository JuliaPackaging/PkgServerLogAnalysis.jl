#!/usr/bin/env julia
using PkgServerLogAnalysis
import PkgServerLogAnalysis: CSV, BufferStream, decompress!, compress!

# Take `output_dir` as the first argument we're given
output_dir = popfirst!(ARGS)
if ispath(output_dir) && !isdir(output_dir)
    println(stderr, "Usage: sanitize_csvs.jl <output_dir> <csv_files...>")
end
mkpath(output_dir)

#work_queue = Channel{String}(length(ARGS))
#put!.(Ref(work_queue), ARGS)
#close(work_queue)
#Threads.foreach(work_queue; ntasks=Threads.nthreads()) do filename
for filename in ARGS
    outfile = joinpath(output_dir, basename(filename))
    @info("Sanitizing $(basename(filename))")
    decompressed_io = BufferStream()
    open(filename, read=true) do compressed_io
        # Decompress/read the `.csv.zst` into memory
        decompress!(compressed_io, decompressed_io)
    end
    @info("decompressed")

    # Purposefully drop `remote_addr`; this is part of our "sanitization" process
    sanitized_data = CSV.File(read(decompressed_io); drop=["remote_addr"])
    @info("dropped")

    # Re-compress the file back out onto disk
    comp_io = BufferStream()
    CSV.write(comp_io, sanitized_data)
    @info("written")

    open(outfile, write=true) do write_io
        compress!(comp_io, write_io)
        @info("compressed")
        close(comp_io)
    end
end
