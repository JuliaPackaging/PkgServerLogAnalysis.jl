using PkgServerLogAnalysis, Dates, Sockets, Random
using PkgServerLogAnalysis: decompress!, BufferStream

# Use this to generate an anonymized nginx log file.
function usage()
    println("Usage: anonymize_log.jl <infile> <outfile>")
    exit(1)
end

if length(ARGS) != 2
    usage()
end

infile = ARGS[1]
outfile = ARGS[2]

function load_nginx_log(filename)
    if endswith(filename, ".gz")
        return open(filename, "r") do io
            decomp_io = BufferStream()
            @async decompress!(io, decomp_io)
            return String(read(decomp_io))
        end
    else
        return String(read(filename))
    end
end
data = load_nginx_log(infile)

# Drop lines that dont' have `/package`, `/artifact` or `/registry` in them
data = join(filter(split(data, "\n")) do line
    return any(occursin.(("/package", "/artifact", "/registry"), Ref(line)))
end, "\n")

# Each time you run this script, it will randomize values in a different way,
# but it will randomize things consistently within the run, so that relationships
# between e.g. multiple requests from the same IP address are mostly left intact.
salt = UInt64(0) #rand(UInt64)

# We're going to scramble all IP addresses, content-hashes, and the H:M:S sections of timestamps.
ipv6_re = Regex(raw"(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))")
ipv4_re = Regex(raw"((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])")
hash_re = Regex(PkgServerLogAnalysis.hash_re)
dt_re = Regex(raw"\d\d/\w\w\w/\d\d\d\d:\d\d:\d\d:\d\d")

consistent_rng = Random.MersenneTwister()

Base.rand(rng::AbstractRNG, ::Type{IPv4}) = string(IPv4(rand(rng, UInt32)))
Base.rand(rng::AbstractRNG, ::Type{IPv6}) = string(IPv6(rand(rng, UInt128)))
Base.rand(rng::AbstractRNG, ::Type{Base.SHA1}) = string(Base.SHA1(rand(rng, UInt8, 20)))
df = Dates.DateFormat("dd/uuu/YYYY:HH:MM:SS")
function Base.rand(rng::AbstractRNG, ::Type{Dates.DateTime})
    # We're going to choose a random date between September 1st, 2020 and December 1st 2020
    dt = DateTime(2020, 9) + Second(rand(rng, UInt)%(60*60*24*91))
    return Dates.format(dt, df)
end
function replace_match(m, T, stochasticity = 0.5)
    # Most of the time, we use our salted seed to randomize to a deterministic
    # output, causing e.g. all identical IP addresses to get randomized to the
    # same output.  In order to not allow perfect reconstruction though, we add
    # an element of randomness to that, replacing some proportion of all these
    # values with completely random values.
    if rand(Float64) < stochasticity
        return rand(T)
    else
        Random.seed!(consistent_rng, hash(m, salt))
        return rand(consistent_rng, T)
    end
end

data = replace(data, ipv6_re => m -> replace_match(m, IPv6))
data = replace(data, ipv4_re => m -> replace_match(m, IPv4))
data = replace(data, hash_re => m -> replace_match(m, Base.SHA1))
data = replace(data, dt_re   => m -> replace_match(m, Dates.DateTime))

open(outfile, "w") do io
    write(io, data)
end
