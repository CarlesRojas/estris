import SwiftUI

/// Measurements shared by settings panes, matched to the sidebar so content boxes line up
/// with it.
enum PaneStyle {
    /// Corner radius of the floating sidebar (macOS 26) and of the boxes beside it.
    static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { return 16 }
        return 10
    }

    /// Gap between the window's bottom edge and the sidebar's, so boxes end where it does.
    static var bottomInset: CGFloat {
        if #available(macOS 26, *) { return 8 }
        return 12
    }
}
