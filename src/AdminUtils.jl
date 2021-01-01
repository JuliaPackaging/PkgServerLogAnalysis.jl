using HTTP, JSON3

function get_server_list()
    replace.(JSON3.read(HTTP.get("https://pkg.julialang.org/meta/siblings").body), "https://" => "")
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

    # Chinese servers need a little different configuration
    if startswith("cn-", server)
        username = "centos"
        server = replace(server, "julialang.org" => "juliacn.com")
    end
    return "$(username)@$(server)"
end