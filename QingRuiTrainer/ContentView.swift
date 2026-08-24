import SwiftUI

/// iPhone 底部 Tab
enum PhoneTab: Hashable {
    case web, subjects
}

private enum IPadLayoutMetrics {
    static let dividerHitWidth: CGFloat = 16
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model = AppModel()
    @State private var phoneTab: PhoneTab = .web
    // 右侧科目区宽度（可拖动调整）；iPad 初始默认为屏幕宽 55%
    @State private var rightWidth: CGFloat = UIScreen.main.bounds.width * 0.55

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout   // iPad：左侧网页（可隐藏）+ 右侧科目（宽度可拖动）
            } else {
                iPhoneLayout // iPhone：底部 Tab
            }
        }
        .environment(model)
        .onChange(of: model.webPromptRequest?.id) { _, requestID in
            if requestID != nil { phoneTab = .web }
        }
    }

    // MARK: iPad 布局

    private var iPadLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if model.showWebPane {
                    NavigationStack {
                        WebPane()
                    }
                    .frame(width: max(200, geo.size.width - rightWidth - IPadLayoutMetrics.dividerHitWidth))  // 左侧占剩余宽

                    ResizableDivider(rightWidth: $rightWidth)
                }

                SubjectPane()
                    .frame(width: model.showWebPane
                           ? min(rightWidth, geo.size.width - 100)   // 右侧固定宽，防止被挤没
                           : geo.size.width)
            }
        }
        .background(CCTheme.bg.ignoresSafeArea())   // 填满左右之间的白底
    }

    // MARK: iPhone 布局

    private var iPhoneLayout: some View {
        Group {
            if model.showWebPane {
                // 打开网页：底部 Tab
                TabView(selection: $phoneTab) {
                    NavigationStack { WebPane() }
                        .tabItem { Label("网页", systemImage: "globe") }
                        .tag(PhoneTab.web)

                    SubjectPane()
                        .tabItem { Label("科目", systemImage: "books.vertical") }
                        .tag(PhoneTab.subjects)
                }
            } else {
                // 隐藏网页：仅科目，全屏
                SubjectPane()
            }
        }
    }
}

// MARK: - 可拖动的分隔线（细线显示、宽触区，手指/笔均可拖）

struct ResizableDivider: View {
    @Binding var rightWidth: CGFloat
    @GestureState private var dragStartWidth: CGFloat?

    var body: some View {
        ZStack {
            // 背景：与布局同色，避免漏出白边
            CCTheme.bg
            // 视觉：细分隔线
            Capsule()
                .fill(.quaternary)
                .frame(width: 2.5)
            // 视觉：中央小把手
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 4, height: 26)
        }
        .contentShape(Rectangle())           // 整个热区都可拖
        .frame(width: IPadLayoutMetrics.dividerHitWidth)
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($dragStartWidth) { _, state, _ in
                    if state == nil { state = rightWidth }
                }
                .onChanged { v in
                    // 向左拖 → 右侧变宽；向右拖 → 右侧变窄
                    let clamped = min(1100, max(320,
                        (dragStartWidth ?? rightWidth) - v.translation.width))
                    rightWidth = clamped
                }
        )
        .onTapGesture {}   // 确保触摸事件不被相邻视图拦截
        .hoverEffect(.highlight)
    }
}

// MARK: - 科目面板（点科目直接进做题页，训练设置走按钮弹窗）

private enum SpecialSubjectDestination: Hashable {
    case englishReading(Subject)
    case englishWords
    case englishTranslation(Subject)
}

struct SubjectPane: View {
    @Environment(AppModel.self) private var model

    @State private var sessionBox: SessionBox?
    @State private var showSettings = false
    @State private var specialDestination: SpecialSubjectDestination?
    @State private var rightScribbleQuestion: Question?
    @State private var fullScreenScribbleQuestion: Question?
    @State private var scribbleWorkspace = ScribbleWorkspace()
    @State private var emptySubject: String?
    @State private var wrongOnlyMode = false

    var body: some View {
        ZStack {
            NavigationStack {
                SubjectListView { subject in
                    startTraining(subject)
                }
                .navigationDestination(item: $sessionBox) { box in
                    QuizRunnerView(session: box.session) {
                        makeQuestions(wrongOnly: wrongOnlyMode)   // 一组做完按当前设置继续新一组
                    } onAdvance: {
                        scribbleWorkspace.reset()
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if supportsQuestionManagement {
                                Button {
                                    toggleWrongOnly(for: box.session)
                                } label: {
                                    Label(
                                        wrongOnlyMode ? "显示全部题" : "只看错题",
                                        systemImage: wrongOnlyMode
                                            ? "exclamationmark.circle.fill"
                                            : "exclamationmark.circle"
                                    )
                                }
                                .tint(wrongOnlyMode ? CCTheme.bad : CCTheme.accent)

                                Button(role: .destructive) {
                                    deleteCurrentManagedQuestion(from: box.session)
                                } label: {
                                    Label("删除当前题", systemImage: "trash")
                                }
                                .disabled(box.session.current == nil)
                            }

                            Button {
                                showScribbleBoard(for: box.session.current)
                            } label: {
                                Label("手写板", systemImage: "square.and.pencil")
                            }
                            .disabled(box.session.current == nil)
                            Button {
                                showSettings = true
                            } label: {
                                Label("训练设置", systemImage: "slider.horizontal.3")
                            }
                        }
                    }
                }
                .navigationDestination(item: $specialDestination) { destination in
                    switch destination {
                    case .englishReading(let subject):
                        EnglishReadingView(directoryId: subject.id, title: subject.name)
                    case .englishWords:
                        EnglishWordView()
                    case .englishTranslation(let subject):
                        EnglishTranslationView(directoryId: subject.id, title: subject.name)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showScribbleBoard(for: listScribbleQuestion)
                        } label: {
                            Label("手写板", systemImage: "square.and.pencil")
                        }
                        .accessibilityLabel("打开手写板")

                        Button {
                            showSettings = true
                        } label: {
                            Label("训练设置", systemImage: "slider.horizontal.3")
                        }
                    }
                }
                .alert("该科目暂无题目", isPresented: Binding(
                    get: { emptySubject != nil },
                    set: { if !$0 { emptySubject = nil } }
                )) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(emptySubject ?? "")
                }
            }

            if let question = rightScribbleQuestion {
                ScribbleBoardSheet(
                    question: question,
                    workspace: scribbleWorkspace,
                    onClose: { rightScribbleQuestion = nil }
                )
                .background(CCTheme.bg)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSettings) {
            TrainingSettingsSheet()
        }
        .fullScreenCover(item: $fullScreenScribbleQuestion) { question in
            ScribbleBoardSheet(question: question, workspace: scribbleWorkspace)
        }
    }

    private func showScribbleBoard(for question: Question?) {
        guard let question else { return }
        switch model.scribblePresentationMode {
        case .right:
            rightScribbleQuestion = question
        case .fullScreen:
            fullScreenScribbleQuestion = question
        }
    }

    private var listScribbleQuestion: Question {
        Question(
            id: 0,
            directoryId: 0,
            questionType: "scribble",
            title: "",
            options: [:],
            correctAnswer: "",
            explanation: nil,
            aiExplanation: nil,
            source: nil
        )
    }

    private func startTraining(_ subject: Subject) {
        scribbleWorkspace.reset()
        model.currentSubject = subject
        wrongOnlyMode = false

        switch subject.name.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "考研英语":
            specialDestination = .englishReading(subject)
            return
        case "英语单词":
            specialDestination = .englishWords
            return
        case "英语翻译":
            specialDestination = .englishTranslation(subject)
            return
        default:
            break
        }

        let qs = makeQuestions()
        guard !qs.isEmpty else { emptySubject = subject.name; return }
        sessionBox = SessionBox(session: configuredSession(questions: qs, title: subject.name))
    }

    /// 按当前训练设置（题量 / 乱序）从当前科目出题
    private func makeQuestions(wrongOnly: Bool = false) -> [Question] {
        guard let subject = model.currentSubject else { return [] }
        let (items, _) = Database.shared.questions(
            directoryId: subject.id,
            limit: model.trainingCount,
            wrongOnly: wrongOnly,
            randomOrder: model.shuffle
        )
        return items
    }

    private var supportsQuestionManagement: Bool {
        guard let name = model.currentSubject?.name.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return name == "考研数学" || name == "考研政治"
    }

    private func configuredSession(questions: [Question], title: String) -> QuizSession {
        let session = QuizSession(questions: questions, title: title)
        if supportsQuestionManagement {
            session.onWrongAnswer = { question in
                Database.shared.setQuestionWrong(id: question.id, isWrong: true)
            }
        }
        return session
    }

    private func toggleWrongOnly(for session: QuizSession) {
        let nextMode = !wrongOnlyMode
        let qs = makeQuestions(wrongOnly: nextMode)
        if nextMode && qs.isEmpty {
            emptySubject = "当前科目暂无错题"
            return
        }
        wrongOnlyMode = nextMode
        scribbleWorkspace.reset()
        session.replaceQuestions(qs)
    }

    private func deleteCurrentManagedQuestion(from session: QuizSession) {
        guard supportsQuestionManagement,
              let question = session.current,
              Database.shared.deleteQuestion(id: question.id) else { return }
        model.reloadSubjects()
        scribbleWorkspace.reset()
        session.removeCurrentQuestion()
    }
}

// MARK: - 训练设置弹窗（按钮触发，不在 tab 内展示）

struct TrainingSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Toggle("显示左侧网页", isOn: $model.showWebPane)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("手写板显示位置：")
                        Picker("手写板显示位置", selection: $model.scribblePresentationMode) {
                            ForEach(ScribblePresentationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("左侧网页：")
                        Picker("左侧网页", selection: $model.aiWebSite) {
                            ForEach(AIWebSite.allCases) { site in
                                Text(site.name).tag(site)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Stepper("题量：\(model.trainingCount) 题", value: $model.trainingCount, in: 1...100)
                    Toggle("乱序出题", isOn: $model.shuffle)
                } header: {
                    Text("训练设置")
                } footer: {
                    Text("设置会即时保存，点击科目即按当前设置开始训练。\"显示左侧网页\"在 iPad / iPhone 上均生效，隐藏后做题区占满全屏。")
                }
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("完成")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("题目训练设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
