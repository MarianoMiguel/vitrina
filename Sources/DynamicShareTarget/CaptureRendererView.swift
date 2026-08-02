import AppKit
import CoreImage
import CoreMedia

@MainActor
final class CaptureRendererView: NSView {
    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB()
    ])

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 1
    }

    func clear() {
        showBackground()
    }

    /// Idle look for the portal: the custom background image if one is set,
    /// otherwise the user's current wallpaper. No text — the portal is what
    /// meeting participants see.
    func showBackground() {
        AppLogger.shared.log("renderer showBackground custom=\(PortalPreferences.customBackgroundURL?.lastPathComponent ?? "none")")
        if let image = backgroundImage() {
            layer?.contentsGravity = .resizeAspectFill
            layer?.contents = image
        } else {
            layer?.contents = nil
        }
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func backgroundImage() -> NSImage? {
        if let custom = PortalPreferences.customBackgroundURL,
           let image = NSImage(contentsOf: custom) {
            return image
        }

        // The renderer's own screen is the virtual display, which keeps the
        // default macOS wallpaper; prefer a real display's wallpaper.
        let ownScreen = window?.screen
        let screen = NSScreen.screens.first { $0 != ownScreen } ?? NSScreen.main
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    func showTestPattern() {
        let targetSize = validDrawingSize()
        let image = NSImage(size: targetSize)

        image.lockFocus()

        NSColor.black.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let stripeHeight = targetSize.height / 6
        let colors: [NSColor] = [
            .systemRed,
            .systemOrange,
            .systemYellow,
            .systemGreen,
            .systemBlue,
            .systemPurple
        ]

        for (index, color) in colors.enumerated() {
            color.withAlphaComponent(0.78).setFill()
            NSRect(
                x: 0,
                y: CGFloat(index) * stripeHeight,
                width: targetSize.width,
                height: stripeHeight
            ).fill()
        }

        NSColor.black.withAlphaComponent(0.72).setFill()
        let panelRect = NSRect(
            x: targetSize.width * 0.22,
            y: targetSize.height * 0.34,
            width: targetSize.width * 0.56,
            height: targetSize.height * 0.32
        )
        NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(42, targetSize.width * 0.052), weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(18, targetSize.width * 0.018), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]

        drawCentered("PeekPortal", in: panelRect.offsetBy(dx: 0, dy: panelRect.height * 0.12), attributes: titleAttributes)
        drawCentered("Test Share Target", in: panelRect.offsetBy(dx: 0, dy: -panelRect.height * 0.18), attributes: detailAttributes)

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: NSRect(origin: .zero, size: targetSize).insetBy(dx: 8, dy: 8))
        border.lineWidth = 8
        border.stroke()

        image.unlockFocus()

        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
    }

    nonisolated func display(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let image = CIImage(cvPixelBuffer: imageBuffer)
        let extent = image.extent

        Task { @MainActor in
            guard let cgImage = self.ciContext.createCGImage(image, from: extent) else {
                return
            }
            self.layer?.contentsGravity = .resizeAspect
            self.layer?.contents = cgImage
        }
    }

    private func drawCentered(
        _ string: String,
        in rect: NSRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let size = attributedString.size()
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        attributedString.draw(at: origin)
    }

    private func validDrawingSize() -> NSSize {
        bounds.size.width > 0 && bounds.size.height > 0
            ? bounds.size
            : NSSize(width: 960, height: 540)
    }
}
