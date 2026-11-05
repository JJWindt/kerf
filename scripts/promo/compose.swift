// Composes the promo video from `Kerf --lab promo` frames: a flat, tilted plane with the real
// island on it, a camera that snaps between angles, kinetic type, wipes and synthesized sound,
// all timed to the recording's events.
//
//     compose <frames> <out>                 kerf-promo.mp4, kerf-promo-silent.mp4, sfx.wav, vo.wav, mix.wav
//     compose <frames> <out> --voiceover     first fetches missing voice-over lines from ElevenLabs
//     compose <frames> <out> --audio-only    remixes the sound onto an existing kerf-promo-silent.mp4
//     compose <frames> <out> --stills 3,8.5  only PNGs of those moments, for checking
//
// The voice-over needs ELEVENLABS_API_KEY in the environment or in the repository's .env;
// ELEVENLABS_VOICE_ID picks another voice, ELEVENLABS_BASE_URL a data residency stack. Music is <out>/music.* (mp3, m4a, wav, aiff), if there.

import AppKit
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import ImageIO

_ = NSApplication.shared
let arguments = CommandLine.arguments
let framesDirectory = URL(fileURLWithPath: arguments[1])
let outDirectory = URL(fileURLWithPath: arguments[2])
try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
let stills: [Double]? = arguments.firstIndex(of: "--stills").map { arguments[$0 + 1].split(separator: ",").compactMap { Double($0) } }
let fetchesVoiceover = arguments.contains("--voiceover"), audioOnly = arguments.contains("--audio-only")

let width = 1920.0, height = 1080.0, fps = 60
let duration = 45.5
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.outputColorSpace: colorSpace, .cacheIntermediates: false])

// MARK: - Palette: one warm grey, ink, and the island's own orange

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let ground = rgb(0.902, 0.894, 0.875)
let plane = rgb(0.957, 0.953, 0.937)
let shadowTone = (r: 0.835, g: 0.827, b: 0.804)
let ink = rgb(0.05, 0.05, 0.05)
let muted = rgb(0.52, 0.51, 0.49)
let accent = rgb(1.0, 0.58, 0.22)
func white(_ a: Double) -> CGColor { rgb(1, 1, 1, a) }

// MARK: - Recording

struct Frame { let url: URL; let time: Double }

func lines(_ name: String) -> [[Substring]] {
    let text = (try? String(contentsOf: framesDirectory.appendingPathComponent(name), encoding: .utf8)) ?? ""
    return text.split(separator: "\n").map { $0.split(separator: " ") }
}

let frames = lines("times.txt").map { Frame(url: framesDirectory.appendingPathComponent(String($0[0])), time: Double($0[1])!) }
let events = lines("events.txt").map { (time: Double($0[0])!, name: String($0[1])) }

/// The time of the n-th event with this name in the recording.
func event(_ name: String, _ n: Int = 0) -> Double {
    events.filter { $0.name == name }[n].time
}

var cachedFrame: (index: Int, image: CGImage)?

func islandFrame(at time: Double) -> CGImage? {
    var low = 0, high = frames.count - 1
    guard high >= 0, time >= frames[0].time else { return nil }
    while low < high {
        let mid = (low + high + 1) / 2
        if frames[mid].time <= time { low = mid } else { high = mid - 1 }
    }
    if let cachedFrame, cachedFrame.index == low { return cachedFrame.image }
    guard let source = CGImageSourceCreateWithURL(frames[low].url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    cachedFrame = (low, image)
    return image
}

// MARK: - Easing

func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double { min(max(x, low), high) }
func progress(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp((t - start) / (end - start)) }
func expoOut(_ x: Double) -> Double { x >= 1 ? 1 : 1 - pow(2, -10 * x) }
func expoIn(_ x: Double) -> Double { x <= 0 ? 0 : pow(2, 10 * x - 10) }
func expoInOut(_ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    return x < 0.5 ? pow(2, 20 * x - 10) / 2 : (2 - pow(2, -20 * x + 10)) / 2
}
func sine(_ x: Double) -> Double { -(cos(.pi * x) - 1) / 2 }
func backOut(_ x: Double) -> Double {
    let c1 = 1.4, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}
func mix(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }
func mix(_ a: CGPoint, _ b: CGPoint, _ x: Double) -> CGPoint { CGPoint(x: mix(a.x, b.x, x), y: mix(a.y, b.y, x)) }

// MARK: - Drawing helpers (top-left origin)

extension CGContext {
    func draw(image: CGImage, in rect: CGRect, alpha: Double = 1) {
        saveGState()
        setAlpha(alpha)
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }

    func fill(_ rect: CGRect, radius: Double, color: CGColor) {
        addPath(CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2, rect.height / 2),
                       cornerHeight: min(radius, rect.width / 2, rect.height / 2), transform: nil))
        setFillColor(color)
        fillPath()
    }
}

func font(_ size: Double, _ weight: NSFont.Weight) -> NSFont { .systemFont(ofSize: size, weight: weight) }

func ctLine(_ text: String, _ font: NSFont, _ color: CGColor, kern: Double = 0) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: kern]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
}

func textWidth(_ text: String, _ font: NSFont, kern: Double = 0) -> Double {
    CTLineGetTypographicBounds(ctLine(text, font, ink, kern: kern), nil, nil, nil)
}

enum Align { case left, center, right }

func draw(_ text: String, in context: CGContext, x: Double, y: Double, font: NSFont, color: CGColor, kern: Double = 0, alpha: Double = 1) {
    context.saveGState()
    context.setAlpha(alpha)
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(ctLine(text, font, color, kern: kern), context)
    context.restoreGState()
}

/// Words that rise into place one after another from behind their own line, and leave upwards.
func kinetic(_ text: String, in context: CGContext, t: Double, x: Double, y: Double, font: NSFont, color: CGColor,
             align: Align, start: Double, end: Double, kern: Double = 0, accentWords: Set<Int> = [], stagger: Double = 0.055) {
    guard t > start, t < end + 0.6 else { return }
    let words = text.split(separator: " ").map(String.init)
    let widths = words.map { textWidth($0, font, kern: kern) }
    let space = textWidth(" ", font, kern: kern)
    let total = widths.reduce(0, +) + space * Double(words.count - 1)
    var wordX = align == .left ? x : align == .center ? x - total / 2 : x - total
    let ascent = font.ascender, descent = -font.descender, travel = (ascent + descent) * 1.05
    for (index, word) in words.enumerated() {
        defer { wordX += widths[index] + space }
        let enter = expoOut(progress(t, start + Double(index) * stagger, start + Double(index) * stagger + 0.55))
        let exit = expoIn(progress(t, end + Double(index) * 0.025, end + Double(index) * 0.025 + 0.3))
        guard enter > 0, exit < 1 else { continue }
        context.saveGState()
        context.clip(to: CGRect(x: wordX - 12, y: y - ascent - 10, width: widths[index] + 24, height: ascent + descent + 20))
        draw(word, in: context, x: wordX, y: y + (1 - enter) * travel - exit * travel, font: font,
             color: accentWords.contains(index) ? accent : color, kern: kern)
        context.restoreGState()
    }
}

func makeContext(_ w: Int, _ h: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext {
    let context = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.translateBy(x: 0, y: Double(h))
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    return context
}

// MARK: - Camera

struct Pose {
    var rx = 0.0, ry = 0.0, rz = 0.0, s = 1.0
    /// The point of the plane that sits at the middle of the picture, plus an offset.
    var fx = 960.0, fy = 40.0, tx = 0.0, ty = 0.0

    static func mix(_ a: Pose, _ b: Pose, _ x: Double) -> Pose {
        func m(_ p: Double, _ q: Double) -> Double { p + (q - p) * x }
        // Scale in log space, so zooming through the notch feels even.
        return Pose(rx: m(a.rx, b.rx), ry: m(a.ry, b.ry), rz: m(a.rz, b.rz), s: exp(m(log(a.s), log(b.s))),
                    fx: m(a.fx, b.fx), fy: m(a.fy, b.fy), tx: m(a.tx, b.tx), ty: m(a.ty, b.ty))
    }
}

struct Move { let time: Double; let duration: Double; let ease: (Double) -> Double; let pose: Pose; var whoosh = 0.0 }

let inNotch = Pose(s: 26, fx: 960, fy: 32)

let moves: [Move] = {
    let dot = event("dot") + 0.25
    let open0 = event("open", 0), close0 = event("close", 0)
    let question = event("question") - 0.28, close1 = event("close", 1)
    let threads = event("threads") - 0.1, jump = event("jump"), alert = event("pull-alert") - 0.38
    let pulls = event("pulls") - 0.05, close2 = event("close", 2), idle = event("idle", 1) + 0.2
    return [
        Move(time: 0, duration: 0, ease: { $0 }, pose: inNotch),
        // Out of the notch: the dot and its count.
        Move(time: dot, duration: 1.0, ease: expoOut, pose: Pose(rx: 16, ry: -26, rz: 0, s: 1.62, fx: 960, fy: 40, tx: -150, ty: -70), whoosh: 1),
        Move(time: dot + 1.0, duration: open0 - dot - 1.1, ease: sine, pose: Pose(rx: 12, ry: -17, rz: 1, s: 1.72, fx: 960, fy: 40, tx: -130, ty: -70)),
        // A permission: swing round as it opens.
        Move(time: open0 - 0.05, duration: 0.6, ease: expoOut, pose: Pose(rx: -10, ry: 18, rz: -2.5, s: 1.28, fx: 960, fy: 230, tx: 150, ty: -120), whoosh: 0.9),
        Move(time: open0 + 0.55, duration: close0 - open0 - 0.6, ease: sine, pose: Pose(rx: -7, ry: 12, rz: -1.5, s: 1.34, fx: 960, fy: 230, tx: 150, ty: -115)),
        Move(time: close0 + 0.04, duration: 0.42, ease: expoIn, pose: Pose(rx: -22, ry: 34, rz: -4, s: 1.4, fx: 960, fy: 120, tx: 300, ty: -60), whoosh: 0.6),
        // A question, from the other side.
        Move(time: question, duration: 0, ease: { $0 }, pose: Pose(rx: 14, ry: -38, rz: 4, s: 1.4, fx: 960, fy: 200, tx: -300, ty: -60)),
        Move(time: question, duration: 0.75, ease: expoOut, pose: Pose(rx: 9, ry: -15, rz: 1.5, s: 1.28, fx: 960, fy: 230, tx: -150, ty: -120)),
        Move(time: question + 0.75, duration: close1 - question - 0.8, ease: sine, pose: Pose(rx: 6, ry: -9, rz: 0.8, s: 1.33, fx: 960, fy: 230, tx: -150, ty: -115)),
        Move(time: close1 + 0.04, duration: 0.42, ease: expoIn, pose: Pose(rx: 20, ry: -30, rz: 3, s: 1.35, fx: 960, fy: 160, tx: -220, ty: -60), whoosh: 0.6),
        // The threads: tipped back, then swung upright.
        Move(time: threads, duration: 0, ease: { $0 }, pose: Pose(rx: -48, ry: 0, rz: 0, s: 1.25, fx: 960, fy: 260, tx: 0, ty: -20)),
        Move(time: threads, duration: 0.85, ease: expoOut, pose: Pose(rx: -18, ry: 12, rz: -1.5, s: 1.24, fx: 960, fy: 250, tx: 180, ty: -130), whoosh: 0.9),
        Move(time: threads + 0.85, duration: jump - threads - 0.95, ease: sine, pose: Pose(rx: -9, ry: -5, rz: 0, s: 1.32, fx: 900, fy: 260, tx: 180, ty: -110)),
        // A whip to the terminal tab.
        Move(time: jump, duration: 0.55, ease: expoOut, pose: Pose(rx: 7, ry: -20, rz: 1, s: 0.9, fx: 960, fy: 470, tx: -170, ty: -30), whoosh: 1),
        Move(time: jump + 0.55, duration: alert - jump - 0.6, ease: sine, pose: Pose(rx: 4, ry: -12, rz: 0.5, s: 0.95, fx: 960, fy: 470, tx: -170, ty: -30)),
        // Back to the notch for the pull request alert, then open.
        Move(time: alert, duration: 0.5, ease: expoInOut, pose: Pose(rx: 18, ry: 28, rz: -3, s: 1.62, fx: 960, fy: 40, tx: 160, ty: -70), whoosh: 1),
        Move(time: alert + 0.5, duration: pulls - alert - 0.55, ease: sine, pose: Pose(rx: 13, ry: 20, rz: -1.5, s: 1.72, fx: 960, fy: 40, tx: 150, ty: -70)),
        Move(time: pulls, duration: 0.65, ease: expoOut, pose: Pose(rx: -9, ry: -13, rz: 1.5, s: 1.14, fx: 960, fy: 320, tx: -160, ty: -150), whoosh: 0.9),
        Move(time: pulls + 0.65, duration: close2 - pulls - 0.7, ease: sine, pose: Pose(rx: -6, ry: -7, rz: 0.5, s: 1.2, fx: 960, fy: 320, tx: -160, ty: -145)),
        // Done: from below, slowly turning.
        Move(time: close2, duration: 0.65, ease: expoOut, pose: Pose(rx: 34, ry: 0, rz: -6, s: 1.75, fx: 960, fy: 40, tx: 0, ty: -150), whoosh: 0.9),
        Move(time: close2 + 0.65, duration: idle - close2 - 0.7, ease: sine, pose: Pose(rx: 27, ry: 0, rz: 3, s: 1.88, fx: 960, fy: 40, tx: 0, ty: -150)),
        // And into the notch.
        Move(time: idle, duration: 0.6, ease: expoIn, pose: inNotch, whoosh: 1.3),
    ]
}()

func pose(at t: Double) -> Pose {
    var current = moves[0].pose
    for move in moves.dropFirst() where t >= move.time {
        let x = move.duration <= 0 ? 1 : move.ease(progress(t, move.time, move.time + move.duration))
        current = Pose.mix(current, move.pose, x)
    }
    // A small punch on every click.
    for click in clickTimes { current.s *= 1 + 0.03 * sin(.pi * progress(t, click, click + 0.22)) }
    return current
}

/// Where a point of the plane lands in the picture.
func project(_ point: CGPoint, _ pose: Pose) -> CGPoint {
    let distance = 2000.0
    var x = (point.x - pose.fx) * pose.s, y = (point.y - pose.fy) * pose.s, z = 0.0
    let rz = pose.rz * .pi / 180, rx = pose.rx * .pi / 180, ry = pose.ry * .pi / 180
    (x, y) = (x * cos(rz) - y * sin(rz), x * sin(rz) + y * cos(rz))
    (y, z) = (y * cos(rx) - z * sin(rx), y * sin(rx) + z * cos(rx))
    (x, z) = (x * cos(ry) + z * sin(ry), -x * sin(ry) + z * cos(ry))
    let k = distance / max(distance + z, 50)
    return CGPoint(x: width / 2 + pose.tx + x * k, y: height / 2 + pose.ty + y * k)
}

func corners(_ pose: Pose) -> [CGPoint] {
    [CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: width, y: height), CGPoint(x: 0, y: height)].map { project($0, pose) }
}

// MARK: - The plane: notch, island, an abstract terminal and a cursor

/// The island frame sits at (440, 0) on the plane, so a point in a frame is offset by 440.
func island(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: 440 + x, y: y) }

func drawNotch(_ context: CGContext) {
    let path = CGMutablePath()
    let left = 960.0 - 185, right = 960.0 + 185, bottom = 64.0, radius = 22.0, flare = 12.0
    path.move(to: CGPoint(x: left - flare, y: 0))
    path.addQuadCurve(to: CGPoint(x: left, y: flare), control: CGPoint(x: left, y: 0))
    path.addLine(to: CGPoint(x: left, y: bottom - radius))
    path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
    path.addLine(to: CGPoint(x: right - radius, y: bottom))
    path.addQuadCurve(to: CGPoint(x: right, y: bottom - radius), control: CGPoint(x: right, y: bottom))
    path.addLine(to: CGPoint(x: right, y: flare))
    path.addQuadCurve(to: CGPoint(x: right + flare, y: 0), control: CGPoint(x: right, y: 0))
    path.closeSubpath()
    context.addPath(path)
    context.setFillColor(ink)
    context.fillPath()
}

let terminalIn = event("jump") + 0.1, terminalOut = event("pull-alert") - 0.42

/// The thread's own tab, as shapes: tabs as pills, lines of output as bars.
func drawTerminal(_ context: CGContext, _ t: Double) {
    let appear = progress(t, terminalIn, terminalIn + 0.5), leave = expoIn(progress(t, terminalOut, terminalOut + 0.3))
    guard appear > 0, leave < 1 else { return }
    let frame = CGRect(x: 420, y: 160 + (1 - backOut(appear)) * 260 + leave * 120, width: 1080, height: 600)
    context.saveGState()
    context.setAlpha(clamp(appear * 3) * (1 - leave))
    context.fill(frame, radius: 30, color: ink)
    for index in 0..<3 {
        context.setFillColor(white(0.22))
        context.fillEllipse(in: CGRect(x: frame.minX + 30 + Double(index) * 34, y: frame.minY + 28, width: 18, height: 18))
    }
    // The click lands on the thread's own tab.
    let tabWidth = 190.0, tabGap = 14.0, tabsX = frame.midX - (tabWidth * 3 + tabGap * 2) / 2
    let slide = expoInOut(progress(t, terminalIn + 0.35, terminalIn + 0.75))
    for index in 0..<3 {
        context.fill(CGRect(x: tabsX + Double(index) * (tabWidth + tabGap), y: frame.minY + 22, width: tabWidth, height: 30), radius: 15, color: white(0.1))
    }
    context.fill(CGRect(x: tabsX + slide * (tabWidth + tabGap), y: frame.minY + 22, width: tabWidth, height: 30), radius: 15, color: white(0.92))

    let rows: [(indent: Double, width: Double, color: CGColor)] = [
        (0, 300, white(0.3)), (0, 0, white(0)), (0, 420, white(0.9)), (0, 560, white(0.45)), (0, 640, white(0.3)), (40, 140, white(0.22)),
        (0, 520, white(0.3)), (40, 200, white(0.22)), (0, 0, white(0)), (0, 380, accent),
    ]
    for (index, row) in rows.enumerated() where row.width > 0 {
        let start = terminalIn + 0.45 + Double(index) * 0.13
        let grow = expoOut(progress(t, start, start + 0.5))
        guard grow > 0 else { continue }
        let y = frame.minY + 110 + Double(index) * 46
        if row.indent == 0 {
            let isAccent = row.color == accent
            let pulse = isAccent ? 1 + 0.25 * sin(t * 7) : 1
            context.setFillColor(isAccent ? accent : white(index == 2 ? 0.9 : 0.3))
            context.fillEllipse(in: CGRect(x: frame.minX + 58 - 8 * pulse, y: y + 12 - 8 * pulse, width: 16 * pulse, height: 16 * pulse))
        }
        context.fill(CGRect(x: frame.minX + 86 + row.indent, y: y + 2, width: row.width * grow, height: 20), radius: 10, color: row.color)
    }
    context.restoreGState()
}

struct Gesture {
    let appear: Double, from: CGPoint
    let arrive: Double, to: CGPoint
    let click: Double
    let leave: Double, away: CGPoint
    let gone: Double
}

let gestures = [
    Gesture(appear: event("open", 0) + 1.5, from: CGPoint(x: 1440, y: 760), arrive: event("allow") - 0.55, to: island(755, 374), click: event("allow") - 0.14,
            leave: event("allow") + 0.2, away: CGPoint(x: 1300, y: 560), gone: event("allow") + 0.6),
    Gesture(appear: event("open", 1) + 1.0, from: CGPoint(x: 1180, y: 720), arrive: event("pick") - 0.5, to: island(343, 244), click: event("pick") - 0.08,
            leave: event("answer") + 0.1, away: CGPoint(x: 900, y: 540), gone: event("answer") + 0.5),
    Gesture(appear: event("threads") + 4.5, from: CGPoint(x: 1320, y: 720), arrive: event("jump") - 0.8, to: island(380, 291), click: event("jump") - 0.14,
            leave: event("jump") + 0.1, away: island(395, 300), gone: event("jump") + 0.4),
]

let clickTimes = gestures.map(\.click)

let arrow: CGPath = {
    let path = CGMutablePath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 38), CGPoint(x: 10, y: 29), CGPoint(x: 17, y: 44),
                            CGPoint(x: 24, y: 41), CGPoint(x: 17, y: 26), CGPoint(x: 29, y: 26)])
    path.closeSubpath()
    return path
}()

func drawCursor(_ context: CGContext, _ t: Double) {
    guard let gesture = gestures.first(where: { t >= $0.appear && t <= $0.gone }) else { return }
    let travel = expoInOut(progress(t, gesture.appear, gesture.arrive))
    var point = mix(gesture.from, gesture.to, travel)
    point = mix(point, gesture.away, expoIn(progress(t, gesture.leave, gesture.gone)))
    let alpha = progress(t, gesture.appear, gesture.appear + 0.15) * (1 - progress(t, gesture.gone - 0.2, gesture.gone))
    let press = 1 - 0.18 * sin(.pi * progress(t, gesture.click - 0.05, gesture.click + 0.12))

    let ripple = progress(t, gesture.click, gesture.click + 0.4)
    if ripple > 0, ripple < 1 {
        let radius = mix(6, 54, expoOut(ripple))
        context.setStrokeColor(rgb(0.05, 0.05, 0.05, 0.8 * (1 - ripple)))
        context.setLineWidth(4)
        context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
    context.saveGState()
    context.setAlpha(alpha)
    context.translateBy(x: point.x, y: point.y)
    context.scaleBy(x: press, y: press)
    context.addPath(arrow)
    context.setFillColor(ink)
    context.setStrokeColor(white(1))
    context.setLineWidth(3)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)
    context.restoreGState()
}

func renderPlane(_ t: Double, scale: Double) -> CGImage {
    let context = makeContext(Int(width * scale), Int(height * scale))
    context.scaleBy(x: scale, y: scale)
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.addPath(CGPath(roundedRect: bounds, cornerWidth: 44, cornerHeight: 44, transform: nil))
    context.clip()
    context.setFillColor(plane)
    context.fill(bounds)
    drawTerminal(context, t)
    drawNotch(context)
    if let frame = islandFrame(at: t) { context.draw(image: frame, in: CGRect(x: 440, y: 0, width: frame.width, height: frame.height)) }
    drawCursor(context, t)
    return context.makeImage()!
}

// MARK: - Type, cards and wipes

struct Caption {
    let title: String, subtitle: String?
    let start: Double, end: Double
    let align: Align
    var accentWords: Set<Int> = []
}

let captions = [
    Caption(title: "Three need you.", subtitle: nil, start: event("dot") + 0.7, end: event("permission") - 0.3, align: .right, accentWords: [0]),
    Caption(title: "Approve from the notch.", subtitle: "Allow, Always or Decline. No window switching.", start: event("open", 0) + 0.35,
            end: event("close", 0) - 0.15, align: .left),
    Caption(title: "Answer its questions.", subtitle: "Pick an option, or type your own.", start: event("open", 1) + 0.4,
            end: event("close", 1) - 0.15, align: .right),
    Caption(title: "Every thread at a glance.", subtitle: "Working, waiting, subagents, branches.", start: event("threads") + 0.5,
            end: event("jump") - 0.3, align: .left),
    Caption(title: "One click. Its own tab.", subtitle: "Terminal, iTerm, VS Code, Cursor or the Claude app.", start: event("jump") + 0.45,
            end: event("pull-alert") - 0.55, align: .right),
    Caption(title: "Knows when CI fails.", subtitle: "Failed checks and requested changes, via gh.", start: event("pull-alert") + 0.35,
            end: event("close", 2) - 0.2, align: .left),
    Caption(title: "And when it’s done.", subtitle: nil, start: event("done") + 0.35, end: event("idle", 1) - 0.1, align: .center),
]

let titleFont = font(104, .bold), subtitleFont = font(34, .medium), cardFont = font(150, .bold)

func drawCaptions(_ context: CGContext, _ t: Double) {
    for caption in captions where t > caption.start && t < caption.end + 0.6 {
        let x = caption.align == .left ? 110.0 : caption.align == .right ? width - 110 : width / 2
        let baseline = caption.subtitle == nil ? 975.0 : 935.0
        kinetic(caption.title, in: context, t: t, x: x, y: baseline, font: titleFont, color: ink, align: caption.align,
                start: caption.start, end: caption.end, kern: -3.5, accentWords: caption.accentWords)
        if let subtitle = caption.subtitle {
            kinetic(subtitle, in: context, t: t, x: x, y: 990, font: subtitleFont, color: muted, align: caption.align,
                    start: caption.start + 0.25, end: caption.end, stagger: 0.02)
        }
    }
}

/// A black card with one line of big type, cut in, wiped in on a slant, or opened as an iris.
struct Card {
    enum Shape { case cut, slant, iris }
    let text: String
    let enter: Double, exit: Double
    let shape: Shape
}

let cards = [
    Card(text: "Four agents.", enter: 0, exit: event("dot") + 0.25, shape: .cut),
    Card(text: "No window switching.", enter: event("close", 0) + 0.14, exit: event("question") - 0.32, shape: .slant),
    Card(text: "All your threads.", enter: event("close", 1) + 0.14, exit: event("threads") - 0.16, shape: .iris),
]

func cardPath(_ card: Card, _ t: Double) -> CGPath? {
    let full = CGRect(x: 0, y: 0, width: width, height: height)
    switch card.shape {
    case .cut:
        return t >= card.enter && t < card.exit ? CGPath(rect: full, transform: nil) : nil
    case .slant:
        let enter = expoInOut(progress(t, card.enter, card.enter + 0.36)), exit = expoInOut(progress(t, card.exit, card.exit + 0.4))
        guard enter > 0, exit < 1 else { return nil }
        let left = mix(width + 100, -300, enter) + mix(0, -(width + 400), exit)
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: left + 250, y: 0), CGPoint(x: left + width + 600, y: 0),
                                CGPoint(x: left + width + 350, y: height), CGPoint(x: left, y: height)])
        path.closeSubpath()
        return path
    case .iris:
        let enter = expoIn(progress(t, card.enter, card.enter + 0.4)), exit = expoOut(progress(t, card.exit, card.exit + 0.5))
        guard enter > 0, exit < 1 else { return nil }
        let center = CGPoint(x: width / 2, y: 300), radius = 2300 * enter, hole = 2300 * exit
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if hole > 0 { path.addEllipse(in: CGRect(x: width / 2 - hole, y: height / 2 - hole, width: hole * 2, height: hole * 2)) }
        return path
    }
}

func drawCards(_ context: CGContext, _ t: Double) {
    for card in cards {
        guard let path = cardPath(card, t) else { continue }
        context.saveGState()
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.setFillColor(ink)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let textStart = card.shape == .cut ? card.enter + 0.12 : card.enter + 0.22
        kinetic(card.text, in: context, t: t, x: width / 2, y: 590, font: cardFont, color: white(1), align: .center,
                start: textStart, end: card.exit - (card.shape == .cut ? 0.32 : 0.2), kern: -5, stagger: 0.07)
        context.restoreGState()
    }
}

let endStart = event("idle", 1) + 0.78

func drawEndCard(_ context: CGContext, _ t: Double) {
    guard t >= endStart else { return }
    context.setFillColor(ink)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // The mark: a small island with its dot.
    let mark = expoOut(progress(t, endStart + 0.1, endStart + 0.7))
    if mark > 0 {
        let size = CGSize(width: 220 * mix(0.5, 1, mark), height: 46 * mix(0.5, 1, mark))
        let rect = CGRect(x: width / 2 - size.width / 2, y: 330, width: size.width, height: size.height)
        context.saveGState()
        context.setAlpha(clamp(mark * 2))
        context.fill(rect, radius: size.height / 2, color: white(1))
        let dot = 18 * mix(0.5, 1, mark)
        context.setFillColor(accent)
        context.fillEllipse(in: CGRect(x: rect.maxX - size.height / 2 - dot / 2 - 4, y: rect.midY - dot / 2, width: dot, height: dot))
        context.restoreGState()
    }
    kinetic("Kerf", in: context, t: t, x: width / 2, y: 610, font: font(210, .heavy), color: white(1), align: .center,
            start: endStart + 0.35, end: 99, kern: -7)
    kinetic("Your agents live in the notch.", in: context, t: t, x: width / 2, y: 715, font: font(62, .semibold), color: white(0.92),
            align: .center, start: endStart + 0.85, end: 99, kern: -1.5, stagger: 0.06)
    kinetic("For Claude Code and GitHub Copilot  ·  macOS 26", in: context, t: t, x: width / 2, y: 790, font: font(30, .medium),
            color: white(0.45), align: .center, start: endStart + 1.5, end: 99, stagger: 0.02)
}

func renderOverlay(_ t: Double) -> CGImage {
    let context = makeContext(Int(width), Int(height))
    drawCaptions(context, t)
    drawCards(context, t)
    drawEndCard(context, t)
    let fade = progress(t, duration - 0.5, duration)
    if fade > 0 {
        context.setFillColor(rgb(0.05, 0.05, 0.05, fade))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return context.makeImage()!
}

// MARK: - Frame

let outRect = CGRect(x: 0, y: 0, width: width, height: height)

func toCI(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: height - point.y) }

func render(_ t: Double) -> CIImage {
    let current = pose(at: t)
    let scale = clamp(current.s, 1, 2)
    let quad = corners(current)
    let perspective = CIFilter.perspectiveTransform()
    perspective.inputImage = CIImage(cgImage: renderPlane(t, scale: scale))
    perspective.topLeft = toCI(quad[0])
    perspective.topRight = toCI(quad[1])
    perspective.bottomRight = toCI(quad[2])
    perspective.bottomLeft = toCI(quad[3])
    var plane = perspective.outputImage!

    // Motion blur from how far the plane moved since the last frame.
    let previous = pose(at: t - 1 / Double(fps))
    let zoom = abs(log(current.s / previous.s))
    let before = corners(previous)
    let dx = zip(quad, before).map { $0.x - $1.x }.reduce(0, +) / 4, dy = zip(quad, before).map { $0.y - $1.y }.reduce(0, +) / 4
    if zoom > 0.015 {
        let blur = CIFilter.zoomBlur()
        blur.inputImage = plane
        blur.center = toCI(project(CGPoint(x: current.fx, y: current.fy), current))
        blur.amount = Float(min(zoom * 260, 45))
        plane = blur.outputImage!
    } else if hypot(dx, dy) > 5 {
        let blur = CIFilter.motionBlur()
        blur.inputImage = plane
        blur.radius = Float(min(hypot(dx, dy) * 0.7, 40))
        blur.angle = Float(atan2(-dy, dx))
        plane = blur.outputImage!
    }

    let tint = CIFilter.colorMatrix()
    tint.inputImage = plane
    tint.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    tint.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    tint.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    tint.biasVector = CIVector(x: shadowTone.r, y: shadowTone.g, z: shadowTone.b, w: 0)
    let shadow = tint.outputImage!.transformed(by: CGAffineTransform(translationX: 26, y: -34))

    let background = CIImage(color: CIColor(cgColor: ground)).cropped(to: outRect)
    let picture = plane.composited(over: shadow.composited(over: background))
    return CIImage(cgImage: renderOverlay(t)).composited(over: picture).cropped(to: outRect)
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

if let stills {
    for t in stills {
        let image = ciContext.createCGImage(render(t), from: outRect)!
        writePNG(image, to: outDirectory.appendingPathComponent(String(format: "still-%05.2f.png", t)))
    }
    exit(0)
}

// MARK: - Sound

let rate = 48_000
let sampleCount = Int(duration * Double(rate))
var left = [Float](repeating: 0, count: sampleCount), right = [Float](repeating: 0, count: sampleCount)
var noiseState: UInt32 = 0x2545F491

func noise() -> Double {
    noiseState ^= noiseState << 13; noiseState ^= noiseState >> 17; noiseState ^= noiseState << 5
    return Double(noiseState) / Double(UInt32.max) * 2 - 1
}

/// Adds `length` seconds of `sample(t)` at `start`, panned (-1 left … 1 right).
func add(at start: Double, length: Double, pan: Double = 0, _ sample: (Double) -> Double) {
    let first = Int(start * Double(rate))
    let gainLeft = Float(cos((pan + 1) * .pi / 4)), gainRight = Float(sin((pan + 1) * .pi / 4))
    for i in 0..<Int(length * Double(rate)) where first + i >= 0 && first + i < sampleCount {
        let value = Float(sample(Double(i) / Double(rate)))
        left[first + i] += value * gainLeft
        right[first + i] += value * gainRight
    }
}

func click(at time: Double) {
    var low = 0.0
    add(at: time, length: 0.09, pan: 0.1) { t in
        low += (noise() - low) * 0.5
        let snap = (noise() - low) * exp(-t / 0.004) * 0.35
        let body = sin(2 * .pi * 2900 * t) * exp(-t / 0.012) * 0.22 + sin(2 * .pi * 950 * t) * exp(-t / 0.03) * 0.16
        return snap + body
    }
}

/// Filtered noise that sweeps up and back down, for the camera's quick moves.
func whoosh(at time: Double, gain: Double, length: Double = 0.5, pan: Double = 0) {
    var low = 0.0, lower = 0.0
    add(at: time - 0.08, length: length, pan: clamp(pan, -0.8, 0.8)) { t in
        let x = t / length
        let cutoff = 300 + 3200 * sin(.pi * x)
        let k = 1 - exp(-2 * .pi * cutoff / Double(rate))
        low += (noise() - low) * k
        lower += (low - lower) * k
        return lower * sin(.pi * pow(x, 0.7)) * gain * 0.35
    }
}

func thump(at time: Double, gain: Double = 0.3) {
    add(at: time, length: 0.35) { t in
        let f = 48 + 70 * exp(-t / 0.03)
        return sin(2 * .pi * f * t) * exp(-t / 0.09) * gain
    }
}

func tone(at time: Double, frequencies: [Double], decay: Double, gain: Double, attack: Double = 0.004, pan: Double = 0, glide: Double = 0) {
    add(at: time, length: decay * 6, pan: pan) { t in
        let envelope = min(1, t / attack) * exp(-t / decay)
        var sum = 0.0
        for (index, frequency) in frequencies.enumerated() {
            sum += sin(2 * .pi * frequency * (1 + glide * min(1, t / 0.06)) * t) / Double(index + 1)
        }
        return sum * envelope * gain
    }
}

func pop(at time: Double) { tone(at: time, frequencies: [880, 1760], decay: 0.07, gain: 0.16, glide: 0.5) }

thump(at: cards[0].enter + 0.12, gain: 0.35)
for move in moves where move.whoosh > 0 { whoosh(at: move.time, gain: move.whoosh, length: max(0.4, min(move.duration, 0.7)), pan: move.pose.tx / 600) }
pop(at: cards[0].exit + 0.05)
pop(at: event("permission"))
for card in cards.dropFirst() {
    whoosh(at: card.enter, gain: 0.8, length: 0.45, pan: card.shape == .slant ? 0.4 : 0)
    thump(at: card.enter + 0.3)
    whoosh(at: card.exit, gain: 0.7, length: 0.45, pan: card.shape == .slant ? -0.4 : 0)
}
pop(at: event("question"))
for time in clickTimes { click(at: time) }
tone(at: event("pull-alert"), frequencies: [660, 1320], decay: 0.12, gain: 0.13, pan: -0.1)
tone(at: event("pull-alert") + 0.16, frequencies: [523, 1046], decay: 0.18, gain: 0.12, pan: 0.1)
tone(at: event("done"), frequencies: [1046.5, 2093], decay: 0.45, gain: 0.12, pan: -0.15)
tone(at: event("done") + 0.09, frequencies: [1568, 3136], decay: 0.6, gain: 0.1, pan: 0.15)
thump(at: endStart, gain: 0.4)
pop(at: endStart + 0.15)
// The end card: a soft major-seventh bloom.
for (index, frequency) in [130.8, 196.0, 261.6, 329.6, 392.0, 493.9].enumerated() {
    tone(at: endStart + 0.35 + Double(index) * 0.03, frequencies: [frequency], decay: 1.4, gain: 0.07, attack: 0.5, pan: index % 2 == 0 ? -0.3 : 0.3)
}

// A little room: a few early reflections, crossed between the channels.
let dryLeft = left, dryRight = right
for (delay, gain) in [(0.031, 0.22), (0.047, 0.18), (0.067, 0.14), (0.089, 0.1), (0.121, 0.07)] {
    let offset = Int(delay * Double(rate))
    for i in offset..<sampleCount {
        left[i] += dryRight[i - offset] * Float(gain)
        right[i] += dryLeft[i - offset] * Float(gain)
    }
}
let peak = max(left.map(abs).max() ?? 1, right.map(abs).max() ?? 1)
let normalize = Float(0.7) / max(peak, 0.0001)
for i in 0..<sampleCount { left[i] *= normalize; right[i] *= normalize }

func writeAudio(to url: URL, settings: [String: Any]) throws {
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2)!
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    var position = 0
    while position < sampleCount {
        let count = min(4096, sampleCount - position)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            buffer.floatChannelData![0][i] = left[position + i]
            buffer.floatChannelData![1][i] = right[position + i]
        }
        try file.write(from: buffer)
        position += count
    }
}

let wavSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                                  AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
try writeAudio(to: outDirectory.appendingPathComponent("sfx.wav"), settings: wavSettings)
let sfxLeft = left, sfxRight = right

// MARK: - Voice-over (ElevenLabs)

/// A line of voice-over: it starts at `start` and should be over by `end`.
struct Line { let text: String; let start: Double; let end: Double }

let voiceLines = [
    Line(text: "You run four agents.", start: 0.15, end: event("dot") + 0.35),
    Line(text: "Three of them are waiting on you. Which ones?", start: event("dot") + 0.5, end: event("open", 0) - 0.05),
    Line(text: "Kerf puts their requests right in the notch. One click.", start: event("open", 0) + 0.3, end: event("close", 0) + 0.15),
    Line(text: "No window switching.", start: cards[1].enter + 0.3, end: cards[1].exit + 0.1),
    Line(text: "Questions too. Pick an answer, back to work.", start: event("open", 1) + 0.35, end: event("close", 1) + 0.15),
    Line(text: "And all your threads,", start: cards[2].enter + 0.3, end: cards[2].exit + 0.2),
    Line(text: "working, waiting or done, with their subagents and branches, at a glance.", start: event("threads") + 0.8, end: event("jump") - 0.2),
    Line(text: "One click, and you're in its own terminal tab or editor.", start: event("jump") + 0.45, end: event("pull-alert") - 0.1),
    Line(text: "It even tells you when CI fails, or a reviewer wants changes.", start: event("pull-alert") + 0.45, end: event("close", 2)),
    Line(text: "And when an agent is done, you'll know.", start: event("done") + 0.35, end: event("idle", 1) + 0.5),
    Line(text: "Kerf. Your agents live in the notch.", start: endStart + 0.55, end: duration - 0.5),
]

let voiceDirectory = outDirectory.appendingPathComponent("vo")

func clipURL(_ index: Int) -> URL { voiceDirectory.appendingPathComponent(String(format: "%02d.mp3", index + 1)) }

func audioDuration(_ url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    return Double(file.length) / file.fileFormat.sampleRate
}

/// A setting from the environment, else from the repository's .env.
func setting(_ name: String) -> String? {
    if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
    let env = (try? String(contentsOfFile: ".env", encoding: .utf8)) ?? ""
    for line in env.split(separator: "\n") where line.hasPrefix("\(name)=") {
        return String(line.dropFirst(name.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
    return nil
}

/// The global API, or the data residency stack the key belongs to (ELEVENLABS_BASE_URL skips the search).
var elevenLabsBase = setting("ELEVENLABS_BASE_URL") ?? "https://api.elevenlabs.io"

func findBase(key: String) {
    guard setting("ELEVENLABS_BASE_URL") == nil else { return }
    for base in ["https://api.elevenlabs.io", "https://api.eu.residency.elevenlabs.io", "https://api.in.residency.elevenlabs.io",
                 "https://api.sg.residency.elevenlabs.io"] {
        var request = URLRequest(url: URL(string: base + "/v1/models")!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        var status = 0
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.signal()
        }.resume()
        done.wait()
        if status == 200 {
            elevenLabsBase = base
            print("ElevenLabs: \(base)")
            return
        }
    }
}

func elevenLabs(_ path: String, key: String, body: [String: Any]? = nil) -> Data {
    var request = URLRequest(url: URL(string: elevenLabsBase + path)!)
    request.httpMethod = body == nil ? "GET" : "POST"
    request.setValue(key, forHTTPHeaderField: "xi-api-key")
    if let body {
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { result = ($0, $1, $2); done.signal() }.resume()
    done.wait()
    let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
    guard let data = result.0, status == 200 else {
        let message = result.0.flatMap { String(data: $0, encoding: .utf8) } ?? result.2?.localizedDescription ?? "no response"
        fatalError("ElevenLabs \(path) failed (\(status)): \(message)")
    }
    return data
}

/// A calm male narrator from the premade voices, unless ELEVENLABS_VOICE_ID says otherwise.
func pickVoice(key: String) -> String {
    if let id = setting("ELEVENLABS_VOICE_ID") { return id }
    let json = try! JSONSerialization.jsonObject(with: elevenLabs("/v1/voices", key: key)) as! [String: Any]
    let voices = json["voices"] as? [[String: Any]] ?? []
    for wanted in ["Brian", "George", "Daniel", "Bill"] {
        if let voice = voices.first(where: { ($0["name"] as? String)?.hasPrefix(wanted) == true }), let id = voice["voice_id"] as? String {
            print("voice: \(voice["name"] as? String ?? id)")
            return id
        }
    }
    fatalError("No calm male premade voice found; set ELEVENLABS_VOICE_ID.")
}

if fetchesVoiceover {
    guard let key = setting("ELEVENLABS_API_KEY") else { fatalError("Set ELEVENLABS_API_KEY in the environment or in .env.") }
    findBase(key: key)
    try? FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
    let voice = pickVoice(key: key)
    for (index, line) in voiceLines.enumerated() {
        let url = clipURL(index), noteURL = url.deletingPathExtension().appendingPathExtension("txt")
        let slot = line.end - line.start
        var speed = 1.0
        for attempt in 0..<3 {
            let note = "\(voice) \(speed) \(line.text)"
            if (try? String(contentsOf: noteURL, encoding: .utf8)) != note {
                let body: [String: Any] = [
                    "text": line.text, "model_id": "eleven_multilingual_v2",
                    "previous_text": index > 0 ? voiceLines[index - 1].text : "", "next_text": index + 1 < voiceLines.count ? voiceLines[index + 1].text : "",
                    "voice_settings": ["stability": 0.55, "similarity_boost": 0.8, "style": 0.15, "use_speaker_boost": true, "speed": speed],
                ]
                try elevenLabs("/v1/text-to-speech/\(voice)?output_format=mp3_44100_128", key: key, body: body).write(to: url)
                try note.write(to: noteURL, atomically: true, encoding: .utf8)
            }
            let length = audioDuration(url) ?? 0
            print(String(format: "line %2d: %.2f s of %.2f s at speed %.2f", index + 1, length, slot, speed))
            // Too long for its slot: a little faster, but never rushed.
            guard length > slot, attempt < 2, speed < 1.15 else { break }
            speed = min(1.15, speed * length / slot * 1.02)
        }
    }
}

// MARK: - Music and the mix

/// Any audio file as 48 kHz stereo samples.
func loadAudio(_ url: URL) -> ([Float], [Float])? {
    guard let file = try? AVAudioFile(forReading: url),
          let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: source)) != nil else { return nil }
    let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2)!
    let converter = AVAudioConverter(from: file.processingFormat, to: format)!
    let capacity = AVAudioFrameCount(Double(source.frameLength) * Double(rate) / file.processingFormat.sampleRate) + 4096
    let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
    var fed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return source
    }
    guard error == nil else { return nil }
    let count = Int(output.frameLength)
    return (Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: count)),
            Array(UnsafeBufferPointer(start: output.floatChannelData![1], count: count)))
}

var voiceLeft = [Float](repeating: 0, count: sampleCount), voiceRight = [Float](repeating: 0, count: sampleCount)
var voiceCount = 0
for (index, line) in voiceLines.enumerated() {
    guard let (clipLeft, clipRight) = loadAudio(clipURL(index)) else { continue }
    voiceCount += 1
    let first = Int(line.start * Double(rate))
    for i in 0..<clipLeft.count where first + i < sampleCount {
        voiceLeft[first + i] += clipLeft[i]
        voiceRight[first + i] += clipRight[i]
    }
}
let voicePeak = max(voiceLeft.map(abs).max() ?? 0, voiceRight.map(abs).max() ?? 0)
if voicePeak > 0 { for i in 0..<sampleCount { voiceLeft[i] *= 0.85 / voicePeak; voiceRight[i] *= 0.85 / voicePeak } }

let musicURL = ["mp3", "m4a", "mp4", "wav", "aiff", "aif", "flac"].map { outDirectory.appendingPathComponent("music.\($0)") }
    .first { FileManager.default.fileExists(atPath: $0.path) }
var musicLeft = [Float](repeating: 0, count: sampleCount), musicRight = [Float](repeating: 0, count: sampleCount)
if let musicURL, let (trackLeft, trackRight) = loadAudio(musicURL) {
    // The track's last hit lands on the end card: shorter tracks come in later, longer ones skip
    // part of their intro.
    let last = trackLeft.indices.last { abs(trackLeft[$0]) > 0.02 || abs(trackRight[$0]) > 0.02 } ?? trackLeft.count - 1
    let offset = Int(endStart * Double(rate)) - last
    var power = 0.0, counted = 0
    for i in max(0, -offset)..<trackLeft.count where i + offset < sampleCount {
        power += Double(trackLeft[i] * trackLeft[i] + trackRight[i] * trackRight[i]) / 2
        counted += 1
    }
    // Level by loudness, not peaks: about -24 dBFS RMS under everything else.
    let gain = Float(0.063 / max(sqrt(power / Double(max(counted, 1))), 0.0001))
    for i in max(0, -offset)..<trackLeft.count where i + offset < sampleCount {
        let fade = Float(min(1, Double(i - max(0, -offset)) / Double(rate) / 0.6))
        musicLeft[i + offset] = trackLeft[i] * gain * fade
        musicRight[i + offset] = trackRight[i] * gain * fade
    }
    print(String(format: "music: %@ from %.2f s, last hit at %.2f s", musicURL.lastPathComponent, max(0, Double(offset)) / Double(rate),
                 Double(last + offset) / Double(rate)))
}

// The music steps back while the voice speaks.
let window = rate / 100
var duck = [Float](repeating: 1, count: sampleCount)
var level: Float = 1
for start in stride(from: 0, to: sampleCount, by: window) {
    var power: Float = 0
    for i in start..<min(start + window, sampleCount) { power += voiceLeft[i] * voiceLeft[i] }
    let speaking = sqrt(power / Float(window)) > 0.02
    let target: Float = speaking ? 0.42 : 1
    let coefficient: Float = target < level ? 0.25 : 0.03
    for i in start..<min(start + window, sampleCount) {
        level += (target - level) * coefficient / Float(window)
        duck[i] = level
    }
}

let sfxGain: Float = voiceCount > 0 || musicURL != nil ? 0.6 : 1
for i in 0..<sampleCount {
    left[i] = musicLeft[i] * duck[i] + sfxLeft[i] * sfxGain + voiceLeft[i]
    right[i] = musicRight[i] * duck[i] + sfxRight[i] * sfxGain + voiceRight[i]
}
// Loud enough for a feed (about -16 dBFS RMS), with a look-ahead limiter keeping peaks under -1 dBFS.
var mixPower = 0.0
for i in 0..<sampleCount { mixPower += Double(left[i] * left[i] + right[i] * right[i]) / 2 }
let makeUp = Float(0.16 / max(sqrt(mixPower / Double(sampleCount)), 0.0001))
let ceiling: Float = 0.89, lookAhead = rate / 200, release: Float = 1 / (0.08 * Float(rate))
var needed = [Float](repeating: 1, count: sampleCount)
for i in 0..<sampleCount {
    let peak = max(abs(left[i]), abs(right[i])) * makeUp
    needed[i] = peak > ceiling ? ceiling / peak : 1
}
// The lowest gain any sample in the next few milliseconds needs, reached before it arrives.
var limiterGain: Float = 1
var window5ms = [Float](repeating: 1, count: sampleCount)
var deque: [Int] = []
var head = 0
for i in stride(from: sampleCount - 1, through: 0, by: -1) {
    while deque.count > head, needed[deque.last!] >= needed[i] { deque.removeLast() }
    deque.append(i)
    while deque[head] > i + lookAhead { head += 1 }
    window5ms[i] = needed[deque[head]]
}
for i in 0..<sampleCount {
    limiterGain = window5ms[i] < limiterGain ? window5ms[i] : min(window5ms[i], limiterGain + release)
    left[i] = max(-ceiling, min(ceiling, left[i] * makeUp * limiterGain))
    right[i] = max(-ceiling, min(ceiling, right[i] * makeUp * limiterGain))
}
try writeAudio(to: outDirectory.appendingPathComponent("mix.wav"), settings: wavSettings)
let m4aURL = outDirectory.appendingPathComponent("mix.m4a")
try writeAudio(to: m4aURL, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000])
if voiceCount > 0 {
    let mixLeft = left, mixRight = right
    left = voiceLeft
    right = voiceRight
    try writeAudio(to: outDirectory.appendingPathComponent("vo.wav"), settings: wavSettings)
    left = mixLeft
    right = mixRight
}
print("sound written: \(voiceCount) voice-over lines, music \(musicURL == nil ? "none" : "yes")")

// MARK: - Video

let silentURL = outDirectory.appendingPathComponent("kerf-promo-silent.mp4")
func renderVideo() throws {
    try? FileManager.default.removeItem(at: silentURL)
    let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(width), AVVideoHeightKey: Int(height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                          AVVideoExpectedSourceFrameRateKey: fps, AVVideoMaxKeyFrameIntervalKey: fps * 2],
        AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(width),
        kCVPixelBufferHeightKey as String: Int(height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let frameCount = Int(duration * Double(fps))
    for index in 0..<frameCount {
        autoreleasepool {
            while !input.isReadyForMoreMediaData { usleep(500) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { fatalError("no pixel buffer") }
            ciContext.render(render(Double(index) / Double(fps)), to: buffer, bounds: outRect, colorSpace: colorSpace)
            CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        }
        if index % 300 == 0 { print("frame \(index)/\(frameCount)") }
    }
    input.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { fatalError("video failed: \(String(describing: writer.error))") }
    print("video written")
}

if !(audioOnly && FileManager.default.fileExists(atPath: silentURL.path)) { try renderVideo() }

// MARK: - Mux

let composition = AVMutableComposition()
let videoAsset = AVURLAsset(url: silentURL), audioAsset = AVURLAsset(url: m4aURL)
let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try videoTrack.insertTimeRange(range, of: videoAsset.tracks(withMediaType: .video)[0], at: .zero)
let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
let audioSource = audioAsset.tracks(withMediaType: .audio)[0]
try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(range.duration, audioSource.timeRange.duration)), of: audioSource, at: .zero)
let finalURL = outDirectory.appendingPathComponent("kerf-promo.mp4")
try? FileManager.default.removeItem(at: finalURL)
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
export.outputURL = finalURL
export.outputFileType = .mp4
let exported = DispatchSemaphore(value: 0)
export.exportAsynchronously { exported.signal() }
exported.wait()
guard export.status == .completed else { fatalError("mux failed: \(String(describing: export.error))") }
print("done: \(finalURL.path)")
