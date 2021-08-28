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
    open(outfile, write=true) do write_io
        open(filename, read=true) do compressed_io
            @info("Sanitizing $(basename(filename))")
            # Decompress/read the `.csv.zst` into memory
            decompressed_io = BufferStream()
            @async decompress!(compressed_io, decompressed_io)

            # Purposefully drop `remote_addr`; this is part of our "sanitization" process
            sanitized_data = CSV.File(read(decompressed_io); drop=["remote_addr"])

            # Re-compress the file back out onto disk
            comp_io = BufferStream()
            CSV.write(comp_io, sanitized_data)
            compress!(comp_io, write_io)
            close(comp_io)
        end
    end
end
