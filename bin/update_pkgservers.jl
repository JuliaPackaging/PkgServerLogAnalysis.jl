using HTTP, JSON3, PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list, get_ssh_creds

for server in PkgServerLogAnalysis.get_server_list()
    @info(server)
    cmd = """
    source ~/.bash_profile
    cd ~/src/PkgServer.jl/deployment
    git pull
    sudo chown --reference=../Project.toml -R .
    cd deployment
    make
    """
    p = run(`ssh -t -o StrictHostKeyChecking=no $(get_ssh_creds(server)) $(cmd)`)
    @info("update-$(server): $(success(p) ? "✓" : "✘")")
end
