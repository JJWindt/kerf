import Testing
@testable import KerfKit

struct DurationTests {
    @Test func parses() {
        #expect(DurationParser.seconds("5") == 300)
        #expect(DurationParser.seconds("5m") == 300)
        #expect(DurationParser.seconds("90s") == 90)
        #expect(DurationParser.seconds("1h30") == 5400)
        #expect(DurationParser.seconds("1:30") == 90)
        #expect(DurationParser.seconds("25 min") == 1500)
        #expect(DurationParser.seconds("2u") == 7200)
        #expect(DurationParser.seconds("koffie") == nil)
        #expect(DurationParser.seconds("") == nil)
    }
}
