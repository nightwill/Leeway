import AppKit

/// The menu bar label, drawn as a single image.
///
/// Drawn rather than laid out, and that is not a preference. `MenuBarExtra`
/// renders the first piece of its label and silently drops the rest, so a title
/// built of several views — a stack, a `ForEach`, a flat row, concatenated text
/// carrying the dots as attachments — shows one provider and loses the other.
/// The menu bar also draws the label in its own face and ignores any the label
/// asks for, which is the second thing a drawn title gets back.
enum MenuBarTitle {

    /// One provider's piece of the title.
    struct Reading {
        /// The colour of the dot in front of the figures, or `nil` where the
        /// title is showing no dots at all.
        var tint: NSColor?
        var text: String
    }

    /// The menu bar's own size, and the same narrowed — about a quarter of the
    /// width back at the same reading size.
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let condensedFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular, width: .condensed)

    /// The readings side by side, each behind its own dot.
    ///
    /// `dark` is the appearance the menu bar is drawing in, which the caller has
    /// to say because it is not the app's: with a light system appearance and a
    /// dark desktop picture the menu bar turns dark on its own, and a title
    /// drawn in the app's colours comes out black on black.
    static func image(_ readings: [Reading], compact: Bool = false, dark: Bool) -> NSImage {
        let font = compact ? condensedFont : self.font
        let pieces = readings.map { reading in
            (dot: reading.tint, title: NSAttributedString(string: reading.text, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]))
        }

        var width: CGFloat = 0
        var height = font.capHeight
        for (index, piece) in pieces.enumerated() {
            if index > 0 { width += readingSpacing }
            if piece.dot != nil { width += dotDiameter + dotSpacing }
            let size = piece.title.size()
            width += size.width
            height = max(height, size.height, dotDiameter)
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: ceil(height)))
        // Drawn now rather than on demand: an image that paints itself lazily
        // arrives in the menu bar as the right amount of empty space with
        // nothing in it. Naming the appearance is what resolves the label colour
        // the title is written in.
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            var left: CGFloat = 0
            for (index, piece) in pieces.enumerated() {
                if index > 0 { left += readingSpacing }
                if let dot = piece.dot {
                    dot.setFill()
                    let box = NSRect(x: left, y: (height - dotDiameter) / 2, width: dotDiameter, height: dotDiameter)
                    NSBezierPath(ovalIn: box).fill()
                    left += dotDiameter + dotSpacing
                }
                let size = piece.title.size()
                piece.title.draw(at: NSPoint(x: left, y: (height - size.height) / 2))
                left += size.width
            }
        }
        image.unlockFocus()

        // Not a template image: the menu bar would paint the dots over in its
        // own colour, and the colour is the whole of what they say. The title
        // keeps the menu bar's colour by asking for it above instead.
        image.isTemplate = false
        image.accessibilityDescription = readings.map(\.text).joined(separator: Self.spokenSeparator)
        return image
    }

    private static let dotDiameter: CGFloat = 8

    /// The gap between a dot and its figures, matching the menu bar's own, and
    /// the wider one that separates two readings.
    private static let dotSpacing: CGFloat = 4
    private static let readingSpacing: CGFloat = 8

    /// What stands between two readings when the title is read aloud, the dots
    /// telling them apart being of no use there.
    private static var spokenSeparator: String {
        String(localized: ", ", comment: "Separates two limit readings spoken from the menu bar")
    }
}
