### A Pluto.jl notebook ###
# v0.14.7

using Markdown
using InteractiveUtils

# ╔═╡ 830b9254-0f0f-11eb-2413-1bee87660bb8
using WebCacheUtilities, PkgServerLogAnalysis, CSV, Sockets, Dates, Printf, Plots, Pkg, Scratch

# ╔═╡ b0c79334-0f0f-11eb-31b7-6b7fb9d3c2ea
begin
	# Load data from logs
	raw_data = parse_logfiles();
	# Load CI IP prefixes
	ci_pxs = ci_prefixes_by_provider();
end

# ╔═╡ 35b616e2-0f1d-11eb-114f-43b4e3c4a3a7
begin
	is_ci_ip(row::CSV.Row) = is_ci_ip(row.remote_addr)
	is_ci_ip(ip::String) = is_ci_ip(parse(IPAddr, ip))
	is_ci_ip(ip::IPAddr) = find_provider(ci_pxs, ip) != "<unknown>"
	
	is_pkg_download(row::CSV.Row) = startswith(row.request_url, "/package")
	is_art_download(row::CSV.Row) = startswith(row.request_url, "/artifact")
end

# ╔═╡ 27f20b7e-0f1f-11eb-0946-7961458506fc
function partition(criteria::Function, data::Vector)
	outputs = Dict{Any,Vector{CSV.Row}}()
	for d in data
		c = criteria(d)
		if !haskey(outputs, c)
			outputs[c] = CSV.Row[]
		end
		push!(outputs[c], d)
	end
	return outputs
end

# ╔═╡ f18edd54-0f10-11eb-3320-a7ded568fb2b
begin
	@info("Partitioning data...")
	# Split CI hits out, and keep only package downloads
	part_raw_pkg_data = filter(is_pkg_download, raw_data)
	part_raw_pkg_data = partition(is_ci_ip, part_raw_pkg_data)
	pkg_data = get(part_raw_pkg_data, false, CSV.Row[])
	ci_pkg_data = get(part_raw_pkg_data, true, CSV.Row[])

	part_raw_art_data = filter(is_art_download, raw_data)
	part_raw_art_data = partition(is_ci_ip, part_raw_art_data)
	art_data = get(part_raw_art_data, false, CSV.Row[])
	ci_art_data = get(part_raw_art_data, true, CSV.Row[])
end;

# ╔═╡ d661b24c-0f1d-11eb-2494-2dae16fc399f
display("Pkg CI hits: $(length(ci_pkg_data)), other hits: $(length(pkg_data))");
display("Artifact CI hits: $(length(ci_art_data)), other hits: $(length(art_data))");

# ╔═╡ bfac967c-0fd4-11eb-306e-4bfc20cb9b8f
begin
	@info("Building UUID -> name map...")
	Pkg.Registry.update()
	package_uuid_maps = Dict(
		r => Pkg.Types.read_registry(joinpath(r.path, "Registry.toml"))["packages"] for r in Pkg.Types.collect_registries()
	)
	function get_package_name(uuid::String)
		for (r, map) in package_uuid_maps
			if haskey(map, uuid)
				return map[uuid]["name"]
			end
		end
		return missing
	end
end

# ╔═╡ 9b069834-0fe0-11eb-331f-a78263f9ebf7
get_package_name(x) = missing

# ╔═╡ 0053a8e8-0f33-11eb-27e9-e7f200e56661
begin
	df = DateFormat("d/u/y:H:M:S")
	get_monthday(row::CSV.Row) = get_monthday(row.time_utc)
	get_monthday(dt::DateTime) = @sprintf("%02d/%02d", month(dt), day(dt))
end

# ╔═╡ 997b5fa2-0f1f-11eb-3aba-11a16b36c946
begin
	@info("Filtering and counting...")
	# We purposefully exclude the first and last day to avoid timezone boundary issues
	days_to_plot = sort(collect(Set(get_monthday(r) for r in pkg_data)))[2:end-1]
	pkg_data_time_filtered = filter(r -> get_monthday(r) ∈ days_to_plot, pkg_data)
	art_data_time_filtered = filter(r -> get_monthday(r) ∈ days_to_plot, art_data)
	
	# Next, split by package UUID and quickly calculate total downloads
	data_by_uuid = partition(d -> d.package_uuid, pkg_data_time_filtered);
	uuid_downloads = sort([u => length(data_by_uuid[u]) for u in keys(data_by_uuid)], by = k -> -k.second)

	# Count artifacts by hash
	art_by_hash = partition(d -> d.artifact_hash, art_data_time_filtered)
	hash_downloads = sort([h => length(art_by_hash[h]) for h in keys(art_by_hash)], by = k -> -k.second)
end

# ╔═╡ 8e490634-1230-11eb-27a5-3b7c9111e1f9
output_path = @get_scratch!("output")

# ╔═╡ d8e42340-1230-11eb-1ac1-db5dcad52696
output_name = "$(month(now()))-$(day(now()))"

# ╔═╡ a6b95bd4-1234-11eb-22f9-2b71252acf91
# Split all uuid downloads by day
begin
	@info("Splitting by day...")
	data_by_uuid_by_day = Dict(uuid => partition(r -> get_monthday(r), data_by_uuid[uuid]) for uuid in keys(data_by_uuid));
	art_by_hash_by_day  = Dict(hash => partition(r -> get_monthday(r), art_by_hash[hash]) for hash in keys(art_by_hash));
end

# ╔═╡ e682db28-1234-11eb-2f65-a5b2c7851037
# Helper function to get downloads for a particular day for a particular UUID
function get_downloads_on_day(data, uuid, day)
	return length(get(get(data, uuid, Dict()), day, []))
end

# ╔═╡ e115b50e-0f30-11eb-199a-356b687f950a
begin
	p = Plots.plot(size=(1200,600))
	for (uuid, total_downloads) in uuid_downloads[1:10]
		name = get_package_name(uuid)

		# Split this package by date
		hits_over_days = [get_downloads_on_day(data_by_uuid_by_day, uuid, d) for d in days_to_plot]
		
		# Plot this package's download stats over the days we're plotting
		Plots.plot!(p, days_to_plot, hits_over_days; label=name, legend=:outerright)
	end
	Plots.savefig(p, joinpath(output_path, "package_downloads_by_day_$(output_name).png"))
	p
end

# ╔═╡ 644fb8e8-1233-11eb-062b-9b3cbbd8b990
open(joinpath(output_path, "package_downloads_by_day_$(output_name).csv"), "w") do io
	csv_data = []
	for (uuid, total_downloads) in uuid_downloads
		# Don't bother reporting `missing` UUIDs
		if uuid === missing
			continue
		end
		days = [Symbol(d) => get_downloads_on_day(data_by_uuid_by_day, uuid, d) for d in days_to_plot]
		push!(csv_data, (;
			uuid=uuid,
			name=get_package_name(uuid),
			total_downloads=total_downloads,
			days...)
		)
	end
	csv_data = collect(csv_data)
	CSV.write(io, csv_data)
end

# ╔═╡ 644fb8e8-1233-11eb-062b-9b3cbbd8b991
open(joinpath(output_path, "artifact_downloads_by_day_$(output_name).csv"), "w") do io
	csv_data = []
	for (hash, total_downloads) in hash_downloads
		# Don't bother reporting `missing` hashes
		if hash === missing
			continue
		end
		days = [Symbol(d) => get_downloads_on_day(art_by_hash_by_day, hash, d) for d in days_to_plot]
		push!(csv_data, (;
			hash=hash,
			total_downloads=total_downloads,
			days...)
		)
	end
	csv_data = collect(csv_data)
	CSV.write(io, csv_data)
end

# ╔═╡ Cell order:
# ╠═830b9254-0f0f-11eb-2413-1bee87660bb8
# ╠═b0c79334-0f0f-11eb-31b7-6b7fb9d3c2ea
# ╠═35b616e2-0f1d-11eb-114f-43b4e3c4a3a7
# ╠═27f20b7e-0f1f-11eb-0946-7961458506fc
# ╠═f18edd54-0f10-11eb-3320-a7ded568fb2b
# ╠═d661b24c-0f1d-11eb-2494-2dae16fc399f
# ╠═bfac967c-0fd4-11eb-306e-4bfc20cb9b8f
# ╠═9b069834-0fe0-11eb-331f-a78263f9ebf7
# ╠═0053a8e8-0f33-11eb-27e9-e7f200e56661
# ╠═997b5fa2-0f1f-11eb-3aba-11a16b36c946
# ╠═8e490634-1230-11eb-27a5-3b7c9111e1f9
# ╠═d8e42340-1230-11eb-1ac1-db5dcad52696
# ╠═a6b95bd4-1234-11eb-22f9-2b71252acf91
# ╠═e682db28-1234-11eb-2f65-a5b2c7851037
# ╠═e115b50e-0f30-11eb-199a-356b687f950a
# ╠═644fb8e8-1233-11eb-062b-9b3cbbd8b990
# ╠═644fb8e8-1233-11eb-062b-9b3cbbd8b991
