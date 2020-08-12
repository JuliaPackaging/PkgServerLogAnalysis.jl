### A Pluto.jl notebook ###
# v0.12.4

using Markdown
using InteractiveUtils

# ╔═╡ 8ad134e0-1000-11eb-13cc-99efc9c36e1e
using PkgServerLogAnalysis, Artifacts

# ╔═╡ 976f3562-1000-11eb-23ee-a97c80a2ab33
# This slash-indexing requires Julia 1.6, if you can't use Julia 1.6 do the `joinpath()` manually
data = PkgServerLogAnalysis.parse_file(artifact"anonymized_test_data/anonymized_test_data.log");

# ╔═╡ 2841a9c6-1001-11eb-2ca6-d94d298378e4
function fetch_fields(fieldname)
	return [d[fieldname] for d in data if d[fieldname] !== missing]
end;

# ╔═╡ 09e54938-1001-11eb-0620-3535cb7900ec
"$(length(unique(fetch_fields(:remote_addr)))) unique IPs in dataset"

# ╔═╡ 15b1bdf0-1001-11eb-3d06-1f5310b20836
"$(length(unique(fetch_fields(:package_uuid)))) unique packages in dataset"

# ╔═╡ Cell order:
# ╠═8ad134e0-1000-11eb-13cc-99efc9c36e1e
# ╠═976f3562-1000-11eb-23ee-a97c80a2ab33
# ╠═2841a9c6-1001-11eb-2ca6-d94d298378e4
# ╠═09e54938-1001-11eb-0620-3535cb7900ec
# ╠═15b1bdf0-1001-11eb-3d06-1f5310b20836
