using HTTP, JSON3, PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list, get_ssh_creds

for server in PkgServerLogAnalysis.get_server_list()
    @info(server)
    p = run(`ssh -t -o StrictHostKeyChecking=no $(get_ssh_creds(server)) "source ~/.bash_profile; cd ~/src/PkgServer.jl/deployment; git pull; make"`)
    @info("update-$(server): $(success(p) ? "✓" : "✘")")
end
