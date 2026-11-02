/// xxHash64, the checksum offload tools use: fast enough to verify a card at full disk speed.
public struct XXHash64: Sendable {
    private static let p1: UInt64 = 11_400_714_785_074_694_791
    private static let p2: UInt64 = 14_029_467_366_897_019_727
    private static let p3: UInt64 = 1_609_587_929_392_839_161
    private static let p4: UInt64 = 9_650_029_242_287_828_579
    private static let p5: UInt64 = 2_870_177_450_012_600_261

    private var v1: UInt64, v2: UInt64, v3: UInt64, v4: UInt64
    private let seed: UInt64
    private var total: UInt64 = 0
    private var buffer = [UInt8](repeating: 0, count: 32)
    private var buffered = 0

    public init(seed: UInt64 = 0) {
        self.seed = seed
        v1 = seed &+ Self.p1 &+ Self.p2
        v2 = seed &+ Self.p2
        v3 = seed
        v4 = seed &- Self.p1
    }

    @inline(__always) private static func round(_ acc: UInt64, _ input: UInt64) -> UInt64 {
        var acc = acc &+ input &* p2
        acc = (acc << 31) | (acc >> 33)
        return acc &* p1
    }

    @inline(__always) private static func merge(_ acc: UInt64, _ value: UInt64) -> UInt64 {
        let value = round(0, value)
        return (acc ^ value) &* p1 &+ p4
    }

    @inline(__always) private static func read64(_ p: UnsafeRawPointer, _ offset: Int) -> UInt64 {
        UInt64(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    @inline(__always) private static func read32(_ p: UnsafeRawPointer, _ offset: Int) -> UInt64 {
        UInt64(UInt32(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
    }

    public mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard var pointer = bytes.baseAddress, bytes.count > 0 else { return }
        var length = bytes.count
        total &+= UInt64(length)
        if buffered + length < 32 {
            buffer.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: buffered).copyMemory(from: pointer, byteCount: length) }
            buffered += length
            return
        }
        if buffered > 0 {
            let fill = 32 - buffered
            buffer.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: buffered).copyMemory(from: pointer, byteCount: fill) }
            buffer.withUnsafeBytes { stripe in
                let s = stripe.baseAddress!
                v1 = Self.round(v1, Self.read64(s, 0))
                v2 = Self.round(v2, Self.read64(s, 8))
                v3 = Self.round(v3, Self.read64(s, 16))
                v4 = Self.round(v4, Self.read64(s, 24))
            }
            pointer = pointer.advanced(by: fill)
            length -= fill
            buffered = 0
        }
        var (a, b, c, d) = (v1, v2, v3, v4)
        while length >= 32 {
            a = Self.round(a, Self.read64(pointer, 0))
            b = Self.round(b, Self.read64(pointer, 8))
            c = Self.round(c, Self.read64(pointer, 16))
            d = Self.round(d, Self.read64(pointer, 24))
            pointer = pointer.advanced(by: 32)
            length -= 32
        }
        (v1, v2, v3, v4) = (a, b, c, d)
        if length > 0 {
            buffer.withUnsafeMutableBytes { $0.baseAddress!.copyMemory(from: pointer, byteCount: length) }
            buffered = length
        }
    }

    public mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update($0) }
    }

    public func finalize() -> UInt64 {
        var hash: UInt64
        if total >= 32 {
            hash = ((v1 << 1) | (v1 >> 63)) &+ ((v2 << 7) | (v2 >> 57)) &+ ((v3 << 12) | (v3 >> 52)) &+ ((v4 << 18) | (v4 >> 46))
            hash = Self.merge(hash, v1)
            hash = Self.merge(hash, v2)
            hash = Self.merge(hash, v3)
            hash = Self.merge(hash, v4)
        } else {
            hash = seed &+ Self.p5
        }
        hash &+= total
        buffer.withUnsafeBytes { raw in
            let p = raw.baseAddress!
            var offset = 0
            while offset + 8 <= buffered {
                let k = Self.round(0, Self.read64(p, offset))
                hash ^= k
                hash = ((hash << 27) | (hash >> 37)) &* Self.p1 &+ Self.p4
                offset += 8
            }
            if offset + 4 <= buffered {
                hash ^= Self.read32(p, offset) &* Self.p1
                hash = ((hash << 23) | (hash >> 41)) &* Self.p2 &+ Self.p3
                offset += 4
            }
            while offset < buffered {
                hash ^= UInt64(p.load(fromByteOffset: offset, as: UInt8.self)) &* Self.p5
                hash = ((hash << 11) | (hash >> 53)) &* Self.p1
                offset += 1
            }
        }
        hash ^= hash >> 33
        hash &*= Self.p2
        hash ^= hash >> 29
        hash &*= Self.p3
        hash ^= hash >> 32
        return hash
    }

    public static func hash(_ bytes: [UInt8]) -> UInt64 {
        var hasher = XXHash64()
        hasher.update(bytes)
        return hasher.finalize()
    }

    public static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
