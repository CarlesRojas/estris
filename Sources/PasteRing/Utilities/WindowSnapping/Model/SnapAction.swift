import AppKit
import Carbon.HIToolbox

/// Where a window can be snapped to, on the screen it is on.
enum SnapAction: String, CaseIterable, Codable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case centerTwoThirds
    case lastTwoThirds
    case restore

    var id: Self { self }

    enum Group: CaseIterable {
        case halves, corners, thirds, other

        var title: String {
            switch self {
            case .halves: String(localized: "Halves")
            case .corners: String(localized: "Corners")
            case .thirds: String(localized: "Thirds")
            case .other: String(localized: "Other")
            }
        }
    }

    var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .corners
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: .thirds
        case .maximize, .restore: .other
        }
    }

    var title: String {
        switch self {
        case .leftHalf: String(localized: "Left Half")
        case .rightHalf: String(localized: "Right Half")
        case .topHalf: String(localized: "Top Half")
        case .bottomHalf: String(localized: "Bottom Half")
        case .topLeft: String(localized: "Top Left")
        case .topRight: String(localized: "Top Right")
        case .bottomLeft: String(localized: "Bottom Left")
        case .bottomRight: String(localized: "Bottom Right")
        case .maximize: String(localized: "Maximize")
        case .firstThird: String(localized: "Left Third")
        case .centerThird: String(localized: "Center Third")
        case .lastThird: String(localized: "Right Third")
        case .firstTwoThirds: String(localized: "Left Two Thirds")
        case .centerTwoThirds: String(localized: "Center Two Thirds")
        case .lastTwoThirds: String(localized: "Right Two Thirds")
        case .restore: String(localized: "Restore")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .maximize: "rectangle.fill"
        case .firstThird: "rectangle.leadingthird.inset.filled"
        // Drawn by `SnapActionIcon`: SF Symbols has no middle-third bar.
        case .centerThird: "rectangle"
        case .lastThird: "rectangle.trailingthird.inset.filled"
        case .firstTwoThirds: "rectangle.split.3x1"
        case .centerTwoThirds: "rectangle.split.3x1"
        case .lastTwoThirds: "rectangle.split.3x1"
        case .restore: "arrow.uturn.backward"
        }
    }

    /// The key each starts out with, used with Control and Option; changeable in Settings.
    var defaultKeyCode: UInt32 {
        let key = switch self {
        case .leftHalf: kVK_LeftArrow
        case .rightHalf: kVK_RightArrow
        case .topHalf: kVK_UpArrow
        case .bottomHalf: kVK_DownArrow
        case .topLeft: kVK_ANSI_U
        case .topRight: kVK_ANSI_I
        case .bottomLeft: kVK_ANSI_J
        case .bottomRight: kVK_ANSI_K
        case .maximize: kVK_Return
        case .firstThird: kVK_ANSI_D
        case .centerThird: kVK_ANSI_F
        case .lastThird: kVK_ANSI_G
        case .firstTwoThirds: kVK_ANSI_E
        case .centerTwoThirds: kVK_ANSI_R
        case .lastTwoThirds: kVK_ANSI_T
        case .restore: kVK_Delete
        }
        return UInt32(key)
    }

    /// The frame for a window on a screen, in AppKit coordinates; nil for Restore, which
    /// goes back to a remembered frame.
    func frame(in screen: NSScreen, current: NSRect) -> NSRect? {
        let area = screen.visibleFrame
        let halfWidth = (area.width / 2).rounded(.down)
        let halfHeight = (area.height / 2).rounded(.down)
        let third = (area.width / 3).rounded(.down)
        let rect: NSRect
        switch self {
        case .leftHalf: rect = NSRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .rightHalf: rect = NSRect(x: area.minX + halfWidth, y: area.minY, width: area.width - halfWidth, height: area.height)
        case .topHalf: rect = NSRect(x: area.minX, y: area.minY + halfHeight, width: area.width, height: area.height - halfHeight)
        case .bottomHalf: rect = NSRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .topLeft: rect = NSRect(x: area.minX, y: area.minY + halfHeight, width: halfWidth, height: area.height - halfHeight)
        case .topRight: rect = NSRect(x: area.minX + halfWidth, y: area.minY + halfHeight, width: area.width - halfWidth, height: area.height - halfHeight)
        case .bottomLeft: rect = NSRect(x: area.minX, y: area.minY, width: halfWidth, height: halfHeight)
        case .bottomRight: rect = NSRect(x: area.minX + halfWidth, y: area.minY, width: area.width - halfWidth, height: halfHeight)
        case .maximize: rect = area
        case .firstThird: rect = NSRect(x: area.minX, y: area.minY, width: third, height: area.height)
        case .centerThird: rect = NSRect(x: area.minX + third, y: area.minY, width: third, height: area.height)
        case .lastThird: rect = NSRect(x: area.minX + 2 * third, y: area.minY, width: area.width - 2 * third, height: area.height)
        case .firstTwoThirds: rect = NSRect(x: area.minX, y: area.minY, width: 2 * third, height: area.height)
        case .centerTwoThirds: rect = NSRect(x: area.minX + (third / 2).rounded(.down), y: area.minY, width: 2 * third, height: area.height)
        case .lastTwoThirds: rect = NSRect(x: area.minX + third, y: area.minY, width: area.width - third, height: area.height)
        case .restore: return nil
        }
        return rect
    }
}
