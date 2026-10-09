import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import CindyCore

/// The athlete, as a circle: their photo when they have given one, the letters of their name when
/// they have only given a name, and a neutral figure when they have given neither.
///
/// One view is the whole avatar at every size, from the header of the menu to the top of the You
/// screen, and it stays monochrome: colour is kept for what the athlete has earned, so the letters
/// and the figure are white ramp on the glass, and a photo brings its own colours. It only draws.
/// A screen that makes it tappable names it to a screen reader itself.
struct AvatarView: View {
    let photo: UIImage?
    let name: String?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: side, height: side).clipShape(Circle())
                } else {
                    Circle().fill(Color.white.opacity(0.09))
                    let letters = Avatar.initials(name)
                    if letters.isEmpty {
                        // A head over a pair of shoulders, cut off by the disc: the sign for "somebody".
                        Image(systemName: "person.fill")
                            .resizable().scaledToFit().frame(width: side * 0.5, height: side * 0.5)
                            .offset(y: side * 0.08)
                            .foregroundStyle(Ink.tertiary)
                            .frame(width: side, height: side).clipShape(Circle())
                    } else {
                        Text(letters)
                            .font(.system(size: side * (letters.count > 1 ? 0.36 : 0.42), weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                Circle().strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        // Decoration by default: a row that holds one already says what it is.
        .accessibilityHidden(true)
    }
}

/// Makes the picture the athlete picked into the photo that is kept: decoded small, stood upright,
/// cut to its centred square and written as a JPEG on black. What to do is `Avatar`'s arithmetic;
/// this does it with ImageIO, which stands the picture upright from its orientation tag itself.
enum AvatarImporter {

    static let jpegQuality = 0.9

    /// The JPEG for `picture`, or nil when it is not a picture ImageIO can read.
    static func jpeg(from picture: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(picture as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        // Decode no bigger than the short side needs, so a twelve megapixel photo is never on the heap.
        let shortSide = min(width, height)
        let longSide = max(width, height)
        let wanted = max(Avatar.sizePx, Int((Double(longSide) * Double(Avatar.sizePx) / Double(shortSide)).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: wanted
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let square = Avatar.squareCrop(decoded.width, decoded.height)
        guard square.size > 0,
              let cut = decoded.cropping(to: CGRect(x: square.left, y: square.top, width: square.size, height: square.size))
        else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let side = CGFloat(Avatar.sizePx)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            // A JPEG has no transparency, so a PNG's clear pixels would come out as whatever colour
            // happened to be underneath them. The app is black; so is this.
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIImage(cgImage: cut).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return image.jpegData(compressionQuality: jpegQuality)
    }
}
