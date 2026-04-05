import AppKit

/// Pins traffic light buttons at the vertical center of a target height (e.g. 44pt tab bar)
/// using Auto Layout constraints so the system cannot reset their positions during layout.
@MainActor
final class TrafficLightAligner {
    private static let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton, .miniaturizeButton, .zoomButton,
    ]

    private let targetHeight: CGFloat
    private weak var window: NSWindow?
    private var constraints: [NSLayoutConstraint] = []

    init(window: NSWindow, targetHeight: CGFloat) {
        self.window = window
        self.targetHeight = targetHeight

        DispatchQueue.main.async { [weak self] in
            self?.installConstraints()
        }
    }

    func tearDown() {
        NSLayoutConstraint.deactivate(constraints)
        constraints.removeAll()
    }

    private func installConstraints() {
        guard let window, let contentView = window.contentView else { return }
        guard let closeButton = window.standardWindowButton(.closeButton),
              let container = closeButton.superview else { return }

        // The titlebar container clips repositioned buttons by default
        container.wantsLayer = true
        container.layer?.masksToBounds = false

        let buttonHeight = closeButton.frame.height
        let margin = (targetHeight - buttonHeight) / 2
        let closeX = closeButton.frame.origin.x

        for type in Self.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            let frame = button.frame
            button.translatesAutoresizingMaskIntoConstraints = false

            let leading = button.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: margin + (frame.origin.x - closeX)
            )

            let centerY = button.centerYAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: targetHeight / 2
            )

            let width = button.widthAnchor.constraint(equalToConstant: frame.width)
            let height = button.heightAnchor.constraint(equalToConstant: frame.height)

            constraints.append(contentsOf: [leading, centerY, width, height])
        }

        NSLayoutConstraint.activate(constraints)
    }
}
