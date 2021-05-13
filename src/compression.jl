using CodecZlib, CodecZstd, TranscodingStreams

function decompress!(input::IO, output::IO; blocksize::Int = 2*1024*1024)
    comp = detect_compressor(input)
    if comp === nothing
        write(output, input)
        return
    end

    output = TranscodingStream(decompressor_object(comp), output)
    while !eof(input)
        write(output, read(input, blocksize))
    end
    # Close the TranscodingStream (this implicitly closes the wrapped output)
    close(output)
end

function compress!(input::IO, output::IO; blocksize::Int = 2*1024*1024, compression::String = "zstd")
    output = TranscodingStream(compressor_object(compression), output)
    while !eof(input)
        write(output, read(input, blocksize))
    end
    close(output)
end

function detect_compressor(io::IO)
    mark(io)
    header = read(io, 6)
    reset(io)
    compressor_magic_bytes = Dict(
        "gzip" => [0x1f, 0x8b],
        "xz" => [0xfd, 0x37, 0x7a, 0x58, 0x5A, 0x00],
        "zstd" => [0x28, 0xB5, 0x2F, 0xFD],
        "bzip2" => [0x42, 0x5a, 0x68],
    )
    for (compressor, magic) in compressor_magic_bytes
        lm = length(magic)
        if length(header) >= lm && header[1:lm] == magic
            return compressor
        end
    end
    return nothing
end

function compressor_object(compression_type::String)
    if compression_type == "gzip"
        return GzipCompressor(;level=9)
    elseif compression_type == "zstd"
        return ZstdCompressor(;level=19)
    else
        error("Unable to use compressor type $(compression_type)")
    end
end

function decompressor_object(decompression_type::String)
    if decompression_type == "gzip"
        return GzipDecompressor()
    elseif decompression_type == "zstd"
        return ZstdDecompressor()
    else
        error("Unable to use decompressor type $(compression_type)")
    end
end
