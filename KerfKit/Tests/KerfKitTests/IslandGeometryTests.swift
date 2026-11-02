import CoreGraphics
import Testing
@testable import KerfKit

struct IslandGeometryTests {
    let notch = IslandGeometry(style: .notch(CGSize(width: 185, height: 32)))
    let floating = IslandGeometry(style: .floating)

    @Test func idleHidesBehindTheNotch() {
        #expect(notch.idle == CGSize(width: 183, height: 31))
        #expect(floating.idle.height == 0)
    }

    @Test func compactAddsTwoWings() {
        #expect(notch.compact() == CGSize(width: 265, height: 32))
        #expect(notch.compact(wings: 60).width == 305)
        #expect(floating.compact().height == IslandGeometry.floatingCompactHeight)
    }

    @Test func cornersGrowWithHeight() {
        #expect(notch.cornerRadius(height: 32, openHeight: 186) == 8)
        #expect(notch.cornerRadius(height: 186, openHeight: 186) == 24)
        #expect(notch.cornerRadius(height: 109, openHeight: 186) == 16)
        #expect(floating.cornerRadius(height: 26, openHeight: 186) == 13)
    }

    @Test func earsOnlyOnceWiderThanTheNotch() {
        #expect(notch.ear(width: 183) == 0)
        #expect(notch.ear(width: 189) == 2)
        #expect(notch.ear(width: 265) == 6)
        #expect(floating.ear(width: 400) == 0)
    }
}

struct MenuBarRoomTests {
    // A 14" MacBook Pro: the notch from x 663 to 848.
    let notch = (min: CGFloat(663), max: CGFloat(848))

    @Test func fewMenusLeaveRoom() {
        let finder = [CGRect(x: 10, y: 0, width: 40, height: 24), CGRect(x: 60, y: 0, width: 50, height: 24),
                      CGRect(x: 1300, y: 0, width: 30, height: 24)]
        let room = MenuBarRoom.free(notchMinX: notch.min, notchMaxX: notch.max, items: finder)
        #expect(room == 452)
        #expect(MenuBarRoom.fits(wings: 40, in: room))
    }

    @Test func manyMenusRunUpToTheNotch() {
        // DaVinci Resolve: "Fusion" ends 4 pt before the notch, "Color" starts 6 pt after it.
        let resolve = [CGRect(x: 580, y: 0, width: 79, height: 24), CGRect(x: 854, y: 0, width: 60, height: 24)]
        let room = MenuBarRoom.free(notchMinX: notch.min, notchMaxX: notch.max, items: resolve)
        #expect(room == 4)
        #expect(!MenuBarRoom.fits(wings: 40, in: room))
    }

    @Test func itemsBehindTheNotchDontCount() {
        let hidden = [CGRect(x: 700, y: 0, width: 30, height: 24), CGRect(x: 1000, y: 0, width: 30, height: 24)]
        #expect(MenuBarRoom.free(notchMinX: notch.min, notchMaxX: notch.max, items: hidden) == 152)
        #expect(MenuBarRoom.free(notchMinX: notch.min, notchMaxX: notch.max, items: []) == .infinity)
    }
}
