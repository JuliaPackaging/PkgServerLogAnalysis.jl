### A Pluto.jl notebook ###
# v0.14.4

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
	# Split CI hits out, and keep only package downloads
	part_raw_data = filter!(is_pkg_download, raw_data)
	part_raw_data = partition(is_ci_ip, part_raw_data)
	data = get(part_raw_data, false, CSV.Row[])
	ci_data = get(part_raw_data, true, CSV.Row[])
end;

# ╔═╡ d661b24c-0f1d-11eb-2494-2dae16fc399f
display("CI hits: $(length(ci_data)), other hits: $(length(data))");

# ╔═╡ bfac967c-0fd4-11eb-306e-4bfc20cb9b8f
function get_package_name(uuid::String)
	regs = Pkg.Types.collect_registries()
	for r in regs
		packages = Pkg.Types.read_registry(joinpath(r.path, "Registry.toml"))["packages"]
		if haskey(packages, uuid)
			return packages[uuid]["name"]
		end
	end
	return nothing
end

# ╔═╡ 9b069834-0fe0-11eb-331f-a78263f9ebf7
get_package_name(x) = nothing

# ╔═╡ 0053a8e8-0f33-11eb-27e9-e7f200e56661
begin
	df = DateFormat("d/u/y:H:M:S")
	get_monthday(row::CSV.Row) = get_monthday(row.time_utc)
	get_monthday(dt::DateTime) = @sprintf("%02d/%02d", month(dt), day(dt))
end

# ╔═╡ 997b5fa2-0f1f-11eb-3aba-11a16b36c946
begin
	# We purposefully exclude the first and last day to avoid timezone boundary issues
	days_to_plot = sort(collect(Set(get_monthday(r) for r in data)))[2:end-1]
	data_time_filtered = filter(r -> get_monthday(r) ∈ days_to_plot, data)
	
	# Next, split by package UUID and quickly calculate total downloads
	data_by_uuid = partition(d -> d.package_uuid, data_time_filtered);
	uuid_downloads = sort([u => length(data_by_uuid[u]) for u in keys(data_by_uuid)], by = k -> -k.second)
end

# ╔═╡ 8e490634-1230-11eb-27a5-3b7c9111e1f9
output_path = @get_scratch!("output")

# ╔═╡ d8e42340-1230-11eb-1ac1-db5dcad52696
output_name = "package_downloads_by_day_$(month(now()))-$(day(now()))"

# ╔═╡ a6b95bd4-1234-11eb-22f9-2b71252acf91
# Split all uuid downloads by day
data_by_uuid_by_day = Dict(uuid => partition(r -> get_monthday(r), data_by_uuid[uuid]) for uuid in keys(data_by_uuid));

# ╔═╡ e682db28-1234-11eb-2f65-a5b2c7851037
# Helper function to get downloads for a particular day for a particular UUID
function get_downloads_on_day(uuid, day)
	return length(get(get(data_by_uuid_by_day, uuid, Dict()), day, []))
end

# ╔═╡ e115b50e-0f30-11eb-199a-356b687f950a
begin
	p = Plots.plot(size=(1200,600))
	for (uuid, total_downloads) in uuid_downloads[1:10]
		name = get_package_name(uuid)

		# Split this package by date
		hits_over_days = [get_downloads_on_day(uuid, d) for d in days_to_plot]
		
		# Plot this package's download stats over the days we're plotting
		Plots.plot!(p, days_to_plot, hits_over_days; label=name, legend=:outerright)
	end
	Plots.savefig(p, joinpath(output_path, "$(output_name).png"))
	p
end

# ╔═╡ 644fb8e8-1233-11eb-062b-9b3cbbd8b990
open(joinpath(output_path, "$(output_name).csv"), "w") do io
	csv_data = []
	for (uuid, total_downloads) in uuid_downloads
		# Don't bother reporting `missing` UUIDs
		if uuid === missing
			continue
		end
		days = [Symbol(d) => get_downloads_on_day(uuid, d) for d in days_to_plot]
		push!(csv_data, (;
			uuid=uuid,
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
