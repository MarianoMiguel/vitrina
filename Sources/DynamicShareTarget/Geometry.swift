import CoreGraphics

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = center.x - point.x
        let dy = center.y - point.y
        return dx * dx + dy * dy
    }
}
