module HyperLogLogHashIPs

export hll_hash_ip, load_hll_key!

using Sockets
using SHA

function ip_data(addr::IPAddr)
    n = sizeof(addr.host)
    [(addr.host >>> ((n-i) << 3)) % UInt8 for i = 1:n]
end

ip_addr(host::UInt32) = IPv4(host)
ip_addr(host::UInt128) = IPv6(host)

# Feistel network with sha256 as round function

const ROUNDS = 16
const DIGEST = SHA.SHA512_CTX

function feistel!(key::Vector{UInt8}, data::Vector{UInt8}, enc::Bool)
    n = length(data)
    m = n >> 1
    rounds = enc ? (0:1:ROUNDS-1) : (ROUNDS-1:-1:0)
    for round in rounds
        digest = DIGEST()
        update!(digest, [round % UInt8])
        update!(digest, key)
        update!(digest, view(data, m+1:n))
        for (i, x) in enumerate(digest!(digest))
            data[mod1(i, m)] ⊻= x
        end
        round == rounds[end] && break
        for i = 1:m
            data[i], data[m+i] = data[m+i], data[i]
        end
    end
    return data
end

encrypt!(key::Vector{UInt8}, data::Vector{UInt8}) = feistel!(key, data, true)
decrypt!(key::Vector{UInt8}, data::Vector{UInt8}) = feistel!(key, data, false)

const ignore_bits = 2 # 2^2 = 4 collisions
const bucket_mask = 0x0000_0fff # 12 bits
const sample_mask = ~bucket_mask << ignore_bits # 18 bits
const sample_shift = trailing_ones(bucket_mask)

@assert count_ones(bucket_mask | sample_mask) == 30

function hyper_log_log!(key::Vector{UInt8}, data::Vector{UInt8})
    encrypt!(key, data)
    value = zero(UInt32)
    for i = 1:sizeof(value)
        value <<= 8
        value |= data[i]
    end
    bucket = value & bucket_mask
    sample = value & sample_mask
    sample = leading_ones(sample)
    return UInt16(bucket), UInt8(sample)
end

function snowflake_hll((bucket, sample)::Tuple{UInt16, UInt8})
    data = Base.StringVector(3)
    data[1] = bucket % UInt8
    data[2] = bucket >> 8
    data[3] = sample + 1
    return String(data)
end

# By default, we encrypt with a zeroed-out key.  The user must either explicitly pass in `key` to `hll_hash_ip()`
# or call `load_hll_key!()` to change this key value.
const default_hll_key = zeros(UInt8, 512)

function load_hll_key!(path::AbstractString)
    open(path, read=true) do io
        # Read the file, try to assign it into `default_hll_key`
        new_key = read(io)
        if length(new_key) != 512
            error("Invalid HLL key!  Must provide exactly 512 bytes of data!")
        end
        global default_hll_key[:] = new_key
    end
    return nothing
end

hll_hash_ip(addr::AbstractString, key::Vector{UInt8} = default_hll_key) = hll_hash_ip(parse(IPAddr, addr), key)
hll_hash_ip(addr::IPAddr, key::Vector{UInt8} = default_hll_key) = snowflake_hll(hyper_log_log!(key, ip_data(addr)))

end # module
