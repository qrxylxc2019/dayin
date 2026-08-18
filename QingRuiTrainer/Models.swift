import Foundation

// MARK: - 科目（directories 表）

struct Subject: Identifiable, Hashable {
    let id: Int
    let name: String
    let parentId: Int?
    var questionCount: Int = 0   // 本科目直属题目数
    var totalCount: Int = 0      // 含子科目的总数
    var children: [Subject] = []
}

// MARK: - 题目（questions 表）

struct Question: Identifiable, Hashable {
    let id: Int
    let directoryId: Int
    let questionType: String     // single / multiple / judge
    let title: String
    let options: [String: String] // "A" -> 文本
    let correctAnswer: String
    let explanation: String?
    let aiExplanation: String?
    let source: String?

    var typeLabel: String {
        switch questionType {
        case "single": return "单选"
        case "multiple": return "多选"
        case "judge": return "判断"
        default: return questionType
        }
    }

    /// 选项字母列表（判断题无选项时用 A=正确 / B=错误）
    var optionKeys: [String] {
        let keys = ["A", "B", "C", "D", "E"].filter { options[$0] != nil }
        return keys.isEmpty && questionType == "judge" ? ["A", "B"] : keys
    }

    func optionText(_ key: String) -> String {
        if questionType == "judge" && options.isEmpty {
            return key == "A" ? "正确" : "错误"
        }
        return options[key] ?? ""
    }

    /// 规范化后的正确答案字母集合
    var correctKeys: Set<String> {
        Set(correctAnswer.uppercased()
            .filter { $0.isLetter }
            .map { String($0) })
    }
}

// MARK: - 考研英语阅读

struct EnglishReadingQuestion: Identifiable, Hashable {
    let id: Int
    let materialId: Int
    let questionNumber: Int
    let title: String
    let options: [String: String]
    let correctAnswer: String
    let explanation: String?

    var optionKeys: [String] {
        ["A", "B", "C", "D"].filter { options[$0] != nil }
    }

    func optionText(_ key: String) -> String {
        options[key] ?? ""
    }

    func asQuestion(directoryId: Int) -> Question {
        Question(
            id: id,
            directoryId: directoryId,
            questionType: "single",
            title: title,
            options: options,
            correctAnswer: correctAnswer,
            explanation: explanation,
            aiExplanation: nil,
            source: "考研英语阅读 第 \(questionNumber) 题"
        )
    }
}

struct EnglishReadingMaterial: Identifiable, Hashable {
    let id: Int
    let directoryId: Int
    let title: String?
    let content: String
    let questions: [EnglishReadingQuestion]
}

// MARK: - 英语单词

struct EnglishWord: Identifiable, Hashable {
    let id: Int
    let word: String
    let phonetic: String
    let meaning: String
    let sortOrder: Int
}

// MARK: - 英语翻译

struct EnglishTranslationItem: Identifiable, Hashable {
    let id: Int
    let directoryId: Int
    let content: String
    let answer: String
    let sortOrder: Int
}
