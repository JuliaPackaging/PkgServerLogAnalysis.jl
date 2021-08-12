using Downloads, Dates, Scratch, Printf


# Download the last 30 days of logs
filenames = String[]
downloads = Task[]
for idx in 1:30
    n = now() - Day(idx)
    datestr = string(string(year(n), pad=4),string(month(n), pad=2),string(day(n), pad=2))
    filename = joinpath(@get_scratch!("neomirrors_logs"), "$(datestr)")
    push!(filenames, filename)
    if !isfile(filename)
        push!(downloads, @async begin
            url = "https://mirrors.tuna.tsinghua.edu.cn/logs/neomirrors/mirrors.log-$(datestr).gz"
            Downloads.download(url, string(filename, ".gz"))
            run(`gunzip $(filename).gz`)
        end)
    end
end

@info("Waiting for $(length(downloads)) downloads to finish")
wait.(downloads)

@info("Parsing out only `/julia` 200 OK requests...")
for f in filenames
    if !isfile("$(f).julia")
        open(f, read=true) do rio
            open("$(f).julia", write=true) do wio
                for line in readlines(rio)
                    if match(r"julia/(package|artifact|registry)/", line) !== nothing
                        println(wio, line)
                    end
                end
            end
        end
    end
end

@info("Summing up Julia 200 requests")
total_bytes_served = 0
for f in filenames
    f = "$(f).julia"
    open(f, read=true) do io
        day_bytes = 0
        for line in readlines(io)
            m = match(r"\"GET .*\" 200 (\d+)", line)
            if m !== nothing
                try
                    day_bytes += parse(Int, m.captures[1])
                catch e
                    @warn("Unable to parse", line, e)
                    continue
                end
            end
        end
        @info("Parsed", filename=basename(f), bytes=day_bytes)
        global total_bytes_served += day_bytes
    end
end

function human_readable(bytes)
    suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "YB"]

    suff_idx = 1
    while bytes > 999
        bytes /= 1024
        suff_idx += 1
    end
    return @sprintf("%.1f %s", bytes, suffixes[suff_idx])
end

@info("All done", total_bytes_served, human_readable(total_bytes_served))
