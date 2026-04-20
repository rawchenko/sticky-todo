import SwiftUI
import AppKit

struct AutoGrowingInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var textColor: NSColor
    var placeholderColor: NSColor
    var maxLines: Int
    var onSubmit: () -> Void
    var onCancel: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil
    var focusOnAppear: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let textView = GrowingTextView()
        textView.delegate = context.coordinator
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.textColor = textColor
        textView.placeholderString = placeholder
        textView.placeholderColor = placeholderColor
        textView.maxLines = maxLines
        textView.focusOnAppear = focusOnAppear
        textView.string = text
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.onFocusChange?(focused)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = context.coordinator.textView else { return nil }
        let width = proposal.width ?? nsView.bounds.width
        guard width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: textView.fittingHeight(forWidth: width))
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        if textView.placeholderString != placeholder { textView.placeholderString = placeholder }
        if textView.placeholderColor != placeholderColor { textView.placeholderColor = placeholderColor }
        if textView.maxLines != maxLines {
            textView.maxLines = maxLines
            textView.invalidateIntrinsicContentSize()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoGrowingInputField
        weak var textView: GrowingTextView?

        init(parent: AutoGrowingInputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? GrowingTextView else { return }
            if parent.text != view.string { parent.text = view.string }
            view.scrollRangeToVisible(view.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Return false on Shift+Return so the text system inserts a newline itself.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let onCancel = parent.onCancel {
                onCancel()
                return true
            }
            return false
        }
    }
}

final class GrowingTextView: NSTextView {
    fileprivate var maxLines: Int = 5
    fileprivate var focusOnAppear = false
    fileprivate var onFocusChange: ((Bool) -> Void)?
    private var didPerformInitialFocus = false

    fileprivate var placeholderString: String = "" {
        didSet { if oldValue != placeholderString { needsDisplay = true } }
    }

    fileprivate var placeholderColor: NSColor = .placeholderTextColor {
        didSet { if oldValue != placeholderColor { needsDisplay = true } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAppear, !didPerformInitialFocus, let window else { return }
        didPerformInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let innerWidth = max(width - textContainerInset.width * 2, 0)
        let oneLine = resolvedLineHeight()
        let usedHeight: CGFloat
        if string.isEmpty {
            usedHeight = oneLine
        } else if let font {
            let rect = (string as NSString).boundingRect(
                with: NSSize(width: innerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            usedHeight = ceil(rect.height)
        } else {
            usedHeight = oneLine
        }
        let cappedLines = min(max(usedHeight, oneLine), oneLine * CGFloat(maxLines))
        return cappedLines + textContainerInset.height * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: placeholderColor
        ]
        let origin = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        (placeholderString as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func resolvedLineHeight() -> CGFloat {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return layoutManager?.defaultLineHeight(for: font) ?? font.pointSize * 1.2
    }
}
