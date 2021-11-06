using HTTP, JSON3, PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list, get_ssh_creds

for server in get_server_list()
    @info(server)
    cmd = """
    source ~/.bash_profile
    cd ~/src/PkgServer.jl
    git pull

    if [[ -f deployment/.env ]]; then
        make -C deployment
    elif [[ -f loadbalancer/.env ]]; then
        make -C loadbalancer
    fi

    downhomes
    docker restart pkgserver_telegraf || true
    """
    p = run(`ssh -t -o StrictHostKeyChecking=no $(get_ssh_creds(server)) $(cmd)`)
    @info("update-$(server): $(success(p) ? "✓" : "✘")")
end
