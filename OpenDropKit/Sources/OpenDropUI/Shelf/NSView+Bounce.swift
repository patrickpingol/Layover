import AppKit

extension NSView {
    /// A 0.25 s scale bounce (1.0, 1.15, 1.0) about the view's center, to point out an Item that
    /// was dropped again.
    func bounce() {
        wantsLayer = true
        guard let layer else { return }
        // Scale about the view's center whatever the layer's anchor point is.
        let anchor = CGPoint(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
        let offset = CGPoint(x: layer.bounds.midX - anchor.x, y: layer.bounds.midY - anchor.y)
        let scale: CGFloat = 1.15
        let enlarged = CATransform3DTranslate(
            CATransform3DScale(CATransform3DMakeTranslation(offset.x, offset.y, 0), scale, scale, 1),
            -offset.x, -offset.y, 0
        )

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [CATransform3DIdentity, enlarged, CATransform3DIdentity].map(NSValue.init)
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.duration = 0.25
        layer.add(animation, forKey: "bounce")
    }
}
