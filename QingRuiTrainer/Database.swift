import Foundation
import SQLite3

/// SQLITE_TRANSIENT 在 Swift 中不可见，需自定义
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite 数据层
/// 首次启动时把 Bundle 内的 qingrui.db 复制到 Documents，App 使用自己的独立副本
final class Database {

    static let shared = Database()

    private var handle: OpaquePointer?

    private init() {
        openDatabase()
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    // MARK: - 打开 / 首次复制

    private var documentsPath: String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("qingrui.db").path
    }

    private func openDatabase() {
        let fm = FileManager.default

        // 若 Documents 中还没有 db，则从 Bundle 复制一份（App 自己的新 db）
        if !fm.fileExists(atPath: documentsPath),
           let bundled = Bundle.main.url(forResource: "qingrui", withExtension: "db") {
            try? fm.copyItem(at: bundled, to: URL(fileURLWithPath: documentsPath))
        }

        guard sqlite3_open(documentsPath, &handle) == SQLITE_OK else {
            NSLog("SQLite 打开失败: %s", sqlite3_errmsg(handle))
            handle = nil
            return
        }

        migrateEnglishStudyDataIfNeeded()
    }

    // MARK: - 辅助

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return columnText(stmt, idx)
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let handle else { return false }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(errorMessage)
            NSLog("SQLite 执行失败: %@", message)
            return false
        }
        return true
    }

    /// 覆盖安装时 Documents 中会保留旧数据库，因此需从新 Bundle 合并专项英语数据。
    private func migrateEnglishStudyDataIfNeeded() {
        guard let handle else { return }
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS english_materials (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          directory_id INTEGER NOT NULL,
          title TEXT,
          content TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (directory_id) REFERENCES directories(id)
        );
        CREATE TABLE IF NOT EXISTS english_questions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          material_id INTEGER NOT NULL,
          question_number INTEGER NOT NULL,
          title TEXT NOT NULL,
          option_a TEXT,
          option_b TEXT,
          option_c TEXT,
          option_d TEXT,
          correct_answer TEXT,
          explanation TEXT,
          sort_order INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (material_id) REFERENCES english_materials(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS english_words (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          phonetic TEXT NOT NULL DEFAULT '',
          meaning TEXT NOT NULL DEFAULT '',
          sort_order INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS english_translate (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          directory_id INTEGER NOT NULL,
          content TEXT NOT NULL,
          answer TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (directory_id) REFERENCES directories(id)
        );
        CREATE INDEX IF NOT EXISTS idx_english_materials_directory ON english_materials(directory_id);
        CREATE INDEX IF NOT EXISTS idx_english_questions_material ON english_questions(material_id);
        CREATE INDEX IF NOT EXISTS idx_english_words_word ON english_words(word);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_english_words_word_unique ON english_words(word);
        CREATE INDEX IF NOT EXISTS idx_english_translate_directory ON english_translate(directory_id);
        CREATE TABLE IF NOT EXISTS app_migrations (
          migration_key TEXT PRIMARY KEY,
          applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        guard execute(schemaSQL) else { return }

        let migrationKey = "english-study-seed-v2"
        var checkStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle,
            "SELECT 1 FROM app_migrations WHERE migration_key = ? LIMIT 1",
            -1,
            &checkStatement,
            nil
        ) == SQLITE_OK else { return }
        sqlite3_bind_text(checkStatement, 1, migrationKey, -1, SQLITE_TRANSIENT)
        let alreadyApplied = sqlite3_step(checkStatement) == SQLITE_ROW
        sqlite3_finalize(checkStatement)
        guard !alreadyApplied else { return }

        guard let bundledURL = Bundle.main.url(forResource: "qingrui", withExtension: "db") else {
            return
        }
        let seedURL = URL(fileURLWithPath: documentsPath)
            .deletingLastPathComponent()
            .appendingPathComponent("qingrui-english-seed.db")
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: seedURL)
        do {
            try fileManager.copyItem(at: bundledURL, to: seedURL)
        } catch {
            NSLog("英语学习数据准备失败: %@", error.localizedDescription)
            return
        }
        defer { try? fileManager.removeItem(at: seedURL) }

        var attachStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle,
            "ATTACH DATABASE ? AS bundled_seed",
            -1,
            &attachStatement,
            nil
        ) == SQLITE_OK else { return }
        sqlite3_bind_text(attachStatement, 1, seedURL.path, -1, SQLITE_TRANSIENT)
        let attached = sqlite3_step(attachStatement) == SQLITE_DONE
        sqlite3_finalize(attachStatement)
        guard attached else { return }

        let importSQL = """
        BEGIN;
        INSERT OR IGNORE INTO english_materials
          (id, directory_id, title, content, sort_order, created_at)
        SELECT id, directory_id, title, content, sort_order, created_at
        FROM bundled_seed.english_materials;
        INSERT OR IGNORE INTO english_questions
          (id, material_id, question_number, title, option_a, option_b, option_c, option_d,
           correct_answer, explanation, sort_order, created_at)
        SELECT id, material_id, question_number, title, option_a, option_b, option_c, option_d,
               correct_answer, explanation, sort_order, created_at
        FROM bundled_seed.english_questions;
        INSERT OR IGNORE INTO english_words
          (id, word, phonetic, meaning, sort_order, created_at)
        SELECT id, word, phonetic, meaning, sort_order, created_at
        FROM bundled_seed.english_words;
        INSERT OR IGNORE INTO english_translate
          (id, directory_id, content, answer, sort_order, created_at)
        SELECT id, directory_id, content, answer, sort_order, created_at
        FROM bundled_seed.english_translate;
        INSERT OR REPLACE INTO app_migrations (migration_key) VALUES ('\(migrationKey)');
        COMMIT;
        """
        _ = execute(importSQL)
        _ = execute("DETACH DATABASE bundled_seed")
    }

    // MARK: - 科目

    /// 全部科目（树形，含题目计数）
    func subjects() -> [Subject] {
        guard let handle else { return [] }
        var stmt: OpaquePointer?
        let sql = """
        SELECT d.id, d.name, d.parent_id,
               CASE
                 WHEN d.template = 'EnglishWord' OR d.name = '英语单词'
                   THEN (SELECT COUNT(*) FROM english_words)
                 WHEN d.name = '考研英语'
                   THEN (SELECT COUNT(*)
                         FROM english_questions eq
                         JOIN english_materials em ON em.id = eq.material_id
                         WHERE em.directory_id = d.id)
                 WHEN d.name = '英语翻译'
                   THEN (SELECT COUNT(*) FROM english_translate et WHERE et.directory_id = d.id)
                 ELSE (SELECT COUNT(*) FROM questions q WHERE q.directory_id = d.id)
               END
        FROM directories d
        ORDER BY d.sort_order, d.id
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var all: [Subject] = []
        var byId: [Int: Subject] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let parentIdInt = sqlite3_column_int64(stmt, 2)
            let s = Subject(
                id: Int(sqlite3_column_int64(stmt, 0)),
                name: columnText(stmt, 1),
                parentId: parentIdInt == 0 ? nil : Int(parentIdInt),
                questionCount: Int(sqlite3_column_int64(stmt, 3))
            )
            all.append(s)
            byId[s.id] = s
        }

        // 组装树并汇总计数
        var roots: [Subject] = []
        for s in all {
            if let pid = s.parentId, byId[pid] != nil {
                byId[pid]?.children.append(s)
            } else {
                roots.append(s)
            }
        }
        func rollup(_ s: inout Subject) -> Int {
            var total = s.questionCount
            for i in s.children.indices {
                total += rollup(&s.children[i])
            }
            s.totalCount = total
            return total
        }
        for i in roots.indices { _ = rollup(&roots[i]) }
        return roots
    }

    // MARK: - 题目

    /// 题目列表：指定科目（含子科目）、关键词搜索、分页
    func questions(directoryId: Int? = nil,
                   search: String = "",
                   limit: Int = 50,
                   offset: Int = 0) -> (items: [Question], total: Int) {
        guard let handle else { return ([], 0) }

        var conditions: [String] = []
        var params: [String] = []

        var ids: [Int] = []
        if let directoryId {
            ids = [directoryId]
            // 子科目
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, "SELECT id FROM directories WHERE parent_id = ?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(directoryId))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    ids.append(Int(sqlite3_column_int64(stmt, 0)))
                }
            }
            sqlite3_finalize(stmt)
        }

        if !ids.isEmpty {
            conditions.append("q.directory_id IN (\(ids.map(String.init).joined(separator: ",")))")
        }
        let kw = search.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty {
            conditions.append("q.title LIKE ?")
            params.append("%\(kw)%")
        }
        let whereSQL = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        // 总数
        var total = 0
        var cStmt: OpaquePointer?
        let countSQL = "SELECT COUNT(*) FROM questions q \(whereSQL)"
        if sqlite3_prepare_v2(handle, countSQL, -1, &cStmt, nil) == SQLITE_OK {
            params.enumerated().forEach { sqlite3_bind_text(cStmt, Int32($0.offset + 1), $0.element, -1, SQLITE_TRANSIENT) }
            if sqlite3_step(cStmt) == SQLITE_ROW { total = Int(sqlite3_column_int64(cStmt, 0)) }
        }
        sqlite3_finalize(cStmt)

        // 数据
        var items: [Question] = []
        var stmt: OpaquePointer?
        let sql = """
        SELECT q.id, q.directory_id, q.question_type, q.title,
               q.option_a, q.option_b, q.option_c, q.option_d, q.option_e,
               q.correct_answer, q.explanation, q.ai_explanation, q.source
        FROM questions q \(whereSQL)
        ORDER BY q.directory_id, q.sort_order, q.id
        LIMIT ? OFFSET ?
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return ([], 0) }
        defer { sqlite3_finalize(stmt) }
        params.enumerated().forEach { sqlite3_bind_text(stmt, Int32($0.offset + 1), $0.element, -1, SQLITE_TRANSIENT) }
        let bindStart = Int32(params.count + 1)
        sqlite3_bind_int(stmt, bindStart, Int32(limit))
        sqlite3_bind_int(stmt, bindStart + 1, Int32(offset))

        while sqlite3_step(stmt) == SQLITE_ROW {
            var options: [String: String] = [:]
            for (idx, key) in ["A", "B", "C", "D", "E"].enumerated() {
                let col = Int32(4 + idx)
                if sqlite3_column_type(stmt, col) != SQLITE_NULL {
                    options[key] = columnText(stmt, col)
                }
            }
            items.append(Question(
                id: Int(sqlite3_column_int64(stmt, 0)),
                directoryId: Int(sqlite3_column_int64(stmt, 1)),
                questionType: columnText(stmt, 2),
                title: columnText(stmt, 3),
                options: options,
                correctAnswer: columnText(stmt, 9),
                explanation: columnOptionalText(stmt, 10),
                aiExplanation: columnOptionalText(stmt, 11),
                source: columnOptionalText(stmt, 12)
            ))
        }
        return (items, total)
    }

    // MARK: - 考研英语阅读

    func englishReadingMaterials(directoryId: Int) -> [EnglishReadingMaterial] {
        guard let handle else { return [] }

        var questionsByMaterial: [Int: [EnglishReadingQuestion]] = [:]
        var questionStatement: OpaquePointer?
        let questionSQL = """
        SELECT q.id, q.material_id, q.question_number, q.title,
               q.option_a, q.option_b, q.option_c, q.option_d,
               q.correct_answer, q.explanation
        FROM english_questions q
        JOIN english_materials m ON m.id = q.material_id
        WHERE m.directory_id = ?
        ORDER BY m.sort_order, m.id, q.sort_order, q.question_number, q.id
        """
        if sqlite3_prepare_v2(handle, questionSQL, -1, &questionStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(questionStatement, 1, Int32(directoryId))
            while sqlite3_step(questionStatement) == SQLITE_ROW {
                var options: [String: String] = [:]
                for (index, key) in ["A", "B", "C", "D"].enumerated() {
                    let column = Int32(4 + index)
                    if sqlite3_column_type(questionStatement, column) != SQLITE_NULL {
                        options[key] = columnText(questionStatement, column)
                    }
                }
                let materialId = Int(sqlite3_column_int64(questionStatement, 1))
                questionsByMaterial[materialId, default: []].append(
                    EnglishReadingQuestion(
                        id: Int(sqlite3_column_int64(questionStatement, 0)),
                        materialId: materialId,
                        questionNumber: Int(sqlite3_column_int64(questionStatement, 2)),
                        title: columnText(questionStatement, 3),
                        options: options,
                        correctAnswer: columnText(questionStatement, 8),
                        explanation: columnOptionalText(questionStatement, 9)
                    )
                )
            }
        }
        sqlite3_finalize(questionStatement)

        var materials: [EnglishReadingMaterial] = []
        var materialStatement: OpaquePointer?
        let materialSQL = """
        SELECT id, directory_id, title, content
        FROM english_materials
        WHERE directory_id = ?
        ORDER BY sort_order, id
        """
        guard sqlite3_prepare_v2(handle, materialSQL, -1, &materialStatement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(materialStatement) }
        sqlite3_bind_int(materialStatement, 1, Int32(directoryId))
        while sqlite3_step(materialStatement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(materialStatement, 0))
            materials.append(
                EnglishReadingMaterial(
                    id: id,
                    directoryId: Int(sqlite3_column_int64(materialStatement, 1)),
                    title: columnOptionalText(materialStatement, 2),
                    content: columnText(materialStatement, 3),
                    questions: questionsByMaterial[id] ?? []
                )
            )
        }
        return materials
    }

    // MARK: - 英语单词

    func englishWords() -> [EnglishWord] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = """
        SELECT id, word, phonetic, meaning, sort_order
        FROM english_words
        ORDER BY sort_order, id
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var words: [EnglishWord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            words.append(
                EnglishWord(
                    id: Int(sqlite3_column_int64(statement, 0)),
                    word: columnText(statement, 1),
                    phonetic: columnText(statement, 2),
                    meaning: columnText(statement, 3),
                    sortOrder: Int(sqlite3_column_int64(statement, 4))
                )
            )
        }
        return words
    }

    @discardableResult
    func deleteEnglishWord(id: Int) -> Bool {
        guard let handle else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM english_words WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    // MARK: - 英语翻译

    func englishTranslations(directoryId: Int) -> [EnglishTranslationItem] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = """
        SELECT id, directory_id, content, answer, sort_order
        FROM english_translate
        WHERE directory_id = ?
        ORDER BY sort_order, id
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(directoryId))

        var items: [EnglishTranslationItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(
                EnglishTranslationItem(
                    id: Int(sqlite3_column_int64(statement, 0)),
                    directoryId: Int(sqlite3_column_int64(statement, 1)),
                    content: columnText(statement, 2),
                    answer: columnText(statement, 3),
                    sortOrder: Int(sqlite3_column_int64(statement, 4))
                )
            )
        }
        return items
    }

    func addEnglishTranslation(
        directoryId: Int,
        content: String,
        answer: String
    ) -> EnglishTranslationItem? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO english_translate (directory_id, content, answer, sort_order)
        VALUES (?, ?, ?, COALESCE((SELECT MAX(sort_order) + 1 FROM english_translate WHERE directory_id = ?), 0))
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(directoryId))
        sqlite3_bind_text(statement, 2, content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, answer, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(directoryId))
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }

        return EnglishTranslationItem(
            id: Int(sqlite3_last_insert_rowid(handle)),
            directoryId: directoryId,
            content: content,
            answer: answer,
            sortOrder: englishTranslations(directoryId: directoryId).last?.sortOrder ?? 0
        )
    }

    @discardableResult
    func deleteEnglishTranslation(id: Int) -> Bool {
        guard let handle else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM english_translate WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        return sqlite3_step(statement) == SQLITE_DONE
    }
}
