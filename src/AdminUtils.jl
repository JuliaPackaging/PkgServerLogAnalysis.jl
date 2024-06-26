using HTTP, JSON3

function get_server_list()
    function interrogate_server(server::String)
        # First, check to see if this server has any children
        children = try
            JSON3.read(HTTP.get(string(server, "/meta/children"); readtimeout=10).body)
        catch
            String[]
        end
        #@info("Children", server, length(children))

        # Query if this is a new-style Cloudflare-loadbalancer by checking if the final
        # redirect goes to storage.julialang.net when requesting Example@0.5.3
        is_cf_lb(server) = try
            uuid = "7876af07-990d-54b4-ab0e-23690620f79a"
            tree_sha1 = "46e44e869b4d90b96bd8ed1fdcf32244fddfb6cc"
            req = HTTP.head(string(server, "/package/$(uuid)/$(tree_sha1)"); readtimeout=10)
            HTTP.header(req.request, "Host") == "storage.julialang.net"
        catch
            false
        end

        future_servers_to_interrogate = String[]
        canonical_servers = String[]

        # If we have children, we know we're an old-style loadbalancer, so just use this URL as the canonical address:
        if !isempty(children)
            future_servers_to_interrogate = collect(children)
            canonical_servers = String[server]
        elseif isempty(children) && is_cf_lb(server)
            # No (public) children and redirecting to Cloudflare: get logs from the loadbalancer
            canonical_servers = String[server]
        else
            # If we're not a loadbalancer, get our canonical address from `/meta`:
            meta = try
                JSON3.read(HTTP.get(string(server, "/meta"); connect_timeout=10, readtimeout=10).body)
            catch e
                @warn("pkgserver failed to respond to /meta", server, e)

                # If we can't canonicalize, just use the URL we originally tried
                Dict{String,String}("pkgserver_url" => server)
            end
            canonical_servers = String[meta["pkgserver_url"]]
        end

        return future_servers_to_interrogate, canonical_servers
    end

    # Get the initial sibling list from the current default pkgserver
    servers_to_interrogate = JSON3.read(HTTP.get("https://pkg.julialang.org/meta/siblings").body)

    servers = Channel{String}(10*length(servers_to_interrogate))
    while !isempty(servers_to_interrogate)
        next_servers_to_interrogate = Channel{String}(10*length(servers_to_interrogate))

        # For each server we need to interrogate, launch a task in parallel
        @sync begin
            for server in servers_to_interrogate
                @async begin
                    new_servers, done_servers = interrogate_server(server)
                    put!.(Ref(next_servers_to_interrogate), new_servers)
                    put!.(Ref(servers), done_servers)
                end
            end
        end
        close(next_servers_to_interrogate)
        servers_to_interrogate = collect(next_servers_to_interrogate)
    end
    close(servers)
    return sort(collect(servers))
end

"""
    run_with_output(cmd)

Run a command, returning the `Process` object as well as `stdout` and `stderr`
"""
function run_with_output(cmd::Cmd, timeout = 600.0, term_timeout = 10.0)
    out = Pipe()
    err = Pipe()
    process = run(pipeline(detach(cmd), stdout=out, stderr=err); wait=false)
    close(out.in)
    close(err.in)

    # Start asynchronous task to get all stdout and stderr data
    out_task = @async String(read(out))
    err_task = @async String(read(err))
    wait(process)
    return process, fetch(out_task), fetch(err_task)
end

function get_ssh_creds(server)
    server = replace(server, "https://" => "")
    username = "ubuntu"

    # Chinese servers use the username `centos`
    if startswith(server, "cn-")
        username = "centos"
    end
    return "$(username)@$(server)"
end
