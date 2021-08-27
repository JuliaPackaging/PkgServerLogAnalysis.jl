using HTTP, JSON3, PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list, get_ssh_creds

for server in get_server_list()
    @info(server)
    cmd = """
    source ~/.bash_profile
    cd ~/src/PkgServer.jl/deployment
    git pull
    make
    """
    p = run(`ssh -t -o StrictHostKeyChecking=no $(get_ssh_creds(server)) $(cmd)`)
    @info("update-$(server): $(success(p) ? "✓" : "✘")")
end
