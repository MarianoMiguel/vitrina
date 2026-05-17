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

    func clear() {
        layer?.contents = nil
        layer?.backgroundColor = NSColor.black.cgColor
        messageLabel.isHidden = true
    }

    func showMessage(_ message: String) {
        layer?.contents = nil
        layer?.backgroundColor = NSColor.black.cgColor
        messageLabel.stringValue = message
        messageLabel.isHidden = false
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
}
