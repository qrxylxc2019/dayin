import SwiftUI
import UIKit

// MARK: - 训练会话模型

@Observable
final class QuizSession {
    let title: String
    var questions: [Question]
    var index = 0
    var answers: [String] = []     // 用户每题答案（字母拼接）
    var results: [Bool] = []
    var submitted = false
    var selection: Set<String> = []

    // 跨组累计统计
    var groupIndex = 1
    var totalCorrect = 0
    var totalAnswered = 0

    /// 已排除（删除）的选项：置灰禁用 + 删除线
    var eliminated: Set<String> = []

    var onWrongAnswer: ((Question) -> Void)?

    var finished: Bool { index >= questions.count }

    init(questions: [Question], title: String) {
        self.questions = questions
        self.title = title
    }

    var current: Question? {
        index < questions.count ? questions[index] : nil
    }

    var correctCount: Int { results.filter { $0 }.count }

    /// 即选即判；多选不立即判定，留待「确认」按钮提交
    func pick(_ key: String, single: Bool) {
        guard let q = current, !eliminated.contains(key) else { return }
        if single {
            selection = [key]
            judge(q)
        } else {
            if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
            // 多选：仅切换选中态，不做判断
        }
    }

    /// 多选「确认」按钮调用：提交当前选中项判定
    func confirmMultiple() {
        guard let q = current, !selection.isEmpty else { return }
        judge(q)
    }

    /// 以当前选中项判定本题（覆盖式，可反复触发）
    private func judge(_ q: Question) {
        let user = selection.sorted().joined()
        let correct = !user.isEmpty && Set(user.map(String.init)) == q.correctKeys
        if !user.isEmpty && !correct {
            questions[index].isWrong = true
            onWrongAnswer?(q)
        }
        if answers.count > index {
            answers[index] = user
            results[index] = correct
        } else {
            answers.append(user)
            results.append(correct)
        }
        submitted = !user.isEmpty   // 有选择即展示判定与解析
        totalCorrect = results.filter { $0 }.count
        totalAnswered = results.count
    }

    /// 排除/恢复选项（再次点击恢复）
    func toggleEliminate(_ key: String) {
        if eliminated.contains(key) {
            eliminated.remove(key)
        } else {
            eliminated.insert(key)
            if selection.contains(key) { selection.remove(key) }   // 被排除的选项不可作为答案
            if let q = current { judge(q) }                          // 重选后重判
        }
    }

    func next() {
        // 未作答直接跳过的题目，补一条空记录，保持 answers/results 与题目对齐
        if !submitted, answers.count <= index {
            answers.append("")
            results.append(false)
            totalAnswered += 1
        }
        index += 1
        submitted = false
        selection = []
        eliminated = []
    }

    func replaceQuestions(_ newQuestions: [Question]) {
        questions = newQuestions
        index = 0
        answers = []
        results = []
        submitted = false
        selection = []
        eliminated = []
    }

    func removeCurrentQuestion() {
        guard questions.indices.contains(index) else { return }
        questions.remove(at: index)
        if answers.indices.contains(index) { answers.remove(at: index) }
        if results.indices.contains(index) { results.remove(at: index) }
        if index >= questions.count {
            index = max(questions.count - 1, 0)
        }
        submitted = false
        selection = []
        eliminated = []
        totalCorrect = results.filter { $0 }.count
        totalAnswered = results.count
    }

    /// 一组结束：按规则载入新一组
    func reload(_ newQuestions: [Question]) {
        questions = newQuestions
        groupIndex += 1
        index = 0
        answers = []
        results = []
        submitted = false
        selection = []
        eliminated = []
    }
}

// MARK: - 训练入口说明
// 训练设置已移至 ContentView 中的 TrainingSettingsSheet（工具栏按钮弹窗），
// 点击科目后在 SubjectPane.startTraining 中按当前设置直接生成 QuizSession 并跳转做题页。

/// navigationDestination 需要的 Hashable 包装
struct SessionBox: Hashable {
    let session: QuizSession
    static func == (lhs: SessionBox, rhs: SessionBox) -> Bool { lhs.session === rhs.session }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(session)) }
}

// MARK: - Claude Code 主题色

enum CCTheme {
    static let bg        = Color(red: 0xFA/255, green: 0xF8/255, blue: 0xF5/255)  // #FAF8F5 米白底
    static let card      = Color.white                                              // 卡片
    static let border    = Color(red: 0xE8/255, green: 0xE4/255, blue: 0xDF/255)  // #E8E4DF
    static let accent    = Color(red: 0xCC/255, green: 0x78/255, blue: 0x5C/255)  // #CC785C 橙
    static let accentBG  = Color(red: 0xF0/255, green: 0xEC/255, blue: 0xE5/255)  // #F0ECE5 柔和底
    static let textMain  = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255)  // #1A1A1A
    static let textSub   = Color(red: 0x6B/255, green: 0x65/255, blue: 0x60/255)  // #6B6560
    static let good      = Color(red: 0x8B/255, green: 0x9A/255, blue: 0x6D/255)  // #8B9A6D 橄榄绿
    static let bad       = Color(red: 0xE8/255, green: 0x68/255, blue: 0x6A/255)  // #E8686A 错误红
}

// MARK: - 答题视图

struct QuizRunnerView: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: QuizSession
    @State private var showVoiceInput = false
    @State private var voiceDraft = ""
    @FocusState private var voiceInputFocused: Bool
    /// 一组做完后按规则生成新一组题目
    var onNewGroup: () -> [Question]
    /// 点击下一题或下一组时清空当前题的手写内容
    var onAdvance: () -> Void

    var body: some View {
        if let q = session.current {
            questionView(q)
        } else {
            ContentUnavailableView(
                "暂无题目",
                systemImage: "tray",
                description: Text("当前规则下没有可练习的题目。")
            )
            .background(CCTheme.bg.ignoresSafeArea())
        }
    }

    // MARK: 答题页

    @ViewBuilder
    private func questionView(_ q: Question) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 进度（含跨组累计）
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(q.typeLabel)题 · 第 \(session.groupIndex) 组 \(session.index + 1)/\(session.questions.count)")
                            .font(.subheadline)
                            .foregroundStyle(CCTheme.textSub)
                        Spacer()
                        Text("本组对 \(session.correctCount) · 累计 \(session.totalCorrect)/\(session.totalAnswered)")
                            .font(.subheadline)
                            .foregroundStyle(CCTheme.good)
                    }
                    if let source = q.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !source.isEmpty {
                        Label("来源：\(source)", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(CCTheme.textSub)
                            .lineLimit(2)
                    }
                    ProgressView(value: Double(session.index + 1), total: Double(session.questions.count))
                        .tint(CCTheme.accent)
                }

                // 题干（LaTeX / 图片混排）
                RichMathText(raw: q.title, fontSize: 20)
                    .foregroundStyle(CCTheme.textMain)

                // 选项
                ForEach(q.optionKeys, id: \.self) { key in
                    optionRow(q: q, key: key)
                }

                // 多选：确认按钮（选了选项但未确认时显示）
                if q.questionType == "multiple" && !session.submitted && !session.selection.isEmpty {
                    Button {
                        session.confirmMultiple()
                    } label: {
                        confirmLabel
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CCTheme.accent)
                }

                // 操作按钮：「AI解析」填入左侧网页；「下一题 / 下一组」始终可点
                HStack(spacing: 10) {
                    Button {
                        model.requestAIExplanation(for: q)
                    } label: {
                        Label("AI解析", systemImage: "sparkles")
                            .font(.headline)
                            .frame(minWidth: 96, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(CCTheme.accent)

                    Button {
                        showVoiceInput = true
                        DispatchQueue.main.async {
                            voiceInputFocused = true
                        }
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.headline)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(CCTheme.accent)
                    .accessibilityLabel("打开语音输入")

                    Button {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            voiceInputFocused = false
                            showVoiceInput = false
                            onAdvance()
                            if session.index == session.questions.count - 1 {
                                session.reload(onNewGroup())
                            } else {
                                session.next()
                            }
                        }
                    } label: {
                        Text(session.index == session.questions.count - 1
                             ? "下一组（再练 \(session.questions.count) 题）"
                             : "下一题")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CCTheme.accent)
                    .id("next-\(session.groupIndex)-\(session.index)")
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .padding(.top, 8)

                // 解析
                if session.submitted {
                    explanationView(q)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(CCTheme.bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showVoiceInput {
                voiceInputBar
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var voiceInputBar: some View {
        HStack(spacing: 10) {
            TextField("语音输入", text: $voiceDraft, axis: .vertical)
                .focused($voiceInputFocused)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit(sendVoicePrompt)

            Button {
                sendVoicePrompt()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CCTheme.accent)
            .disabled(voiceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("发送")

            Button {
                voiceInputFocused = false
                showVoiceInput = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CCTheme.textSub)
            .accessibilityLabel("关闭语音输入")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func sendVoicePrompt() {
        let prompt = voiceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        model.requestWebPrompt(prompt)
        voiceDraft = ""
        voiceInputFocused = false
        showVoiceInput = false
    }

    /// 多选确认按钮文本
    private var confirmLabel: some View {
        let chosen = session.selection.sorted().joined(separator: "\u{3001}")
        return Text("确认选择 (\(chosen))")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 40)
    }

    private func optionRow(q: Question, key: String) -> some View {
        let selected = session.selection.contains(key)
        let eliminated = session.eliminated.contains(key)   // 已排除：置灰 + 删除线
        let judged = session.submitted                 // 已判定：正确项标绿
        let correct = judged && q.correctKeys.contains(key)
        let wrongPick = judged && selected && !q.correctKeys.contains(key)

        // Claude Code 风格状态色
        let badgeBG: Color = correct ? CCTheme.good
                          : (wrongPick ? CCTheme.bad
                          : (selected ? CCTheme.accent : CCTheme.accentBG))
        let badgeFG: Color = (selected || correct || wrongPick) ? .white : CCTheme.textSub
        let rowBG: Color = correct ? CCTheme.good.opacity(0.10)
                          : (wrongPick ? CCTheme.bad.opacity(0.08)
                          : (selected ? CCTheme.accent.opacity(0.08) : CCTheme.card))
        let strokeColor: Color = correct ? CCTheme.good
                          : (wrongPick ? CCTheme.bad
                          : (selected ? CCTheme.accent : CCTheme.border))
        let strokeWidth: CGFloat = (selected || correct || wrongPick) ? 1.5 : 1

        return HStack(alignment: .center, spacing: 8) {
            // 选项卡片：整卡可点
            Button {
                session.pick(key, single: q.questionType != "multiple")
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(key)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(badgeBG))
                        .foregroundStyle(badgeFG)
                    RichMathText(raw: q.optionText(key), fontSize: 18)
                        .foregroundStyle(eliminated ? CCTheme.textSub.opacity(0.7) : CCTheme.textMain)
                        .strikethrough(eliminated, color: CCTheme.bad)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(rowBG))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(strokeColor, lineWidth: strokeWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))   // 整个卡片区域响应点击
            }
            .buttonStyle(.plain)
            .disabled(eliminated)   // 排除后不可选

            // 删除/恢复选项按钮（卡片外，红色）
            if !eliminated {
                Button {
                    session.toggleEliminate(key)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(CCTheme.bad)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("排除选项")
            } else {
                Button {
                    session.toggleEliminate(key)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(CCTheme.textSub)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复选项")
            }
        }
        .opacity(eliminated ? 0.6 : 1)
    }

    @ViewBuilder
    private func explanationView(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("正确答案：\(q.correctAnswer)", systemImage: "checkmark.seal.fill")
                .foregroundStyle(CCTheme.good)
                .font(.subheadline.weight(.semibold))
            if let exp = q.explanation, !exp.isEmpty {
                MarkdownMathText(raw: exp, fontSize: 16)
                    .foregroundStyle(CCTheme.textMain)
            }
            if let ai = q.aiExplanation, !ai.isEmpty {
                Label("AI 解析", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CCTheme.textSub)
                    .padding(.top, 4)
                MarkdownMathText(raw: ai, fontSize: 14)
                    .foregroundStyle(CCTheme.textSub)
            }
            if let exp = q.explanation, exp.isEmpty, q.aiExplanation == nil {
                Text("暂无解析").font(.caption).foregroundStyle(CCTheme.textSub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CCTheme.accentBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CCTheme.border, lineWidth: 1))
    }

    // MARK: 已无结算页：一组完成后点「下一组」直接按规则开始新一组
}
