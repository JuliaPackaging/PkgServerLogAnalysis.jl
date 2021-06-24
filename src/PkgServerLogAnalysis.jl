module PkgServerLogAnalysis

export parse_logfiles, hist

using SimpleBufferStream, CSV, Tables, Printf, Sockets, Dates, Scratch, SHA

include("AdminUtils.jl")
include("compression.jl")
include("parsing.jl")

function hit_filecache(collator::Function, src_filename::String, cleanup::Bool = true)
    dst_filename = joinpath(@get_scratch!("csv_cache"), string(bytes2hex(sha256(src_filename)[1:div(end,2)]), ".csv.zst"))
    if stat(dst_filename).mtime < stat(src_filename).mtime
        try
            @info("Parsing $(basename(src_filename))")
            data = open(io -> collator(io), src_filename)
            @info("Saving it out to <scratch space>/$(basename(dst_filename))")
            open(dst_filename, "w") do dst_io
                comp_io = BufferStream()
                t_comp = @async compress!(comp_io, dst_io)
                CSV.write(comp_io, data)
                close(comp_io)
                wait(t_comp)
            end
        catch e
            cleanup && rm(dst_filename; force=true)
            rethrow(e)
        end
    end

    # If it already exists, decompress it into a CSV.File
    @info("Loading cached $(dst_filename)")
    decomp_io = BufferStream()
    try
        open(dst_filename) do io
            decompress!(io, decomp_io)
        end
    catch
        @error("Decompressing $(dst_filename) failed, re-parsing!")
        rm(dst_filename)
        return hit_filecache(collator, src_filename, cleanup)
    finally
        close(decomp_io)
    end
    return CSV.File(read(decomp_io))
end

function parse_file(filename::AbstractString)
    hit_filecache(filename) do maybe_compressed_io
        local io
        io = BufferStream()
        @async decompress!(maybe_compressed_io, io)
        parsed_lines = NamedTuple[]
        while !eof(io)
            parsed = parse_log_line(readline(io), filename)
            if parsed !== nothing
                push!(parsed_lines, parsed)
            end
        end
        if isempty(parsed_lines)
            return NamedTuple[]
        else
            return Tables.columntable(parsed_lines)
        end
    end
end

const date_df = DateFormat("yyyymmdd")
is_access_log(f::String) = match(r"^access_.*\.pkg\.julia.*\.((gz)|(zst))", basename(f)) !== nothing
function is_recent(f::String, days::Int)
    m = match(r".*-(\d+).((gz)|(zst))", f)
    if m === nothing
        return false
    end
    return Dates.days(now() - parse(DateTime, m.captures[1], date_df)) < days
end

# By default, we look at one week of data plus two days, since we usually throw out
# the first and last days, to account for bad timezone overlaps.
function parse_logfiles(;criteria::Function = f -> is_access_log(f) && is_recent(f, 31+2),
                        dir::AbstractString = @get_scratch!("logs"),
                        collect_results::Bool = true)
    results_lock = ReentrantLock()
    parsed = []

    logfiles = filter(criteria, readdir(dir; join=true))
    work_queue = Channel{String}(length(logfiles))
    put!.(Ref(work_queue), logfiles)
    close(work_queue)
    Threads.foreach(work_queue; ntasks=2*Threads.nthreads()) do f
        d = parse_file(f)
        if collect_results
            lock(results_lock) do
                append!(parsed, d)
            end
        end
    end
    return parsed
end

end
