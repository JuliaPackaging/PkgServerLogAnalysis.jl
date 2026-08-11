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
const s3cache_lock = ReentrantLock()
@info "--- Restored $(length(s3cache)) entries from s3cache"

# Load the HLL keyfile
PkgServerLogAnalysis.load_hll_key!(hll_keyfile)


# Verify that AWS credentials are available before doing any work. Note that a
# credential failure in exist_sanitized_in_s3 is indistinguishable from a
# missing object, so without this check the whole pipeline would run only to
# fail at the upload steps.
function check_aws_credentials()
    @info "--- Checking AWS credentials"
    cmd = `aws sts get-caller-identity`
    if !success(pipeline(cmd; stdout = devnull))
        error("AWS credentials check failed (`aws sts get-caller-identity`)")
    end
    return
end

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

struct LogFile
    key::String
end
raw_path(l::LogFile) = joinpath(raw_log_dir, l.key * ".gz")
parsed_path(l::LogFile) = joinpath(parsed_log_dir, l.key * ".csv.zst")
sanitized_path(l::LogFile) = joinpath(sanitized_log_dir, l.key * ".csv.zst")

raw_s3_path(l::LogFile) = "s3://$(ephemeral_bucket)/raw/" * l.key * ".gz"
parsed_s3_path(l::LogFile) = "s3://$(ephemeral_bucket)/csv/" * l.key * ".csv.zst"
sanitized_s3_path(l::LogFile) = "s3://$(persistent_bucket)/csv/" * l.key * ".csv.zst"

is_cached(l::LogFile) = @lock s3cache_lock l.key in s3cache

# Record a fully processed log in the cache, both in memory and on disk
function record_processed!(l::LogFile)
    @lock s3cache_lock begin
        if !(l.key in s3cache)
            push!(s3cache, l.key)
            open(s3_cache_file, "a") do io
                println(io, l.key)
            end
        end
    end
    return
end

function exist_sanitized_in_s3(l::LogFile)
    key = "csv/" * l.key * ".csv.zst"
    @info "Checking S3 for $key"
    cmd = `aws s3api head-object --bucket $(persistent_bucket) --key $(key)`
    return success(pipeline(cmd; stdout = devnull, stderr = devnull))
end

# bin/sanitize_csvs.jl
function sanitize_logfile(l::LogFile)
    filename = parsed_path(l)
    outfile = sanitized_path(l)
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
    return
end

# Run the full pipeline for a single log file: upload the raw log, parse it,
# sanitize it, upload the results and finally record it in the cache.
function process_logfile(l::LogFile)
    # Skip if this log has already been fully processed in a previous run
    if is_cached(l)
        return
    end
    if exist_sanitized_in_s3(l)
        record_processed!(l)
        return
    end
    # Upload the raw log to the ephemeral S3 bucket
    @info "Uploading $(raw_path(l)) to $(raw_s3_path(l))"
    run(`aws s3 cp --no-progress --acl=private $(raw_path(l)) $(raw_s3_path(l))`)
    # Parse the file
    PkgServerLogAnalysis.parse_file(raw_path(l))
    # Sanitize the file
    sanitize_logfile(l)
    # Upload parsed and sanitized files to S3
    @info "Uploading $(parsed_path(l)) to $(parsed_s3_path(l))"
    run(`aws s3 cp --no-progress --acl=private $(parsed_path(l)) $(parsed_s3_path(l))`)
    @info "Uploading $(sanitized_path(l)) to $(sanitized_s3_path(l))"
    run(`aws s3 cp --no-progress --acl=private $(sanitized_path(l)) $(sanitized_s3_path(l))`)
    # Everything for this log is now in S3
    record_processed!(l)
    return
end

function process_logs()
    local_logs = sort!(
        [
            splitext(basename(f))[1] for f in readdir(raw_log_dir; join = true)
            if isfile(f) && endswith(f, ".gz")
        ]
    )
    @info "Found $(length(local_logs)) local logs"
    queue = Channel{LogFile}(Inf) do ch
        for key in local_logs
            put!(ch, LogFile(key))
        end
    end
    nfailed = Threads.Atomic{Int}(0)
    Threads.foreach(queue; ntasks = 2 * Threads.nthreads()) do l
        try
            process_logfile(l)
        catch e
            Threads.atomic_add!(nfailed, 1)
            @error "Processing $(l.key) failed" exception = (e, catch_backtrace())
        end
    end
    return nfailed[]
end

function main()
    # Fail fast on missing/expired AWS credentials
    check_aws_credentials()
    # Sync remote logs to local directory
    @sync for server in servers
        Threads.@spawn rsync_logs(server)
    end
    # Process each log file (upload raw, parse, sanitize, upload results)
    nfailed = process_logs()
    # Individual failures don't abort the queue, but the job as a whole should
    # still fail loudly if anything went wrong
    if nfailed > 0
        error("Processing failed for $(nfailed) logfile(s), see logs above")
    end
    return
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
