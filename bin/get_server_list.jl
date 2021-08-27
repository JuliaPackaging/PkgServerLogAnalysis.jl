using PkgServerLogAnalysis
using PkgServerLogAnalysis: get_server_list

for server in PkgServerLogAnalysis.get_server_list()
    println(server)
end
