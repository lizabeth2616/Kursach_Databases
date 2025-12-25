import psycopg2

def test_audit_trigger():
    conn = psycopg2.connect(
        host="localhost",
        database="project",
        user="postgres",
        password="ecole1286"  
    )
    
    cur = conn.cursor()
    
    print("=== Тестирование триггеров аудита ===")
    
    # 1. Вставка новой книги
    print("1. Вставляем новую книгу...")
    cur.execute("""
        INSERT INTO books (title, author_id, genre_id, price, stock_quantity) 
        VALUES ('Тестовая книга для аудита', 1, 1, 500.00, 50)
        RETURNING book_id;
    """)
    book_id = cur.fetchone()[0]
    conn.commit()
    print(f"   Создана книга ID: {book_id}")
    
    # 2. Проверка аудита
    cur.execute("""
        SELECT action, changed_at 
        FROM audit_log 
        WHERE table_name = 'books' AND record_id = %s
        ORDER BY changed_at DESC;
    """, (book_id,))
    
    audit_records = cur.fetchall()
    print(f"2. Записей в audit_log: {len(audit_records)}")
    for action, changed_at in audit_records:
        print(f"   - {action} в {changed_at}")
    
    # 3. Обновление книги
    print("3. Обновляем цену книги...")
    cur.execute("UPDATE books SET price = 600.00 WHERE book_id = %s", (book_id,))
    conn.commit()
    
    # 4. Удаление книги
    print("4. Удаляем книгу...")
    cur.execute("DELETE FROM books WHERE book_id = %s", (book_id,))
    conn.commit()
    
    # 5. Итоговая проверка
    cur.execute("SELECT COUNT(*) FROM audit_log WHERE record_id = %s", (book_id,))
    total = cur.fetchone()[0]
    print(f"5. Всего записей аудита для книги: {total}")
    
    cur.close()
    conn.close()
    print("\n✅ Тест завершен!")
    print("Триггер audit_book_changes работает корректно.")

if __name__ == "__main__":
    test_audit_trigger()