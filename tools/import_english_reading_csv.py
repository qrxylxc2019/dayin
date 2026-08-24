#!/usr/bin/env python3
"""
Import authorized English reading materials into QingRuiTrainer's SQLite seed DB.

CSV columns:
year,paper,text_no,directory_id,material_title,material_content,material_sort_order,
question_number,question_title,option_a,option_b,option_c,option_d,correct_answer,
explanation,source_url
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path


REQUIRED_COLUMNS = [
    "year",
    "paper",
    "text_no",
    "directory_id",
    "material_title",
    "material_content",
    "material_sort_order",
    "question_number",
    "question_title",
    "option_a",
    "option_b",
    "option_c",
    "option_d",
    "correct_answer",
    "explanation",
    "source_url",
]


def text(value: str | None) -> str:
    return (value or "").strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import English reading CSV into qingrui.db"
    )
    parser.add_argument("csv_path", type=Path)
    parser.add_argument(
        "--db",
        type=Path,
        default=Path("QingRuiTrainer/Resources/qingrui.db"),
        help="Path to qingrui.db",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Replace existing materials with the same directory_id + material_title",
    )
    parser.add_argument(
        "--allow-incomplete",
        action="store_true",
        help="Skip validation for blank material/question fields",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and summarize the CSV without writing to the database",
    )
    return parser.parse_args()


def read_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = [column for column in REQUIRED_COLUMNS if column not in reader.fieldnames]
        if missing:
            raise SystemExit(f"CSV missing columns: {', '.join(missing)}")
        return [{key: text(value) for key, value in row.items()} for row in reader]


def validate(rows: list[dict[str, str]], allow_incomplete: bool) -> None:
    if not rows:
        raise SystemExit("CSV has no data rows")
    if allow_incomplete:
        return

    required_text = [
        "directory_id",
        "material_title",
        "material_content",
        "question_number",
        "question_title",
        "option_a",
        "option_b",
        "option_c",
        "option_d",
        "correct_answer",
    ]
    errors: list[str] = []
    for index, row in enumerate(rows, start=2):
        for column in required_text:
            if not row.get(column):
                errors.append(f"row {index}: {column} is blank")
        answer = row.get("correct_answer", "").upper()
        if answer and answer not in {"A", "B", "C", "D"}:
            errors.append(f"row {index}: correct_answer must be A/B/C/D")
    if errors:
        raise SystemExit("Validation failed:\n" + "\n".join(errors[:40]))


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
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
        CREATE INDEX IF NOT EXISTS idx_english_materials_directory
          ON english_materials(directory_id);
        CREATE INDEX IF NOT EXISTS idx_english_questions_material
          ON english_questions(material_id);
        """
    )


def material_key(row: dict[str, str]) -> tuple[int, str]:
    return (int(row["directory_id"]), row["material_title"])


def import_rows(conn: sqlite3.Connection, rows: list[dict[str, str]], replace: bool) -> None:
    grouped: dict[tuple[int, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        grouped[material_key(row)].append(row)

    with conn:
        ensure_schema(conn)
        for (directory_id, title), material_rows in grouped.items():
            first = material_rows[0]
            source_url = text(first.get("source_url"))
            content = first["material_content"]
            if source_url and source_url not in content:
                content = f"{content}\n\n来源：{source_url}"
            sort_order = int(first["material_sort_order"] or 0)

            existing = conn.execute(
                """
                SELECT id FROM english_materials
                WHERE directory_id = ? AND title = ?
                ORDER BY id LIMIT 1
                """,
                (directory_id, title),
            ).fetchone()

            if existing and replace:
                material_id = int(existing[0])
                conn.execute("DELETE FROM english_questions WHERE material_id = ?", (material_id,))
                conn.execute(
                    """
                    UPDATE english_materials
                    SET content = ?, sort_order = ?
                    WHERE id = ?
                    """,
                    (content, sort_order, material_id),
                )
            elif existing:
                material_id = int(existing[0])
            else:
                cursor = conn.execute(
                    """
                    INSERT INTO english_materials
                      (directory_id, title, content, sort_order)
                    VALUES (?, ?, ?, ?)
                    """,
                    (directory_id, title, content, sort_order),
                )
                material_id = int(cursor.lastrowid)

            if not replace and existing:
                existing_questions = conn.execute(
                    "SELECT COUNT(*) FROM english_questions WHERE material_id = ?",
                    (material_id,),
                ).fetchone()[0]
                if existing_questions:
                    print(f"skip existing material: {title}", file=sys.stderr)
                    continue

            for row in sorted(material_rows, key=lambda item: int(item["question_number"])):
                conn.execute(
                    """
                    INSERT INTO english_questions
                      (material_id, question_number, title, option_a, option_b,
                       option_c, option_d, correct_answer, explanation, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        material_id,
                        int(row["question_number"]),
                        row["question_title"],
                        row["option_a"],
                        row["option_b"],
                        row["option_c"],
                        row["option_d"],
                        row["correct_answer"].upper(),
                        row["explanation"],
                        int(row["question_number"]),
                    ),
                )


def main() -> int:
    args = parse_args()
    rows = read_rows(args.csv_path)
    validate(rows, args.allow_incomplete)
    if not args.db.exists():
        raise SystemExit(f"DB not found: {args.db}")

    grouped = {material_key(row) for row in rows}
    if args.dry_run:
        print(
            f"Validated {len(rows)} question rows across {len(grouped)} materials "
            f"from {args.csv_path}"
        )
        return 0

    conn = sqlite3.connect(args.db)
    try:
        import_rows(conn, rows, replace=args.replace)
    finally:
        conn.close()

    print(f"Imported {len(rows)} question rows from {args.csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
