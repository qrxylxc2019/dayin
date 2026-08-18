import SwiftUI
import UIKit
import PencilKit

// MARK: - 考研英语阅读

struct EnglishReadingView: View {
    @Environment(AppModel.self) private var model

    let directoryId: Int
    let title: String

    @State private var materials: [EnglishReadingMaterial] = []
    @State private var materialIndex = 0
    @State private var selectedAnswers: [Int: String] = [:]
    @State private var excludedOptions: Set<String> = []
    @State private var materialFontSize: Double = 20
    @State private var materialRatio: CGFloat = 0.6
    @State private var materialCanvas = PKCanvasView()
    @State private var materialDrawings: [Int: PKDrawing] = [:]
    @State private var materialContentHeight: CGFloat = 0

    var body: some View {
        Group {
            if let material = currentMaterial {
                GeometryReader { geometry in
                    let dividerHeight: CGFloat = 18
                    let availableHeight = max(geometry.size.height - dividerHeight, 0)
                    let materialHeight = availableHeight * materialRatio
                    let questionsHeight = availableHeight - materialHeight

                    VStack(spacing: 0) {
                        articleSection(material)
                            .frame(height: materialHeight)

                        ReadingPaneDivider(
                            materialRatio: $materialRatio,
                            availableHeight: availableHeight
                        )

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(material.questions) { question in
                                    questionCard(question, material: material)
                                }
                            }
                            .padding(14)
                        }
                        .id("questions-\(material.id)")
                        .frame(height: questionsHeight)
                        .background(CCTheme.bg)
                    }
                }
            } else {
                ContentUnavailableView(
                    "暂无考研英语阅读",
                    systemImage: "text.book.closed",
                    description: Text("数据库中没有可用的阅读材料")
                )
            }
        }
        .navigationTitle(
            materials.isEmpty ? title : "阅读 \(materialIndex + 1)/\(materials.count)"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    changeMaterial(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(materialIndex == 0)
                .accessibilityLabel("上一篇")

                Button {
                    changeMaterial(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(materialIndex >= materials.count - 1)
                .accessibilityLabel("下一篇")
            }
        }
        .onAppear {
            if materials.isEmpty {
                materials = Database.shared.englishReadingMaterials(directoryId: directoryId)
            }
            configureMaterialCanvas()
            if let material = currentMaterial {
                materialCanvas.drawing = materialDrawings[material.id] ?? PKDrawing()
            }
        }
    }

    private var currentMaterial: EnglishReadingMaterial? {
        materials.indices.contains(materialIndex) ? materials[materialIndex] : nil
    }

    private func articleSection(_ material: EnglishReadingMaterial) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(articleTitle(material), systemImage: "doc.text")
                    .font(.headline)
                    .foregroundStyle(CCTheme.textMain)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Button {
                    materialCanvas.undoManager?.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("撤销材料笔迹")

                Button {
                    materialCanvas.undoManager?.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重做材料笔迹")

                Button(role: .destructive) {
                    materialCanvas.drawing = PKDrawing()
                    materialDrawings[material.id] = PKDrawing()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空材料笔迹")

                Image(systemName: "textformat.size")
                    .font(.caption)
                    .foregroundStyle(CCTheme.textSub)
                Slider(value: $materialFontSize, in: 13...28, step: 1)
                    .frame(width: 120)
                Text("\(Int(materialFontSize))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CCTheme.textSub)
                    .frame(width: 22, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)

            Divider()

            GeometryReader { geometry in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        MarkdownMathText(
                            raw: relaxedMaterialText(material.content),
                            fontSize: CGFloat(materialFontSize),
                            lineSpacing: max(7, CGFloat(materialFontSize) * 0.5),
                            blockSpacing: 16
                        )
                        .foregroundStyle(CCTheme.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            GeometryReader { contentGeometry in
                                Color.clear.preference(
                                    key: MaterialContentHeightKey.self,
                                    value: contentGeometry.size.height
                                )
                            }
                        }

                        MaterialPencilCanvas(canvasView: materialCanvas)
                            .frame(height: max(materialContentHeight, geometry.size.height))
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .onPreferenceChange(MaterialContentHeightKey.self) { height in
                    materialContentHeight = max(height, geometry.size.height)
                }
            }
            .id("material-\(material.id)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.bg)
    }

    private func questionCard(
        _ question: EnglishReadingQuestion,
        material: EnglishReadingMaterial
    ) -> some View {
        let selected = selectedAnswers[question.id]
        let answered = selected != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(question.questionNumber)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(width: 28, height: 28)
                    .background(CCTheme.accentBG, in: Circle())
                    .foregroundStyle(CCTheme.accent)
                RichMathText(raw: question.title, fontSize: 18)
                    .foregroundStyle(CCTheme.textMain)
                Spacer(minLength: 0)
            }

            ForEach(question.optionKeys, id: \.self) { key in
                readingOptionRow(question, key: key, selected: selected)
            }

            HStack {
                Button {
                    model.requestAIExplanation(
                        for: question.asQuestion(directoryId: material.directoryId),
                        material: material.content
                    )
                } label: {
                    Label("AI解析", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .tint(CCTheme.accent)

                Spacer()

                if answered {
                    Label(
                        selected == normalizedAnswer(question.correctAnswer) ? "回答正确" : "正确答案 \(question.correctAnswer)",
                        systemImage: selected == normalizedAnswer(question.correctAnswer)
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        selected == normalizedAnswer(question.correctAnswer) ? CCTheme.good : CCTheme.bad
                    )
                }
            }

            if answered {
                Divider()
                MarkdownMathText(
                    raw: question.explanation?.isEmpty == false ? question.explanation! : "暂无解析",
                    fontSize: 15
                )
                .foregroundStyle(CCTheme.textSub)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readingOptionRow(
        _ question: EnglishReadingQuestion,
        key: String,
        selected: String?
    ) -> some View {
        let exclusionKey = "\(question.id)-\(key)"
        let excluded = excludedOptions.contains(exclusionKey)
        let answered = selected != nil
        let correct = answered && key == normalizedAnswer(question.correctAnswer)
        let wrong = answered && selected == key && !correct
        let chosen = selected == key

        let background: Color = correct ? CCTheme.good.opacity(0.12)
            : wrong ? CCTheme.bad.opacity(0.10)
            : chosen ? CCTheme.accent.opacity(0.10)
            : CCTheme.card
        let border: Color = correct ? CCTheme.good
            : wrong ? CCTheme.bad
            : chosen ? CCTheme.accent
            : CCTheme.border

        return HStack(spacing: 8) {
            Button {
                if excluded {
                    excludedOptions.remove(exclusionKey)
                } else {
                    excludedOptions.insert(exclusionKey)
                }
            } label: {
                Image(systemName: excluded ? "arrow.uturn.backward.circle" : "trash")
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(excluded ? CCTheme.accent : CCTheme.textSub)
            .accessibilityLabel(excluded ? "恢复选项 \(key)" : "排除选项 \(key)")

            Button {
                guard !excluded else { return }
                selectedAnswers[question.id] = key
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(key)
                        .font(.subheadline.weight(.bold))
                        .frame(width: 26, height: 26)
                        .background(border, in: Circle())
                        .foregroundStyle((chosen || correct || wrong) ? Color.white : CCTheme.textMain)
                    Text(question.optionText(key))
                        .font(.body)
                        .strikethrough(excluded, color: CCTheme.bad)
                        .foregroundStyle(excluded ? CCTheme.textSub.opacity(0.55) : CCTheme.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(border, lineWidth: chosen || correct || wrong ? 1.5 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(excluded)
        }
    }

    private func articleTitle(_ material: EnglishReadingMaterial) -> String {
        let value = material.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "阅读材料 \(materialIndex + 1)" : value
    }

    private func relaxedMaterialText(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: " \u{2009}")
    }

    private func normalizedAnswer(_ answer: String) -> String {
        String(answer.uppercased().first(where: { $0.isLetter }) ?? " ")
    }

    private func changeMaterial(by offset: Int) {
        let next = materialIndex + offset
        guard materials.indices.contains(next) else { return }
        if let material = currentMaterial {
            materialDrawings[material.id] = materialCanvas.drawing
        }
        materialContentHeight = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            materialIndex = next
        }
        materialCanvas.drawing = materialDrawings[materials[next].id] ?? PKDrawing()
    }

    private func configureMaterialCanvas() {
        materialCanvas.backgroundColor = .clear
        materialCanvas.isOpaque = false
        materialCanvas.drawingPolicy = .pencilOnly
        materialCanvas.isScrollEnabled = false
        materialCanvas.tool = PKInkingTool(.pen, color: .systemRed, width: 5)
        materialCanvas.drawingGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        if #available(iOS 18.0, *) {
            materialCanvas.isDrawingEnabled = true
        }
    }
}

private struct ReadingPaneDivider: View {
    @Binding var materialRatio: CGFloat
    let availableHeight: CGFloat

    @GestureState private var dragStartRatio: CGFloat?

    var body: some View {
        ZStack {
            CCTheme.bg
            Capsule()
                .fill(.quaternary)
                .frame(height: 2.5)
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 28, height: 4)
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($dragStartRatio) { _, state, _ in
                    if state == nil { state = materialRatio }
                }
                .onChanged { value in
                    guard availableHeight > 0 else { return }
                    let startHeight = (dragStartRatio ?? materialRatio) * availableHeight
                    materialRatio = min(0.8, max(0.3,
                        (startHeight + value.translation.height) / availableHeight
                    ))
                }
        )
        .hoverEffect(.highlight)
        .accessibilityLabel("调整材料与选项高度")
    }
}

private struct MaterialContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MaterialPencilCanvas: UIViewRepresentable {
    let canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        configure(canvasView)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        configure(uiView)
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

// MARK: - 英语单词

private enum WordStudyMode: String, CaseIterable, Identifiable {
    case grid = "全看模式"
    case flash = "快闪模式"

    var id: Self { self }
}

struct EnglishWordView: View {
    @Environment(AppModel.self) private var model

    private let wordsPerPage = 49

    @State private var words: [EnglishWord] = []
    @State private var studyMode: WordStudyMode = .grid
    @State private var showMeaning = true
    @State private var searchText = ""
    @State private var page = 1
    @State private var flashIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            wordToolbar
            Divider()

            if filteredWords.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if studyMode == .grid {
                gridMode
            } else {
                flashMode
            }
        }
        .navigationTitle("英语单词")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索单词、音标或释义")
        .onAppear {
            if words.isEmpty {
                words = Database.shared.englishWords()
            }
        }
        .onChange(of: searchText) { _, _ in
            page = 1
            flashIndex = 0
        }
        .onChange(of: studyMode) { _, _ in
            flashIndex = 0
        }
    }

    private var filteredWords: [EnglishWord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return words }
        return words.filter {
            $0.word.localizedCaseInsensitiveContains(query)
                || $0.phonetic.localizedCaseInsensitiveContains(query)
                || $0.meaning.localizedCaseInsensitiveContains(query)
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredWords.count) / Double(wordsPerPage))))
    }

    private var pageWords: [EnglishWord] {
        let validPage = min(max(page, 1), totalPages)
        let start = (validPage - 1) * wordsPerPage
        guard start < filteredWords.count else { return [] }
        return Array(filteredWords[start..<min(start + wordsPerPage, filteredWords.count)])
    }

    private var currentRange: String {
        guard !filteredWords.isEmpty else { return "0" }
        let start = (page - 1) * wordsPerPage + 1
        let end = min(page * wordsPerPage, filteredWords.count)
        return "\(start)-\(end)"
    }

    private var wordToolbar: some View {
        VStack(spacing: 8) {
            Picker("学习模式", selection: $studyMode) {
                ForEach(WordStudyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("共 \(filteredWords.count) 词 · \(currentRange)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CCTheme.textSub)
                Spacer()
                Toggle("显示释义", isOn: $showMeaning)
                    .toggleStyle(.switch)
                    .font(.subheadline)
                    .disabled(studyMode == .flash)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var gridMode: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                spacing: 10
            ) {
                ForEach(pageWords) { word in
                    wordCard(word)
                }
            }
            .padding(14)

            pageControls
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
        }
        .background(CCTheme.bg.ignoresSafeArea())
    }

    private func wordCard(_ word: EnglishWord) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    model.requestAIWordStudy(for: word)
                } label: {
                    Image(systemName: "sparkles")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(CCTheme.accent)
                .accessibilityLabel("AI 学习 \(word.word)")

                Spacer()

                Button(role: .destructive) {
                    deleteWord(word)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除单词 \(word.word)")
            }

            Text(word.word)
                .font(.title3.weight(.bold))
                .foregroundStyle(CCTheme.textMain)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(word.phonetic)
                .font(.caption)
                .foregroundStyle(CCTheme.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(showMeaning ? word.meaning : " ")
                .font(.footnote)
                .foregroundStyle(CCTheme.textMain)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(minHeight: 48, alignment: .top)
                .opacity(showMeaning ? 1 : 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .top)
        .background(CCTheme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CCTheme.border, lineWidth: 1)
        }
    }

    private var flashMode: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 16)

            if let word = activeFlashWord {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CCTheme.accentBG.opacity(0.75))
                        .frame(maxWidth: 430, minHeight: 270)
                        .offset(y: 12)

                    VStack(spacing: 16) {
                        HStack {
                            Spacer()
                            Button {
                                model.requestAIWordStudy(for: word)
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.bordered)
                            .tint(CCTheme.accent)
                            .accessibilityLabel("AI 学习 \(word.word)")
                        }

                        Spacer(minLength: 0)
                        Text(word.word)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(CCTheme.textMain)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(word.phonetic)
                            .font(.title3)
                            .foregroundStyle(CCTheme.textSub)
                        Text(word.meaning)
                            .font(.headline)
                            .foregroundStyle(CCTheme.textMain)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(maxWidth: 430, minHeight: 270)
                    .background(CCTheme.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(CCTheme.border, lineWidth: 1)
                    }
                    .id(word.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                .padding(.horizontal, 18)
            }

            VStack(spacing: 6) {
                ProgressView(
                    value: Double(min(flashIndex + 1, max(pageWords.count, 1))),
                    total: Double(max(pageWords.count, 1))
                )
                .tint(CCTheme.accent)
                Text("\(min(flashIndex + 1, pageWords.count)) / \(pageWords.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CCTheme.textSub)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 14) {
                Button {
                    previousFlash()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("上一个单词")

                Button {
                    advanceFlash()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("下一个单词")

                Button {
                    withAnimation { flashIndex = 0 }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("重置快闪")
            }

            pageControls
                .padding(.horizontal, 18)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CCTheme.bg.ignoresSafeArea())
    }

    private var activeFlashWord: EnglishWord? {
        guard !pageWords.isEmpty else { return nil }
        return pageWords[min(flashIndex, pageWords.count - 1)]
    }

    private var pageControls: some View {
        HStack(spacing: 12) {
            Button {
                changePage(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(page <= 1)
            .accessibilityLabel("上一页")

            Text("第 \(page) / \(totalPages) 页")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(CCTheme.textSub)
                .frame(minWidth: 100)

            Button {
                changePage(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(page >= totalPages)
            .accessibilityLabel("下一页")
        }
        .frame(maxWidth: .infinity)
    }

    private func changePage(by offset: Int) {
        let next = page + offset
        guard (1...totalPages).contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            page = next
            flashIndex = 0
        }
    }

    private func advanceFlash() {
        guard !pageWords.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            flashIndex = (flashIndex + 1) % pageWords.count
        }
    }

    private func previousFlash() {
        guard !pageWords.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            flashIndex = (flashIndex - 1 + pageWords.count) % pageWords.count
        }
    }

    private func deleteWord(_ word: EnglishWord) {
        guard Database.shared.deleteEnglishWord(id: word.id) else { return }
        words.removeAll { $0.id == word.id }
        page = min(page, totalPages)
        flashIndex = min(flashIndex, max(pageWords.count - 1, 0))
    }
}

// MARK: - 英语翻译

struct EnglishTranslationView: View {
    @Environment(AppModel.self) private var model

    let directoryId: Int
    let title: String

    @State private var items: [EnglishTranslationItem] = []
    @State private var currentIndex = 0
    @State private var userAnswer = ""
    @State private var showResult = false
    @State private var copied = false
    @State private var showAddSheet = false
    @State private var showDeleteConfirmation = false
    @State private var newContent = ""
    @State private var newAnswer = ""

    var body: some View {
        VStack(spacing: 0) {
            if let item = currentItem {
                translationToolbar
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sourceCard(item)
                        answerCard(item)
                    }
                    .padding(14)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(CCTheme.bg.ignoresSafeArea())
            } else {
                ContentUnavailableView {
                    Label("暂无翻译题目", systemImage: "character.book.closed")
                } actions: {
                    Button {
                        prepareAddSheet()
                    } label: {
                        Label("新增题目", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CCTheme.accent)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(CCTheme.accent)
        .onAppear {
            if items.isEmpty { loadItems() }
        }
        .sheet(isPresented: $showAddSheet) {
            addTranslationSheet
        }
        .alert("删除这道翻译题？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive, action: deleteCurrentItem)
            Button("取消", role: .cancel) {}
        }
    }

    private var currentItem: EnglishTranslationItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    private var translationToolbar: some View {
        HStack(spacing: 10) {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(items.count < 2)
            .accessibilityLabel("上一题")

            VStack(alignment: .leading, spacing: 4) {
                Text("题目 \(currentIndex + 1) / \(items.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                ProgressView(value: Double(currentIndex + 1), total: Double(max(items.count, 1)))
                    .tint(CCTheme.accent)
            }

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(items.count < 2)
            .accessibilityLabel("下一题")

            Spacer(minLength: 4)

            Button {
                prepareAddSheet()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("新增翻译题")

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .tint(CCTheme.bad)
            .accessibilityLabel("删除当前翻译题")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func sourceCard(_ item: EnglishTranslationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("翻译材料", systemImage: "text.quote")
                    .font(.headline)
                    .foregroundStyle(CCTheme.textMain)
                Spacer()
                Button {
                    UIPasteboard.general.string = item.content
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(copied ? "已复制" : "复制英文原文")
            }

            Text(item.content)
                .font(.title3)
                .foregroundStyle(CCTheme.textMain)
                .lineSpacing(7)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CCTheme.border, lineWidth: 1)
        }
    }

    private func answerCard(_ item: EnglishTranslationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("你的翻译", systemImage: "square.and.pencil")
                .font(.headline)
                .foregroundStyle(CCTheme.textMain)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $userAnswer)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 150)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(CCTheme.border, lineWidth: 1)
                    }
                    .disabled(showResult)

                if userAnswer.isEmpty {
                    Text("输入中文译文")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                if showResult {
                    Button {
                        resetAnswer()
                    } label: {
                        Label("重新作答", systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        showResult = true
                    } label: {
                        Label("提交翻译", systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CCTheme.accent)
                    .disabled(userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showResult {
                    Button {
                        model.requestAITranslation(for: item, userAnswer: userAnswer)
                    } label: {
                        Label("AI解析", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CCTheme.accent)
                }
            }

            if showResult {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("标准答案", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CCTheme.good)
                    Text(item.answer)
                        .font(.body)
                        .foregroundStyle(CCTheme.textMain)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }

                Label(
                    normalized(userAnswer) == normalized(item.answer)
                        ? "与标准答案一致"
                        : "请对照标准答案检查表达",
                    systemImage: normalized(userAnswer) == normalized(item.answer)
                        ? "checkmark.seal.fill"
                        : "text.magnifyingglass"
                )
                .font(.subheadline)
                .foregroundStyle(
                    normalized(userAnswer) == normalized(item.answer) ? CCTheme.good : CCTheme.textSub
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CCTheme.border, lineWidth: 1)
        }
    }

    private var addTranslationSheet: some View {
        NavigationStack {
            Form {
                Section("英文材料") {
                    TextEditor(text: $newContent)
                        .frame(minHeight: 130)
                }
                Section("中文答案") {
                    TextEditor(text: $newAnswer)
                        .frame(minHeight: 130)
                }
            }
            .navigationTitle("新增翻译题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveNewItem)
                        .disabled(
                            newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || newAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .presentationDetents([.large])
        .tint(CCTheme.accent)
    }

    private func loadItems() {
        var loaded = Database.shared.englishTranslations(directoryId: directoryId)
        if model.shuffle { loaded.shuffle() }
        items = Array(loaded.prefix(max(model.trainingCount, 1)))
        currentIndex = 0
        resetAnswer()
    }

    private func move(by offset: Int) {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex + offset + items.count) % items.count
        resetAnswer()
    }

    private func resetAnswer() {
        userAnswer = ""
        showResult = false
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !"，。？！,.?!“”\"'".contains($0) }
    }

    private func prepareAddSheet() {
        newContent = ""
        newAnswer = ""
        showAddSheet = true
    }

    private func saveNewItem() {
        let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = newAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = Database.shared.addEnglishTranslation(
            directoryId: directoryId,
            content: content,
            answer: answer
        ) else { return }

        items.append(item)
        currentIndex = items.count - 1
        resetAnswer()
        showAddSheet = false
    }

    private func deleteCurrentItem() {
        guard let item = currentItem,
              Database.shared.deleteEnglishTranslation(id: item.id) else { return }
        items.remove(at: currentIndex)
        if currentIndex >= items.count {
            currentIndex = max(items.count - 1, 0)
        }
        resetAnswer()
    }
}
