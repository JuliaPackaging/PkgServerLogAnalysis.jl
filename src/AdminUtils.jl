using HTTP, JSON3

function get_server_list()
    function interrogate_server(server::String)
        # First, check to see if this server has any children
        children = try
            JSON3.read(HTTP.get(string(server, "/meta/children")).body)
        catch
            String[]
        end

        future_servers_to_interrogate = String[]
        canonical_servers = String[]

        # If we have children, we know we're a loadbalancer, so just use this URL as the canonical address:
        if !isempty(children)
            future_servers_to_interrogate = collect(children)
            canonical_servers = String[server]
        else
            # If we're not a loadbalancer, get our canonical address from `/meta`:
            meta = try
                JSON3.read(HTTP.get(string(server, "/meta")).body)
            catch
                @error("pkgserver failed to respond to /meta", server)
                Dict{String,String}()
            end
            if !isempty(meta)
                canonical_servers = String[meta["pkgserver_url"]]
            end
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
    username = "ubuntu"

    # Chinese servers use the username `centos`
    if startswith(server, "cn-")
        username = "centos"
    end
    return "$(username)@$(server)"
end
