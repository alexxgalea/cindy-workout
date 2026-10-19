import SwiftUI

/// Android's `ic_*` drawables, drawn from `Assets.xcassets/Icons` (which `tools/ios_icons.py`
/// writes). Every icon is a template image, tinted at the call site with `.foregroundStyle`,
/// except `checkFilled`, which keeps its own green.
enum CindyIcon: String, CaseIterable {
    case again = "ic_again"
    case check = "ic_check"
    case checkFilled = "ic_check_filled"
    case chevronLeft = "ic_chevron_left"
    case chevronRight = "ic_chevron_right"
    case dontMove = "ic_dont_move"
    case external = "ic_external"
    case flame = "ic_flame"
    case flip = "ic_flip"
    case frame = "ic_frame"
    case link = "ic_link"
    case menu = "ic_menu"
    case minus = "ic_minus"
    case music = "ic_music"
    case pause = "ic_pause"
    case phoneStand = "ic_phone_stand"
    case play = "ic_play"
    case plus = "ic_plus"
    case rec = "ic_rec"
    case ringEmpty = "ic_ring_empty"
    case skip = "ic_skip"
    case stop = "ic_stop"
    case voice = "ic_voice"
}

extension Image {
    /// The icon's image. Call sites add `.resizable()`, a frame and `.foregroundStyle(…)`.
    init(_ icon: CindyIcon) {
        self.init(icon.rawValue)
    }
}
