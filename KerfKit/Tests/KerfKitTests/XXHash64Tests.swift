import Testing
@testable import KerfKit

struct XXHash64Tests {
    @Test func knownValues() {
        #expect(XXHash64.hash([]) == 0xEF46_DB37_51D8_E999)
        #expect(XXHash64.hash(Array("a".utf8)) == 0xD24E_C4F1_A98C_6E5B)
        #expect(XXHash64.hash(Array("abc".utf8)) == 0x44BC_2CF5_AD77_0999)
    }

    @Test func chunksDontMatter() {
        let data = (0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        let whole = XXHash64.hash(data)
        for size in [1, 7, 31, 32, 33, 100, 4096] {
            var hasher = XXHash64()
            var offset = 0
            while offset < data.count {
                hasher.update(Array(data[offset..<min(offset + size, data.count)]))
                offset += size
            }
            #expect(hasher.finalize() == whole, "chunk size \(size)")
        }
        #expect(XXHash64.hex(0xAB) == "00000000000000ab")
    }
}
