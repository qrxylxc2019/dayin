import SwiftUI

// MARK: - 全局共享状态（当前科目等）

struct WebPromptRequest: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
}

enum ScribblePresentationMode: String, CaseIterable, Identifiable {
    case right
    case fullScreen

    var id: Self { self }

    var title: String {
        switch self {
        case .right: "右侧"
        case .fullScreen: "全屏"
        }
    }
}

@Observable
final class AppModel {
    var subjects: [Subject] = []
    var currentSubject: Subject?
    var webPromptRequest: WebPromptRequest?

    // 训练设置（由「训练设置」弹窗维护，点科目时按此配置出题）
    var trainingCount = 10
    var shuffle = true

    // 是否显示左侧网页（iPad 默认开 / iPhone 默认关，持久化到 UserDefaults）
    var showWebPane: Bool {
        didSet { UserDefaults.standard.set(showWebPane, forKey: "cc.showWebPane") }
    }

    var aiWebSite: AIWebSite {
        didSet {
            UserDefaults.standard.set(
                aiWebSite.rawValue,
                forKey: "cc.aiWebSite"
            )
        }
    }

    var scribblePresentationMode: ScribblePresentationMode {
        didSet {
            UserDefaults.standard.set(
                scribblePresentationMode.rawValue,
                forKey: "cc.scribblePresentationMode"
            )
        }
    }

    init() {
        subjects = Database.shared.subjects()
        aiWebSite = AIWebSite(
            rawValue: UserDefaults.standard.string(forKey: "cc.aiWebSite") ?? ""
        ) ?? .deepSeek
        scribblePresentationMode = ScribblePresentationMode(
            rawValue: UserDefaults.standard.string(forKey: "cc.scribblePresentationMode") ?? ""
        ) ?? .fullScreen
        if UserDefaults.standard.object(forKey: "cc.showWebPane") != nil {
            showWebPane = UserDefaults.standard.bool(forKey: "cc.showWebPane")
        } else {
            // 未设置过：iPad 默认显示，iPhone 默认隐藏
            showWebPane = UIScreen.main.traitCollection.horizontalSizeClass == .regular
        }
    }

    var flatSubjects: [Subject] {
        var out: [Subject] = []
        for s in subjects {
            var root = s
            root.children = []
            out.append(root)
            for c in s.children { out.append(c) }
        }
        return out
    }

    func subjectName(id: Int) -> String {
        flatSubjects.first(where: { $0.id == id })?.name ?? "未知科目"
    }

    func requestAIExplanation(for question: Question, material: String? = nil) {
        var parts: [String] = []
        let materialText = material?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !materialText.isEmpty {
            parts.append("【阅读材料】\n\(materialText)")
        }
        parts.append("【题目】\n\(question.title)")
        let options = question.optionKeys.map { key in
            "\(key). \(question.optionText(key))"
        }
        if !options.isEmpty {
            parts.append("【选项】\n\(options.joined(separator: "\n"))")
        }
        let questionText = parts.joined(separator: "\n\n")
        webPromptRequest = WebPromptRequest(
            prompt: "请详细讲解以下题目的解题思路、涉及的考点和易错点：\n\n\(questionText)"
        )
        showWebPane = true
    }

    func requestWebPrompt(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        webPromptRequest = WebPromptRequest(prompt: text)
        showWebPane = true
    }

    func reloadSubjects() {
        subjects = Database.shared.subjects()
    }

    func requestAIWordStudy(for word: EnglishWord) {
        let prompt = """
        请作为我的英语词汇教练，带我循序渐进掌握单词“\(word.word)”。

        参考信息：
        - 音标：\(word.phonetic)
        - 基础释义：\(word.meaning)

        请严格按以下阶段和我互动：
        1. 核心理解：用简明中文讲清核心含义、发音要点，并给一个容易记住的联想。
        2. 实际用法：讲解常见搭配、词形变化和容易混淆的近义词。
        3. 语境输入：给出由易到难的例句，让我先猜句中含义再讲解。
        4. 主动回忆：依次进行中译英、选词填空和造句练习；答错时先给提示，不要立即公布答案。
        5. 掌握检查：最后做一次简短混合测试，并根据我的错误总结复习重点。

        每次只进行一个阶段，内容保持精炼；每个阶段结束时只问一个问题，等待我回答或确认后再进入下一阶段。现在从第 1 阶段开始。
        """
        webPromptRequest = WebPromptRequest(prompt: prompt)
        showWebPane = true
    }

    func requestAITranslation(for item: EnglishTranslationItem, userAnswer: String) {
        let submittedAnswer = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        webPromptRequest = WebPromptRequest(
            prompt: """
            你是一位资深英语翻译老师。请对以下英文句子进行详细翻译解析，包括：
            1. 句子结构分析
            2. 重点词汇和短语讲解
            3. 完整中文翻译
            4. 对比用户翻译与标准答案，给出评价和改进建议

            【英文原文】
            \(item.content)

            【标准答案】
            \(item.answer)

            【用户翻译】
            \(submittedAnswer.isEmpty ? "（用户未提供）" : submittedAnswer)
            """
        )
        showWebPane = true
    }
}

// MARK: - 科目列表（ScrollView + LazyVStack，数据多时可流畅滑动）

struct SubjectListView: View {
    @Environment(AppModel.self) private var model
    var onSelected: (Subject) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                ForEach(model.subjects) { subject in
                    subjectCard(subject)
                    if !subject.children.isEmpty {
                        // 子科目横向流式排布
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                                  spacing: 8) {
                            ForEach(subject.children) { child in
                                childChip(child)
                            }
                        }
                        .padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(CCTheme.bg.ignoresSafeArea())
    }

    private func subjectCard(_ subject: Subject) -> some View {
        Button {
            onSelected(subject)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(CCTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(CCTheme.textMain)
                    Text(subject.children.isEmpty
                         ? "题目数：\(subject.totalCount)"
                         : "题目数：\(subject.totalCount)（含子科目）")
                        .font(.caption)
                        .foregroundStyle(CCTheme.textSub)
                }
                Spacer()
                Text("\(subject.totalCount)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(CCTheme.accent)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(CCTheme.textSub.opacity(0.6))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CCTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(CCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func childChip(_ child: Subject) -> some View {
        Button {
            onSelected(child)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(CCTheme.accent)
                Text(child.name)
                    .font(.footnote)
                    .foregroundStyle(CCTheme.textMain)
                Text("\(child.questionCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CCTheme.textSub)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CCTheme.accentBG, in: Capsule())
            .overlay(Capsule().strokeBorder(CCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
