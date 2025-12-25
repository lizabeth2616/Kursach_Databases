-- Аудит
-- Посмотреть аудит для таблицы books
SELECT * FROM audit_log WHERE table_name = 'books' ORDER BY changed_at DESC LIMIT 5;


-- Представления
-- Детальная информация о книгах
SELECT * FROM book_details LIMIT 5;

-- Ежемесячные продажи
SELECT * FROM monthly_sales ORDER BY month DESC LIMIT 6;

-- Популярные книги
SELECT * FROM popular_books LIMIT 10;

-- Статистика пользователей
SELECT * FROM user_statistics WHERE total_orders > 0 LIMIT 5;


-- Функции
-- Сумма в корзине пользователя
SELECT get_cart_total(1) as cart_total_user_1;

-- Проверка наличия книги
SELECT check_book_availability(1, 5) as is_book_available;



-- Триггеры
-- 1. Демонстрация триггера обновления updated_at
-- Вставляем нового пользователя
INSERT INTO users (email, password_hash, first_name, last_name)
VALUES ('test@example.com', 'hash123', 'Иван', 'Тестов')
RETURNING user_id, created_at, updated_at;

-- Обновляем пользователя (триггер сработает на updated_at)
UPDATE users SET first_name = 'Иван Обновленный' 
WHERE email = 'test@example.com'
RETURNING user_id, created_at, updated_at;

-- 2. Демонстрация триггера пересчета рейтинга книги
-- Вставляем отзыв на книгу (ID=1)
INSERT INTO reviews (book_id, user_id, rating, comment)
VALUES (1, 1, 5, 'Отличная книга!')
RETURNING review_id;

-- Проверяем, обновился ли рейтинг книги
SELECT book_id, title, average_rating, total_reviews 
FROM books WHERE book_id = 1;

-- 3. Демонстрация триггера аудита на книгах
-- Создаем тестовую книгу
INSERT INTO books (title, author_id, genre_id, price, stock_quantity)
VALUES ('Тест аудита', 1, 1, 1000.00, 50)
RETURNING book_id;

-- Обновляем цену (триггер запишет в audit_log)
UPDATE books SET price = 1200.00 WHERE title = 'Тест аудита';

-- Удаляем книгу (тоже запишется в audit_log)
DELETE FROM books WHERE title = 'Тест аудита';

-- Смотрим что записалось в audit_log
SELECT table_name, record_id, action, changed_at 
FROM audit_log 
WHERE table_name = 'books' 
ORDER BY changed_at DESC 
LIMIT 5;

SELECT COUNT(*) FROM books;