import Foundation
import Testing
@testable import KerfKit

struct NowPlayingStateTests {
    @Test func readsSafariFromTheAdapter() throws {
        let line = #"{"playbackRate":0,"album":"","elapsedTime":456.6,"timestamp":"2026-10-31T02:17:04Z","bundleIdentifier":"com.apple.WebKit.GPU","processIdentifier":770,"parentApplicationBundleIdentifier":"com.apple.Safari","title":"PFAS | LUBACH","duration":1263.6,"artist":"LUBACH","playing":false}"#
        let state = try #require(NowPlayingState.parse(Data(line.utf8)))
        #expect(state.title == "PFAS | LUBACH")
        #expect(state.sourceBundleID == "com.apple.Safari")
        #expect(state.processID == 770)
        #expect(state.duration == 1263.6)
        #expect(!state.isPlaying)
    }

    @Test func readsStreamEnvelopes() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Nachtrit","artist":"Boerma","playing":true,"bundleIdentifier":"com.spotify.client","artworkData":"AAEC"}}"#
        let state = try #require(NowPlayingState.parse(Data(line.utf8)))
        #expect(state.sourceBundleID == "com.spotify.client")
        #expect(state.artwork == Data([0, 1, 2]))
        #expect(state.isPlaying)
    }

    @Test func nothingPlaying() {
        #expect(NowPlayingState.parse(Data("null".utf8)) == nil)
        #expect(NowPlayingState.parse(Data(#"{"payload":{"title":""}}"#.utf8)) == nil)
    }

    @Test func musicLeavesOutWhatABrowserPlays() {
        let safari = #"{"title":"PFAS | LUBACH","playing":true,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari"}"#
        #expect(NowPlayingState.parse(Data(safari.utf8)) != nil)
        #expect(NowPlayingState.parseMusic(Data(safari.utf8)) == nil)
        let spotify = #"{"title":"Nachtrit","playing":true,"bundleIdentifier":"com.spotify.client"}"#
        #expect(NowPlayingState.parseMusic(Data(spotify.utf8))?.title == "Nachtrit")
    }

    @Test(arguments: ["com.apple.Safari", "com.apple.Safari.WebApp.5E1F", "com.apple.WebKit.GPU", "com.google.Chrome",
                      "com.google.Chrome.canary", "com.microsoft.edgemac"])
    func browsers(_ bundleID: String) {
        #expect(NowPlayingState(title: "x", sourceBundleID: bundleID).playsInBrowser)
    }

    @Test(arguments: ["com.spotify.client", "com.apple.Music", "com.apple.podcasts", "com.apple.TV", ""])
    func notBrowsers(_ bundleID: String) {
        #expect(!NowPlayingState(title: "x", sourceBundleID: bundleID).playsInBrowser)
    }

    @Test func elapsedRunsWhilePlayingAndStopsAtTheEnd() {
        let start = Date(timeIntervalSince1970: 1000)
        var state = NowPlayingState(title: "x", duration: 100, elapsed: 10, timestamp: start, isPlaying: true)
        #expect(state.elapsed(at: start.addingTimeInterval(5)) == 15)
        #expect(state.elapsed(at: start.addingTimeInterval(500)) == 100)
        state.isPlaying = false
        #expect(state.elapsed(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func clockFormat() {
        #expect(NowPlayingState.clock(65) == "1:05")
        #expect(NowPlayingState.clock(760) == "12:40")
        #expect(NowPlayingState.clock(3723) == "1:02:03")
    }
}

struct LevelMeterTests {
    func tone(_ frequency: Double, count: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / 48_000)) }
    }

    func run(_ meter: inout LevelMeter, _ samples: [Float], chunk: Int) -> LevelMeter.Levels {
        var levels = LevelMeter.Levels()
        var start = 0
        while start < samples.count {
            let end = min(start + chunk, samples.count)
            levels = samples[start..<end].withUnsafeBufferPointer { meter.process($0) }
            start = end
        }
        return levels
    }

    @Test func silenceIsFlat() {
        var meter = LevelMeter(sampleRate: 48_000)
        let levels = run(&meter, [Float](repeating: 0, count: 2048), chunk: 512)
        #expect(LevelMeter.array(levels).allSatisfy { $0 == 0 })
    }

    @Test func bassAndTrebleLightDifferentBars() {
        var bass = LevelMeter(sampleRate: 48_000)
        let low = LevelMeter.array(run(&bass, tone(60, count: 9600), chunk: 480))
        #expect(low.count == 6)
        #expect(low[0] > low[5])
        var treble = LevelMeter(sampleRate: 48_000)
        let high = LevelMeter.array(run(&treble, tone(9000, count: 9600), chunk: 480))
        #expect(high[5] > high[0])
        #expect(low.allSatisfy { (0...1).contains($0) })
    }

    /// Bigger audio buffers must not change how the bars move.
    @Test func sameAtAnyBufferSize() {
        var noise: UInt32 = 7
        let music = (0..<48_000).map { index -> Float in
            noise = noise &* 1_664_525 &+ 1_013_904_223
            return Float(sin(Double(index) * 0.02)) * 0.4 + (Float(noise >> 8) / Float(1 << 24) - 0.5) * 0.2
        }
        var small = LevelMeter(sampleRate: 48_000)
        var large = LevelMeter(sampleRate: 48_000)
        let a = run(&small, Array(music.prefix(46_080)), chunk: 512)
        let b = run(&large, Array(music.prefix(46_080)), chunk: 1600)
        #expect(LevelMeter.array(a) == LevelMeter.array(b))
    }

    /// The vector version gives what the bars were tuned with: the old per-sample meter.
    @Test func matchesTheTunedMeter() {
        var noise: UInt32 = 3
        let music = (0..<24_576).map { index -> Float in
            noise = noise &* 1_664_525 &+ 1_013_904_223
            return Float(sin(Double(index) * 0.01) + sin(Double(index) * 0.7)) * 0.3 + (Float(noise >> 8) / Float(1 << 24) - 0.5) * 0.3
        }
        var meter = LevelMeter(sampleRate: 48_000)
        let levels = LevelMeter.array(run(&meter, music, chunk: 512))
        // The meter as it was: arrays, one buffer of 512 at a time.
        let edges: [Double] = [120, 350, 900, 2200, 5000]
        let lift: [Float] = [0, 3, 6, 9, 12, 15]
        let coefficients = edges.map { Float(1 - exp(-2 * Double.pi * $0 / 48_000)) }
        var lows = [Float](repeating: 0, count: 5)
        var smoothed = [Float](repeating: 0, count: 6)
        for block in stride(from: 0, to: music.count, by: 512) {
            var energy = [Float](repeating: 0, count: 6)
            for sample in music[block..<block + 512] {
                var below: Float = 0
                for index in lows.indices {
                    lows[index] += coefficients[index] * (sample - lows[index])
                    let band = lows[index] - below
                    energy[index] += band * band
                    below = lows[index]
                }
                energy[5] += (sample - below) * (sample - below)
            }
            for band in 0..<6 {
                let rms = (energy[band] / 512).squareRoot()
                let level = min(max((20 * log10(max(rms, 1e-7)) + lift[band] + 48) / 42, 0), 1)
                smoothed[band] += (level - smoothed[band]) * (level > smoothed[band] ? 0.65 : 0.18)
            }
        }
        for band in 0..<6 { #expect(abs(levels[band] - smoothed[band]) < 0.0005) }
    }

    @Test func stereoIsMixedToMono() {
        let mono = tone(440, count: 4096)
        let stereo = mono.flatMap { [$0, $0] }
        var a = LevelMeter(sampleRate: 48_000)
        var b = LevelMeter(sampleRate: 48_000)
        let fromMono = run(&a, mono, chunk: 1024)
        let fromStereo = stereo.withUnsafeBufferPointer { b.process(interleaved: $0, channels: 2) }
        #expect(LevelMeter.array(fromMono) == LevelMeter.array(fromStereo))
    }

    @Test func newTrackWithTheLastCoverIsStale() {
        let cover = Data([1, 2, 3])
        let first = NowPlayingState(title: "One", artist: "A", album: "First", sourceBundleID: "com.spotify.client", artwork: cover)
        let next = NowPlayingState(title: "Two", artist: "B", album: "Second", sourceBundleID: "com.spotify.client", artwork: cover)
        #expect(next.hasStaleArtwork(after: first))
        // Its own cover, or none yet: nothing stale.
        #expect(!NowPlayingState(title: "Two", artist: "B", album: "Second", artwork: Data([9])).hasStaleArtwork(after: first))
        #expect(!NowPlayingState(title: "Two", artist: "B", album: "Second").hasStaleArtwork(after: first))
    }

    @Test func oneAlbumSharesItsCover() {
        let cover = Data([1, 2, 3])
        let first = NowPlayingState(title: "One", artist: "A", album: "Record", artwork: cover)
        #expect(!NowPlayingState(title: "Two", artist: "A", album: "Record", artwork: cover).hasStaleArtwork(after: first))
        // Without albums the artist decides.
        let single = NowPlayingState(title: "One", artist: "A", artwork: cover)
        #expect(!NowPlayingState(title: "Two", artist: "A", artwork: cover).hasStaleArtwork(after: single))
        #expect(NowPlayingState(title: "Two", artist: "B", artwork: cover).hasStaleArtwork(after: single))
        // The same track again (paused, resumed) is never stale.
        #expect(!first.hasStaleArtwork(after: first))
    }
}
