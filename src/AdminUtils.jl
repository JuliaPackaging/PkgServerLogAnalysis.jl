using HTTP, JSON3

function get_server_list()
    # Get the server list from the current default pkgserver
    siblings = replace.(JSON3.read(HTTP.get("https://pkg.julialang.org/meta/siblings").body), "https://" => "")

    # Go and ask each indifvidual sibling what it thinks its canonical URL is, in the case of redirects
    c = Channel(length(siblings))
    @info("Canonicalizing $(length(siblings)) server hostnames...")
    @sync for sibling in siblings
        @async begin
            @info(sibling)
            try
                meta = JSON3.read(HTTP.get("https://$(sibling)/meta").body)
                put!(c, replace(meta["pkgserver_url"], "https://" => ""))
            catch
                @warn("Unable to canonicalize", sibling)
                put!(c, sibling)
            end
        end
    end
    close(c)
    return collect(c)
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
