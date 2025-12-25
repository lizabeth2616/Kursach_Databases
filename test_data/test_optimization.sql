-- Тестирование оптимизации запросов

-- 1. Показываем текущие индексы
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public' 
AND tablename IN ('books', 'orders', 'reviews')
ORDER BY tablename, indexname;

-- 2. Тест без индекса (временное удаление)
DROP INDEX IF EXISTS idx_books_search;
DROP INDEX IF EXISTS idx_orders_composite;

-- 3. Медленные запросы
EXPLAIN ANALYZE
SELECT b.*, a.full_name 
FROM books b
JOIN authors a ON b.author_id = a.author_id
WHERE b.title LIKE '%война%' 
AND b.price BETWEEN 300 AND 1000
AND b.genre_id = 6;

EXPLAIN ANALYZE
SELECT o.*, u.email
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.status = 'delivered'
AND o.order_date BETWEEN '2024-01-01' AND '2024-12-31'
ORDER BY o.order_date DESC;

-- 4. Восстанавливаем индексы
CREATE INDEX idx_books_search ON books(title, author_id, genre_id);
CREATE INDEX idx_orders_composite ON orders(user_id, status, order_date);

-- 5. Быстрые запросы (те же самые)
EXPLAIN ANALYZE
SELECT b.*, a.full_name 
FROM books b
JOIN authors a ON b.author_id = a.author_id
WHERE b.title LIKE '%война%' 
AND b.price BETWEEN 300 AND 1000
AND b.genre_id = 6;

EXPLAIN ANALYZE
SELECT o.*, u.email
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.status = 'delivered'
AND o.order_date BETWEEN '2024-01-01' AND '2024-12-31'
ORDER BY o.order_date DESC;