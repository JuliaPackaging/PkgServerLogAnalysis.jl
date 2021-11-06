using HTTP, JSON3, PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list, get_ssh_creds

@info("Collecting server list...")
servers = get_server_list()
@info("About to update $(length(servers)) servers")
c = Channel(length(servers))

@async begin
    @sync begin
        for server in servers
            @async begin
                cmd = """
                source ~/.bash_profile
                cd ~/src/PkgServer.jl
                git pull

                if [[ -f deployment/.env ]]; then
                    make -C deployment
                elif [[ -f loadbalancer/.env ]]; then
                    make -C loadbalancer
                fi

                sudo chown \${UID}:\${UID} -R deployment/logs || true
                sudo chown \${UID}:\${UID} -R loadbalancer/logs || true

                downhomes
                rewg || true
                docker restart pkgserver_telegraf || true
                docker restart telegraf_telegraf || true
                """
                p = run(`ssh -A -t -o ConnectTimeout=5 -o ConnectionAttempts=2 -o StrictHostKeyChecking=no $(get_ssh_creds(server)) $(cmd)`; wait=false)
                wait(p)
                put!(c, (server, p))
            end
        end
    end
    close(c)
end


while isopen(c) || isready(c)
    server, p = take!(c)
    @info("update-$(server): $(success(p) ? "✓" : "✘")")
end
