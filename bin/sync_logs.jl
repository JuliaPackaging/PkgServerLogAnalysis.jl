#!/usr/bin/env julia

using JSON3, HTTP, PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list, get_ssh_creds, run_with_output

verbose = "--verbose" in ARGS

# Get list of servers we're going to connect to
server_list = get_server_list()
logsdir = abspath(joinpath(dirname(@__DIR__), "logs"))
@info("Fetching logs from $(length(server_list)) servers into $(logsdir)...")

# Spin off a bunch of rsync calls
@sync begin
    procs = Dict()
    for server in server_list
        @async begin
            ssh_options = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
            remote_logs = "~/src/PkgServer.jl/deployment/logs/nginx/access_*.gz"
            p, stdout, stderr = run_with_output(
                `rsync -e $(ssh_options) -Pav "$(get_ssh_creds(server)):$(remote_logs)" $(logsdir)`
            )
            @info("Log sync from pkgserver-$(server): $(success(p) ? "✓" : "✘")")
            if !success(p) && verbose
                @warn("stdout: $(stdout)")
                @warn("stderr: $(stderr)")
            end
        end
    end
end
