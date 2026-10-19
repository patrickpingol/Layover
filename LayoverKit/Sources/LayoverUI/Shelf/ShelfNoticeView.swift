import AppKit

/// A short message over a Shelf's content, such as "'x.txt' was removed from disk.". Messages show one
/// at a time, each for `duration`, in the order they arrive. It never takes the mouse.
@MainActor
final class ShelfNoticeView: NSView {
    private let duration: Duration
    private let label = NSTextField(wrappingLabelWithString: "")
    private var queue: [String] = []
    private var timer: Task<Void, Never>?

    /// The message on screen now, or nil when none is.
    private(set) var currentMessage: String?

    init(duration: Duration = .seconds(3)) {
        self.duration = duration
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.cornerRadius = 8
        isHidden = true

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Queues `messages` behind whatever is showing.
    func show(_ messages: [String]) {
        queue.append(contentsOf: messages)
        if currentMessage == nil { showNext() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func showNext() {
        guard !queue.isEmpty else {
            currentMessage = nil
            isHidden = true
            return
        }
        let message = queue.removeFirst()
        currentMessage = message
        label.stringValue = message
        isHidden = false
        timer = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.showNext()
        }
    }
}
