import SwiftUI
import PencilKit
import UIKit

// MARK: - 笔型

enum PenKind: Hashable {
    case pen, marker, pencil, eraser

    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .pencil: "pencil.and.outline"
        case .eraser: "eraser.fill"
        }
    }

    var inkType: PKInkingTool.InkType? {
        switch self {
        case .pen: .pen
        case .marker: .marker
        case .pencil: .pencil
        case .eraser: nil
        }
    }
}

// MARK: - 当前题的手写工作区

@Observable
final class ScribbleWorkspace {
    var pages: [ScribbleCanvasView] = [ScribbleCanvasView()]
    var pageIndex = 0

    func reset() {
        pages = [ScribbleCanvasView()]
        pageIndex = 0
    }
}

// MARK: - 手写板（全屏、多页，每页显示题目，笔迹覆盖题目）

struct ScribbleBoardSheet: View {
    let question: Question
    let workspace: ScribbleWorkspace
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var toolColor: Color = .red
    @State private var penKind: PenKind = .pen
    @State private var toolWidth: CGFloat = 5
    @State private var transitionDirection: PageSwipeDirection = .next

    private let inkColors: [Color] = [.black, .red, .blue, .green, .orange, .purple]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    PageCanvasView(canvasView: activeCanvas,
                                   question: question) { direction in
                        changePage(direction)
                    }
                    .id(ObjectIdentifier(activeCanvas))
                    .transition(pageTransition)
                }
                .clipped()
                .padding(8)

                toolBar
                    .padding(.vertical, 8)
                    .padding(.bottom, 4)
                    .background(.bar)
            }
            .onAppear {
                workspace.pages.forEach { applyTool(to: $0) }
            }
            .navigationTitle("手写板 · 第 \(workspace.pageIndex + 1)/\(workspace.pages.count) 页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        activeCanvas.undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    Button {
                        activeCanvas.undoManager?.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    Button(role: .destructive) {
                        activeCanvas.drawing = PKDrawing()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        addPage()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    Button {
                        close()
                    } label: {
                        Text("完成").bold()
                    }
                }
            }
        }
    }

    private var activeCanvas: ScribbleCanvasView { workspace.pages[workspace.pageIndex] }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func addPage() {
        let newPage = ScribbleCanvasView()
        applyTool(to: newPage)
        transitionDirection = .next
        withAnimation(pageAnimation) {
            workspace.pages.append(newPage)
            workspace.pageIndex = workspace.pages.count - 1
        }
    }

    private func applyTool(to canvas: PKCanvasView) {
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        if let ink = penKind.inkType {
            canvas.tool = PKInkingTool(ink, color: UIColor(toolColor), width: toolWidth)
        } else {
            canvas.tool = PKEraserTool(.bitmap)
        }
    }

    private func changePage(_ direction: PageSwipeDirection) {
        transitionDirection = direction
        switch direction {
        case .next:
            guard workspace.pageIndex < workspace.pages.count - 1 else { return }
            withAnimation(pageAnimation) {
                workspace.pageIndex += 1
            }
        case .previous:
            guard workspace.pageIndex > 0 else { return }
            withAnimation(pageAnimation) {
                workspace.pageIndex -= 1
            }
        }
    }

    private var pageAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.88)
    }

    private var pageTransition: AnyTransition {
        switch transitionDirection {
        case .next:
            .asymmetric(
                insertion: .move(edge: .trailing)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.98)),
                removal: .move(edge: .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.98))
            )
        case .previous:
            .asymmetric(
                insertion: .move(edge: .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.98)),
                removal: .move(edge: .trailing)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.98))
            )
        }
    }

    // MARK: 底部工具条（笔型 / 颜色 / 翻页）

    private var toolBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                penPicker
                    .frame(width: 260)
                colorPicker(circleSize: 22, spacing: 8)
                if penKind != .eraser {
                    widthControl(sliderWidth: 110)
                }
                pageControls
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    penPicker
                    pageControls
                }

                HStack(spacing: 8) {
                    colorPicker(circleSize: 19, spacing: 5)
                    if penKind != .eraser {
                        Spacer(minLength: 4)
                        widthControl(sliderWidth: 76)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private var penPicker: some View {
        Picker("笔型", selection: $penKind) {
            ForEach([PenKind.pen, .marker, .pencil, .eraser], id: \.self) { kind in
                Image(systemName: kind.icon).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: penKind) { _, _ in
            workspace.pages.forEach { applyTool(to: $0) }
        }
    }

    private func colorPicker(circleSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(inkColors, id: \.description) { color in
                Circle()
                    .fill(color)
                    .frame(width: circleSize, height: circleSize)
                    .overlay {
                        if color == toolColor {
                            Circle().strokeBorder(.primary, lineWidth: 2)
                        }
                    }
                    .onTapGesture {
                        toolColor = color
                        workspace.pages.forEach { applyTool(to: $0) }
                    }
            }
        }
    }

    private func widthControl(sliderWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lineweight")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $toolWidth, in: 1...20, step: 0.5)
                .frame(width: sliderWidth)
            Text(String(format: "%.1f", Double(toolWidth)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("笔迹粗细")
        .onChange(of: toolWidth) { _, _ in
            workspace.pages.forEach { applyTool(to: $0) }
        }
    }

    private var pageControls: some View {
        HStack(spacing: 8) {
            Button {
                changePage(.previous)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(workspace.pageIndex == 0)
            .accessibilityLabel("上一页")

            Text("\(workspace.pageIndex + 1)/\(workspace.pages.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)

            Button {
                changePage(.next)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(workspace.pageIndex == workspace.pages.count - 1)
            .accessibilityLabel("下一页")
        }
    }
}

// MARK: - 单页画布（Apple Pencil 书写，手指翻页）

enum PageSwipeDirection {
    case previous, next
}

struct PageCanvasView: View {
    let canvasView: PKCanvasView
    let question: Question?
    let onFingerSwipe: (PageSwipeDirection) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: .systemBackground)

            if let question {
                QuestionPageContent(question: question)
                    .padding(20)
                    .allowsHitTesting(false)
            }

            PencilCanvasView(canvasView: canvasView, onFingerSwipe: onFingerSwipe)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
    }
}

private struct QuestionPageContent: View {
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(question.typeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CCTheme.accent)
                Text("题目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            RichMathText(raw: question.title, fontSize: 20)
                .foregroundStyle(.primary)

            ForEach(question.optionKeys, id: \.self) { key in
                HStack(alignment: .top, spacing: 10) {
                    Text(key)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(CCTheme.accentBG))
                        .foregroundStyle(CCTheme.textMain)
                    RichMathText(raw: question.optionText(key), fontSize: 17)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PencilCanvasView: UIViewRepresentable {
    let canvasView: PKCanvasView
    let onFingerSwipe: (PageSwipeDirection) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        configure(canvasView)
        (canvasView as? ScribbleCanvasView)?.onFingerSwipe = onFingerSwipe
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        configure(uiView)
        (uiView as? ScribbleCanvasView)?.onFingerSwipe = onFingerSwipe
    }

    private func configure(_ canvas: PKCanvasView) {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.isUserInteractionEnabled = true
        canvas.drawingGestureRecognizer.isEnabled = true
        canvas.drawingGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        if #available(iOS 18.0, *) {
            canvas.isDrawingEnabled = true
        }
    }
}

final class ScribbleCanvasView: PKCanvasView, UIGestureRecognizerDelegate {
    var onFingerSwipe: ((PageSwipeDirection) -> Void)?

    private lazy var pageSwipeRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePageSwipe(_:)))
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(pageSwipeRecognizer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(pageSwipeRecognizer)
    }

    @objc private func handlePageSwipe(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        let horizontal = abs(translation.x) >= abs(translation.y)
        let distance = horizontal ? translation.x : translation.y
        let speed = horizontal ? velocity.x : velocity.y
        guard abs(distance) > 60 || abs(speed) > 500 else { return }

        onFingerSwipe?(distance < 0 ? .next : .previous)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
