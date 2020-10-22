using PkgServerLogAnalysis
using Artifacts, CSV, Dates, Test

@testset "parse_log_line" begin
    # /package line with ipv4 and $time_local format
    l = "14.176.79.196 [06/Nov/2020:20:00:14 +0000] \"GET /package/d8e11817-5142-5d16-987a-aa16d5891078/b51f894272d996c9857577f3e8d3a8d69df22caa HTTP/1.1\" 200 147755 \"libcurl/7.71.1 mbedTLS/2.16.8 zlib/1.2.11 libssh2/1.9.0 nghttp2/1.40.0 julia/1.6.0-DEV.1278\" 0.027 1.6.0-DEV.1278 x86_64-apple-darwin18-libgfortran5-julia_version+1.6.0 \"APPVEYOR=n;CI=n;CI_SERVER=n;CIRCLECI=n;CONTINUOUS_INTEGRATION=n;GITHUB_ACTIONS=n;GITLAB_CI=n;JULIA_CI=n;JULIA_PKGEVAL=n;JULIA_REGISTRYCI_AUTOMERGE=n;TF_BUILD=n;TRAVIS=n\" true \"eu-central.pkg.julialang.org\""
    p = PkgServerLogAnalysis.parse_log_line(l, "access_eu-central.pkg.julialang.org.log")
    @test p.remote_addr == "14.176.79.196"
    @test p.time_utc == "2020-11-06T20:00:14"
    @test p.request == "GET /package/d8e11817-5142-5d16-987a-aa16d5891078/b51f894272d996c9857577f3e8d3a8d69df22caa HTTP/1.1"
    @test p.request_method == "GET"
    @test p.request_url == "/package/d8e11817-5142-5d16-987a-aa16d5891078/b51f894272d996c9857577f3e8d3a8d69df22caa"
    @test p.package == "/package/d8e11817-5142-5d16-987a-aa16d5891078/b51f894272d996c9857577f3e8d3a8d69df22caa"
    @test p.package_uuid == "d8e11817-5142-5d16-987a-aa16d5891078"
    @test p.package_hash == "b51f894272d996c9857577f3e8d3a8d69df22caa"
    @test p.artifact === missing
    @test p.artifact_hash === missing
    @test p.registry === missing
    @test p.registry_uuid === missing
    @test p.registry_hash === missing
    @test p.request_http == "HTTP/1.1"
    @test p.status == 200
    @test p.body_bytes_sent == 147755
    @test p.http_user_agent == "libcurl/7.71.1 mbedTLS/2.16.8 zlib/1.2.11 libssh2/1.9.0 nghttp2/1.40.0 julia/1.6.0-DEV.1278"
    @test p.request_time == 0.027
    @test p.julia_version == "1.6.0-DEV.1278"
    @test p.julia_system == "x86_64-apple-darwin18-libgfortran5-julia_version+1.6.0"
    @test p.julia_ci_variables == "APPVEYOR=n;CI=n;CI_SERVER=n;CIRCLECI=n;CONTINUOUS_INTEGRATION=n;GITHUB_ACTIONS=n;GITLAB_CI=n;JULIA_CI=n;JULIA_PKGEVAL=n;JULIA_REGISTRYCI_AUTOMERGE=n;TF_BUILD=n;TRAVIS=n"
    @test p.julia_interactive == true
    @test p.julia_pkg_server == "eu-central.pkg.julialang.org"
    @test p.pkgserver == "eu-central"

    # /package line with ipv6, $time_local format with offset and 404 status
    l = "2001:db8::8a2e:370:7334 [28/Oct/2020:01:05:00 +0230] \"GET /artifact/2b4232945204cdceaa254c800d4027e3f011dca7 HTTP/1.1\" 404 5 \"Pkg.jl (https://github.com/JuliaLang/Pkg.jl)\" 0.158 1.5.1 x86_64-w64-mingw32-libgfortran5-cxx11 \"APPVEYOR=n;CI=n;CI_SERVER=n;CIRCLECI=n;CONTINUOUS_INTEGRATION=n;GITHUB_ACTIONS=n;GITLAB_CI=n;JULIA_CI=n;JULIA_PKGEVAL=n;JULIA_REGISTRYCI_AUTOMERGE=n;TF_BUILD=n;TRAVIS=n\" false \"-\""
    p = PkgServerLogAnalysis.parse_log_line(l)
    @test p.remote_addr == "2001:db8::8a2e:370:7334"
    @test p.time_utc == "2020-10-27T22:35:00"
    @test p.request == "GET /artifact/2b4232945204cdceaa254c800d4027e3f011dca7 HTTP/1.1"
    @test p.request_method == "GET"
    @test p.request_url == "/artifact/2b4232945204cdceaa254c800d4027e3f011dca7"
    @test p.package === missing
    @test p.package_uuid === missing
    @test p.package_hash === missing
    @test p.artifact == "/artifact/2b4232945204cdceaa254c800d4027e3f011dca7"
    @test p.artifact_hash == "2b4232945204cdceaa254c800d4027e3f011dca7"
    @test p.registry === missing
    @test p.registry_uuid === missing
    @test p.registry_hash === missing
    @test p.request_http == "HTTP/1.1"
    @test p.status == 404
    @test p.body_bytes_sent == 5
    @test p.http_user_agent == "Pkg.jl (https://github.com/JuliaLang/Pkg.jl)"
    @test p.request_time == 0.158
    @test p.julia_version == "1.5.1"
    @test p.julia_system == "x86_64-w64-mingw32-libgfortran5-cxx11"
    @test p.julia_ci_variables == "APPVEYOR=n;CI=n;CI_SERVER=n;CIRCLECI=n;CONTINUOUS_INTEGRATION=n;GITHUB_ACTIONS=n;GITLAB_CI=n;JULIA_CI=n;JULIA_PKGEVAL=n;JULIA_REGISTRYCI_AUTOMERGE=n;TF_BUILD=n;TRAVIS=n"
    @test p.julia_interactive == false
    @test p.julia_pkg_server === missing
    @test p.pkgserver === missing

    # /registry line with $time_iso8601 format
    l = "212.181.25.47 [2020-11-02T18:31:41+00:00] \"GET /registry/23338594-aafe-5451-b93e-139f81909106/b5230a91f1429fb5f11e589305d567f2756ad1b3 HTTP/1.1\" 200 2319449 \"libcurl/7.71.1 mbedTLS/2.16.8 brotli/1.0.9 libssh2/1.9.0_DEV julia/1.6.0-DEV.1284\" 1.546 1.6.0-DEV.1284 x86_64-linux-gnu-libgfortran5-libstdcxx28-cxx11-julia_version+1.6.0 \"APPVEYOR=n;CI=n;CI_SERVER=n;CIRCLECI=n;CONTINUOUS_INTEGRATION=n;GITHUB_ACTIONS=n;GITLAB_CI=n;JULIA_CI=n;JULIA_PKGEVAL=n;JULIA_REGISTRYCI_AUTOMERGE=n;TF_BUILD=n;TRAVIS=n\" false \"-\""
    p = PkgServerLogAnalysis.parse_log_line(l)
    @test p.remote_addr == "212.181.25.47"
    @test p.time_utc == "2020-11-02T18:31:41"
    @test p.request == "GET /registry/23338594-aafe-5451-b93e-139f81909106/b5230a91f1429fb5f11e589305d567f2756ad1b3 HTTP/1.1"
    @test p.request_method == "GET"
    @test p.request_url == "/registry/23338594-aafe-5451-b93e-139f81909106/b5230a91f1429fb5f11e589305d567f2756ad1b3"
    @test p.package === missing
    @test p.package_uuid === missing
    @test p.package_hash === missing
    @test p.artifact === missing
    @test p.artifact_hash === missing
    @test p.registry == "/registry/23338594-aafe-5451-b93e-139f81909106/b5230a91f1429fb5f11e589305d567f2756ad1b3"
    @test p.registry_uuid == "23338594-aafe-5451-b93e-139f81909106"
    @test p.registry_hash == "b5230a91f1429fb5f11e589305d567f2756ad1b3"
    @test p.request_http == "HTTP/1.1"
    @test p.status == 200
    @test p.body_bytes_sent == 2319449
    @test p.http_user_agent == "libcurl/7.71.1 mbedTLS/2.16.8 brotli/1.0.9 libssh2/1.9.0_DEV julia/1.6.0-DEV.1284"
    @test p.request_time == 1.546
    @test p.julia_version == "1.6.0-DEV.1284"
    @test p.julia_system == "x86_64-linux-gnu-libgfortran5-libstdcxx28-cxx11-julia_version+1.6.0"
    @test p.julia_ci_variables == "APPVEYOR=n;CI=n;CI_SERVER=n;CIRCLECI=n;CONTINUOUS_INTEGRATION=n;GITHUB_ACTIONS=n;GITLAB_CI=n;JULIA_CI=n;JULIA_PKGEVAL=n;JULIA_REGISTRYCI_AUTOMERGE=n;TF_BUILD=n;TRAVIS=n"
    @test p.julia_interactive == false
    @test p.julia_pkg_server === missing
    @test p.pkgserver === missing

    # line with $time_iso8601 format with offset and non-(package|artifact|registry) URL
    l = "212.181.25.47 [2020-11-02T18:31:41-02:30] \"GET /meta HTTP/1.1\" 200 123 \"Pkg.jl\" 1.546 1.5.2 x86_64-linux-gnu \"APPVEYOR=n\" false \"-\""
    p = PkgServerLogAnalysis.parse_log_line(l)
    @test p.remote_addr == "212.181.25.47"
    @test p.time_utc == "2020-11-02T21:01:41"
    @test p.request == "GET /meta HTTP/1.1"
    @test p.request_method == "GET"
    @test p.request_url == "/meta"
    @test p.package === missing
    @test p.package_uuid === missing
    @test p.package_hash === missing
    @test p.artifact === missing
    @test p.artifact_hash === missing
    @test p.registry === missing
    @test p.registry_uuid === missing
    @test p.registry_hash === missing
    @test p.request_http == "HTTP/1.1"
    @test p.status == 200
    @test p.body_bytes_sent == 123
    @test p.http_user_agent == "Pkg.jl"
    @test p.request_time == 1.546
    @test p.julia_version == "1.5.2"
    @test p.julia_system == "x86_64-linux-gnu"
    @test p.julia_ci_variables == "APPVEYOR=n"
    @test p.julia_interactive == false
    @test p.julia_pkg_server === missing
    @test p.pkgserver === missing
end # testset


@testset "load anonymized_test_data" begin
    datafile = joinpath(artifact"anonymized_test_data", "anonymized_test_data.log")
    dataset = PkgServerLogAnalysis.parse_file(datafile)
    # Run some smoke tests
    @test dataset isa CSV.File
    @test length(dataset) == 21222
    @test dataset.time_utc isa Vector{DateTime}
    @test dataset.status isa Vector{Int}
    @test dataset.request_url isa Vector{String}
    @test dataset.julia_interactive isa Vector{Bool}
    @test dataset.body_bytes_sent isa Vector{Int}
    @test dataset.request_time isa Vector{Float64}
end
