#!/usr/bin/env julia

import PkgServerLogAnalysis
import PkgServerLogAnalysis: CSV, BufferStream, decompress!, compress!

const servers = split(ENV["SERVERS"], ",")
const timeout = let t = Sys.which("timeout") !== nothing ? Sys.which("timeout") : Sys.which("gtimeout")
    t !== nothing ? `$t 300s` : ``
end
const hll_keyfile = ENV["HLL_KEY"]
const ephemeral_bucket = ENV["EPHEMERAL_BUCKET"]
const persistent_bucket = ENV["PERSISTENT_BUCKET"]

# Configure directories
const scratch_prefix = joinpath(DEPOT_PATH[1], "scratchspaces", "736c6f6f-5473-6973-796c-616e41676f4c")
const raw_log_dir = joinpath(scratch_prefix, "raw_logs")
const parsed_log_dir = joinpath(scratch_prefix, "raw_csvs")
const sanitized_log_dir = joinpath(scratch_prefix, "sanitized_csvs")
mkpath(raw_log_dir)
mkpath(parsed_log_dir)
mkpath(sanitized_log_dir)

# Cache file to avoid unnecessary S3 requests
const s3_cache_file = joinpath(scratch_prefix, "s3cache.csv")
const s3cache = isfile(s3_cache_file) ? Set(readlines(s3_cache_file)) : Set{String}()
@info "--- Restored $(length(s3cache)) entries from s3cache"

# Load the HLL keyfile
PkgServerLogAnalysis.load_hll_key!(hll_keyfile)


function rsync_logs(server)
    host = server * ".pkg.julialang.org"
    @info "--- Syncing remote logs from host $host"
    remote_user = "ubuntu"
    remote_log_dir = "~/apps/PkgServer.jl/loadbalancer/logs/nginx/access_*.gz"
    if startswith(server, "cn-")
        remote_user = "centos"
        remote_log_dir = "~/src/PkgServer.jl/deployment/logs/nginx/access_*.gz"
    end
    ssh = join(
        [
            "ssh",
            "-o UserKnownHostsFile=/dev/null",
            "-o StrictHostKeyChecking=no",
            "-o BatchMode=yes",
        ],
        " "
    )
    cmd = `$timeout rsync -rt -e $(ssh) $(remote_user)@$(host):$(remote_log_dir) $(raw_log_dir)`
    if run(ignorestatus(cmd)).exitcode != 0
        @warn "--- Syncing remote logs from host $(host) failed"
    end
    return
end

function sync_raw_logs()
    @info "--- Uploading raw logs to ephemeral S3 bucket"
    run(`aws s3 sync --no-progress --acl=private $(raw_log_dir) "s3://$(ephemeral_bucket)/raw/"`)
    return
end

struct LogFile
    key::String
end
raw_path(l::LogFile) = joinpath(raw_log_dir, l.key * ".gz")
parsed_path(l::LogFile) = joinpath(parsed_log_dir, l.key * ".csv.zst")
sanitized_path(l::LogFile) = joinpath(sanitized_log_dir, l.key * ".csv.zst")

parsed_s3_path(l::LogFile) = "s3://$(ephemeral_bucket)/csv/" * l.key * ".csv.zst"
sanitized_s3_path(l::LogFile) = "s3://$(persistent_bucket)/csv/" * l.key * ".csv.zst"

function exist_sanitized_in_s3(l::LogFile)
    if l.key in s3cache
        return true
    end
    key = "csv/" * l.key * ".csv.zst"
    @info "Checking S3 for $key"
    cmd = `aws s3api head-object --bucket $(persistent_bucket) --key $(key)`
    return success(pipeline(cmd; stdout = devnull, stderr = devnull))
end

function filter_processed_logs()
    local_logs = Set{String}(
        splitext(basename(f))[1] for f in readdir(raw_log_dir; join = true) if isfile(f) && endswith(f, ".gz")
    )
    files_to_parse = Channel{LogFile}(length(local_logs))
    queue = Channel{LogFile}(Inf) do ch
        for l in local_logs
            put!(ch, LogFile(l))
        end
    end
    Threads.foreach(queue; ntasks = 32) do f
        if !exist_sanitized_in_s3(f)
            put!(files_to_parse, f)
        end
    end
    close(files_to_parse)
    return local_logs, collect(files_to_parse)
end

function write_s3cache(keys)
    tmp = s3_cache_file * ".tmp"
    open(tmp, "w") do io
        for k in keys
            println(io, k)
        end
    end
    mv(tmp, s3_cache_file; force = true)
    return
end

# bin/parse_logfiles.jl
function parse_logfiles(logs_to_parse)
    work_queue = Channel{String}() do q
        for l in logs_to_parse
            put!(q, raw_path(l))
        end
    end
    Threads.foreach(work_queue; ntasks = 2 * Threads.nthreads()) do f
        PkgServerLogAnalysis.parse_file(f)
    end
    return
end

# bin/sanitize_csvs.jl
function sanitize_logfiles(logs_to_parse)
    work_queue = Channel{String}() do q
        for l in logs_to_parse
            put!(q, parsed_path(l))
        end
    end
    Threads.foreach(work_queue; ntasks = 2 * Threads.nthreads()) do filename
        outfile = joinpath(sanitized_log_dir, basename(filename))
        @info("Sanitizing $(basename(filename))")
        decompressed_io = BufferStream()
        open(filename, read = true) do compressed_io
            # Decompress/read the `.csv.zst` into memory
            decompress!(compressed_io, decompressed_io)
        end
        close(decompressed_io)

        # Purposefully drop `remote_addr`; this is part of our "sanitization" process
        comp_io = BufferStream()
        CSV.write(comp_io, CSV.Rows(read(decompressed_io); reusebuffer = true, drop = ["remote_addr"]))
        close(comp_io)

        # Re-compress the file back out onto disk
        open(outfile, write = true) do write_io
            compress!(comp_io, write_io)
        end
    end
    return
end

function s3_upload(logs_to_parse)
    work_queue = Channel{LogFile}() do q
        for l in logs_to_parse
            put!(q, l)
        end
    end
    Threads.foreach(work_queue; ntasks = 32) do f
        @info "Uploading $(parsed_path(f)) to $(parsed_s3_path(f))"
        run(`aws s3 cp --no-progress --acl=private $(parsed_path(f)) $(parsed_s3_path(f))`)
        @info "Uploading $(sanitized_path(f)) to $(sanitized_s3_path(f))"
        run(`aws s3 cp --no-progress --acl=private $(sanitized_path(f)) $(sanitized_s3_path(f))`)
    end
    return
end

function main()
    # Sync remote logs to local directory
    @sync for server in servers
        Threads.@spawn rsync_logs(server)
    end
    # Sync raw logs with ephemeral bucket on S3
    sync_raw_logs()
    # Filter out logs that we have already processed
    local_logs, logs_to_parse = filter_processed_logs()
    @info "Found $(length(local_logs)) local logs, $(length(logs_to_parse)) to parse"
    # Parse the files
    parse_logfiles(logs_to_parse)
    # Sanitize the files
    sanitize_logfiles(logs_to_parse)
    # Upload to S3
    s3_upload(logs_to_parse)
    # Cache all local logs — after upload, everything is in S3
    write_s3cache(local_logs)
    return
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
