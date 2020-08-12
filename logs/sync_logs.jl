#!/usr/bin/env julia

using JSON3, HTTP

# Get list of servers we're going to connect to
server_list = JSON3.read(String(HTTP.get("https://pkg.julialang.org/meta/siblings").body))
@info("Fetching logs from $(length(server_list)) servers...")

# Spin off a bunch of rsync calls
@sync begin
    procs = Dict()
    for server in server_list
        # Get the region code
        region = server[9:end-18]
        username = "ubuntu"

        # The chinese servers use centos, not Ubuntu, and we need to convert from julialang.org
        # to juliacn.com since HTTP forwarding doesn't work for SSH. :P
        server_address = "$(region).pkg.julialang.org"
        if startswith(region, "cn-")
            username = "centos"
            server_address = "$(region).pkg.juliacn.com"
        end
        @async begin
            p = run(`rsync -e "ssh -o StrictHostKeyChecking=no" -Pav "$(username)@$(server_address):~/src/PkgServerS3Mirror/logs/nginx/access_*.gz" ./`; wait=false)
            wait(p)
            result = success(p) ? "✓" : "✘"
            @info("Log sync from pkgserver-$(server_address): $(result)")
        end
    end
end
