import AppKit
import CoreImage
import CoreMedia

@MainActor
final class CaptureRendererView: NSView {
    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    private let messageLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 36, weight: .semibold)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 3
        messageLabel.isHidden = true
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 96),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -96)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 1
    }

    func clear() {
        layer?.contents = nil
        layer?.backgroundColor = NSColor.black.cgColor
        messageLabel.isHidden = true
    }

    func showMessage(_ message: String) {
        layer?.contents = nil
        layer?.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.065, blue: 0.075, alpha: 1).cgColor
        messageLabel.stringValue = message
        messageLabel.isHidden = false
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
        messageLabel.isHidden = true
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
            self.layer?.contents = cgImage
            self.messageLabel.isHidden = true
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
