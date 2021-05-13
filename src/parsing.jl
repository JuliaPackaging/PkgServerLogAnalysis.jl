
function field_ns(name, pat; quoted=false, allow_dash=false)
    local ret
    if allow_dash
        ret = "(?<$(name)>($(pat))|-)"
    else
        ret = "(?<$(name)>$(pat))"
    end
    if quoted
        ret = string("\"", ret, "\"")
    end
    return ret
end
field(name, pat; kwargs...) = field_ns(name, pat; kwargs...)

# Build mondo regex to parse whole line into fields.  This is going to be a ridiculously large regex.dd

# For reference, the log_format used by nginx is:
# '$remote_addr [$time_iso8601] "$request" $status $body_bytes_sent "$http_user_agent" $request_time $http_julia_version $http_julia_system "$http_julia_ci_variables" $http_julia_interactive "$http_julia_pkg_server"'
const hex_re = "[a-fA-F0-9]"
const uuid_re = "$(hex_re){8}-$(hex_re){4}-$(hex_re){4}-$(hex_re){4}-$(hex_re){12}"
const hash_re = "$(hex_re){40}"
const mondo_pieces = [
    # $remote_addr, either an ipv4 or ipv6 address
    field("remote_addr", raw"[\.a-fA-F0-9:]+"),
    # $time_iso8601 or $time_local, a timestamp a la `[16/Jul/2020:06:24:54 +0000]`/`[2016-09-29T10:20:48+01:00]`
    field("time_utc", raw"\[.*?\]"),
    # $request, which we split into `$request_method`, `$request_url` and `$request_http`.
    field("request", string(
           field("request_method", raw"[^ ]+"),
           " ",
           field("request_url", string(
               # Try to parse out a package URL
               field_ns("package", string("/package/",   field_ns("package_uuid", uuid_re), "/", field_ns("package_hash", hash_re))),
               "|",
               # Try to parse out a registry URL
               field_ns("registry", string("/registry/", field_ns("registry_uuid", uuid_re), "/", field_ns("registry_hash", hash_re))),
               "|",
               # Try to parse out an artifact URL
               field_ns("artifact", string("/artifact/", field_ns("artifact_hash", hash_re))),
               "|",
               # Fallback for everything else
               "[^ ]+",
           )),
           " ",
           field_ns("request_http", raw"HTTP/[\.\d]+"),
    ); quoted=true),
    # $status
    field("status", raw"\d+"),
    # $body_bytes_sent
    field("body_bytes_sent", raw"\d+"),
    # $http_user_agent
    field("http_user_agent", raw".+?"; quoted=true),
    # $request_time; how long it took the backend to process this request
    field("request_time", raw"[\.\d]+"),
    # $julia_version; constrain it to start with `\d+\.`, to enforce as much schema as possible.
    field("julia_version", raw"\d+\.[^ ]+", allow_dash=true),
    # $julia_system; the full host platform triplet identifying compiler ABI
    field("julia_system", raw"[^ ]+"; allow_dash=true),
    # $julia_ci_variables; a semicolon-separated list of variable mappings self-identifying CI systems
    field("julia_ci_variables", raw"[^ ]+"; quoted=true, allow_dash=true),
    # $julia_interactive; a boolean self-identifying an interactive session
    field("julia_interactive", raw"[^ ]+"; allow_dash=true),
    # $julia_pkg_server; the original Pkg server attempting to be contacted
    field("julia_pkg_server", raw"[^ ]+"; quoted=true, allow_dash=true),
]
const mondo_regex = Regex(string("^", join(mondo_pieces, " "), "\$"))

function Base.keys(r::Regex)
    Symbol[Symbol(x[2]) for x in Base.PCRE.capture_names(r.regex)]
end
const mondo_capture_groups = keys(mondo_regex)

# There are certain well-known URL requests that we should just ignore.
function should_ignore_parse_failure(r::RegexMatch)
    if haskey(r, :request_url)
        request_url = r[:request_url]
        # No favicons, robots or homepages here, move along
        if request_url == "/" || request_url == "/favicon.ico" || request_url == "/robots.txt"
            return true
        end
        # Ignore hits on our meta-URLs
        if startswith(request_url, "/meta")
            return true
        end
        # If it's a request for a badge, ignore
        if startswith(request_url, "/badges/")
            return true
        end
        # Ignore what are presumably old julia hub links
        if startswith(request_url, "/detail/") || startswith(request_url, "/docs/") || startswith(request_url, "/logs/")
            return true
        end
    end
    # If it's StatPing, ignore
    if haskey(r, :http_user_agent)
        http_user_agent = r[:http_user_agent]
        if lowercase(http_user_agent) == "statping"
            return true
        end
    end
    return false
end

# We rewrite some regex matches
function fetch_rewrite(m::RegexMatch, k::Symbol)
    x = m[k]

    # Rewrite timestamp into ISO8601 format
    if k === :time_utc
        # nginx $time_local format, e.g. [29/Sep/2016:10:20:48 +0100]
        time_local_re = r"^\[(\d{2}\/\w{3}\/\d{4}:\d{2}:\d{2}:\d{2}) (\+|-)(\d{2})(\d{2})\]$"
        # nginx $time_iso8601 format, e.g. [2016-09-29T10:20:48+01:00]
        time_iso8601_re = r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\+|-)(\d{2}):(\d{2})\]$"
        if (m = match(time_local_re, x)) !== nothing
            dt = tryparse(DateTime, m[1], dateformat"dd/uu/yyyy:HH:MM:SS")
            offset_sign = m[2]
            offset_hour = m[3]
            offset_min = m[4]
        elseif (m = match(time_iso8601_re, x)) !== nothing
            dt = tryparse(DateTime, m[1], dateformat"yyyy-mm-ddTHH:MM:SS")
            offset_sign = m[2]
            offset_hour = m[3]
            offset_min = m[4]
        else
            return nothing
        end
        dt === nothing && return nothing
        offset = Hour(parse(Int, offset_hour)) + Minute(parse(Int, offset_min))
        if offset_sign == "+"
            dt -= offset
        else # offset_sign == "-"
            dt += offset
        end
        return Dates.format(dt, dateformat"yyyy-mm-ddTHH:MM:SS")
    end

    # Parse request_time as Float64
    if k === :request_time
        return tryparse(Float64, x)
    end

    # Parse status and body_bytes_sent as Int
    if k === :status || k == :body_bytes_sent
        return tryparse(Int, x)
    end

    # Parse julia_interactive as Bool
    if k === :julia_interactive
        return tryparse(Bool, x)
    end

    # Rewrite "-" to missing
    if x == "-"
        return missing
    end

    return x
end


function parse_log_line(line::AbstractString, filename::AbstractString="")
    m = match(mondo_regex, line)
    if m === nothing
        # Try to debug where it went wrong:
        for idx in 2:length(mondo_pieces)
            mini_regex = Regex(join(mondo_pieces[1:idx]))
            mini_match = match(mini_regex, line)
            if mini_match === nothing
                prev_regex = Regex(join(mondo_pieces[1:(idx-1)]))
                prev_match = match(prev_regex, line)
                if prev_match !== nothing
                    next_token = first(split(line[max(length(prev_match.match),1):end]))
                    @warn("Unable to parse", line, next_token, prev_match, idx, mondo_pieces[idx], filename)
                    break
                end

            # If this is a well-known URL that we know we can't parse, silently fail
            elseif should_ignore_parse_failure(mini_match)
                break
            end
        end
        return nothing
    end
    nothing_to_missing(::Nothing) = missing
    nothing_to_missing(x) = x

    # Try to parse out a pkgserver from the filename
    pkgserver = missing
    fm = match(r"^access_(.*)\.pkg\.julia", basename(filename))
    if fm !== nothing
        pkgserver = fm[1]
    end

    return (;(k => nothing_to_missing(fetch_rewrite(m, k)) for k in mondo_capture_groups)..., :pkgserver => pkgserver)
end
