#!/usr/bin/env julia

using JSON3, HTTP, PkgServerLogAnalysis, Scratch
using PkgServerLogAnalysis: get_server_list, get_ssh_creds, run_with_output

verbose = "--verbose" in ARGS

# Get list of servers we're going to connect to
server_list = replace.(get_server_list(), "https://" => "")
logsdir = @get_scratch!("logs")
@info("Fetching logs from $(length(server_list)) servers into $(logsdir)...")

# Spin off a bunch of rsync calls
@sync begin
    procs = Dict()
    for server in server_list
        remote_logs = "~/apps/PkgServer.jl/loadbalancer/logs/nginx/access_*.gz"
        if "https://cn-" in server
            remote_logs = "~/src/PkgServer.jl/deployment/logs/nginx/access_*.gz"
        end
        @async begin
            ssh_options = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR"
            creds = get_ssh_creds(server)
            p, stdout, stderr = run_with_output(
                `rsync -e $(ssh_options) -Pav "$(creds):$(remote_logs)" $(logsdir)`
            )
            @info("Log sync from pkgserver-$(server): $(success(p) ? "✓" : "✘")", creds)
            if !success(p)
                @warn("stdout: $(stdout)")
                @warn("stderr: $(stderr)")
            elseif verbose
                println(stdout)
            end
        end
    end
end
