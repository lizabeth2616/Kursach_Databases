
-- БАЗОВЫЕ ДАННЫЕ ДЛЯ ТЕСТИРОВАНИЯ HRM-СИСТЕМЫ

DO $$
BEGIN
    -- Проверяем, есть ли уже данные в таблице Departments
    IF NOT EXISTS (SELECT 1 FROM departments LIMIT 1) THEN
        RAISE NOTICE 'Загружаем данные из 06_load_generated.sql...';
        
        -- Выполняем внешний файл с данными
        RAISE NOTICE 'Файл 06_load_generated.sql должен быть выполнен отдельно';
        RAISE NOTICE 'или через команду: \i 06_load_generated.sql';
    ELSE
        RAISE NOTICE 'Данные уже загружены, пропускаем загрузку...';
    END IF;
END $$;


-- ДОПОЛНИТЕЛЬНЫЕ ДАННЫЕ, КОТОРЫХ НЕТ В ГЕНЕРИРОВАННОМ ФАЙЛЕ

-- Устанавливаем контекст для аудита
SELECT set_audit_context(1, 'post_generation_setup');

-- 1. Обновляем структуру отделов (добавляем manager_id если его нет)
DO $$
BEGIN
    -- Проверяем наличие столбца manager_id
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'departments' AND column_name = 'manager_id') THEN
        
        -- Назначаем руководителей отделов
        -- Для отдела Руководство находим сотрудника с самой высокой зарплатой
        UPDATE departments d
        SET manager_id = (
            SELECT e.employee_id 
            FROM employees e 
            WHERE e.department_id = d.department_id 
            ORDER BY e.salary DESC 
            LIMIT 1
        )
        WHERE manager_id IS NULL;
        
        RAISE NOTICE 'Назначены руководители отделов';
    END IF;
END $$;

-- 2. Проверяем и создаем недостающие позиции
INSERT INTO positions (position_title, position_level, base_salary_min, base_salary_max, description, requirements) 
SELECT * FROM (VALUES
    ('Генеральный директор', 'executive', 250000, 500000, 'Руководитель компании', 'Высшее образование, опыт управления от 10 лет'),
    ('Технический директор', 'director', 200000, 350000, 'Руководитель технического блока', 'Техническое образование, опыт от 8 лет'),
    ('Финансовый директор', 'director', 180000, 300000, 'Руководитель финансового блока', 'Финансовое образование, опыт от 8 лет'),
    ('Руководитель отдела разработки', 'manager', 150000, 250000, 'Руководитель команды разработки', 'Опыт разработки от 5 лет, навыки управления'),
    ('Руководитель тестирования', 'manager', 120000, 200000, 'Руководитель QA-отдела', 'Опыт тестирования от 5 лет'),
    ('Руководитель отдела продаж', 'manager', 130000, 220000, 'Руководитель продаж', 'Опыт продаж от 5 лет, навыки управления командой'),
    ('Старший разработчик', 'senior', 120000, 180000, 'Ведущий разработчик', 'Опыт разработки от 5 лет, знание нескольких языков'),
    ('Разработчик', 'middle', 80000, 130000, 'Разработчик ПО', 'Опыт разработки от 2 лет'),
    ('Младший разработчик', 'junior', 50000, 80000, 'Начинающий разработчик', 'Базовые знания программирования'),
    ('Старший тестировщик', 'senior', 90000, 140000, 'Ведущий специалист по тестированию', 'Опыт тестирования от 4 лет'),
    ('Тестировщик', 'middle', 60000, 90000, 'Специалист по тестированию', 'Опыт тестирования от 1 года'),
    ('Менеджер по продажам', 'middle', 70000, 120000, 'Специалист по продажам', 'Опыт продаж от 2 лет'),
    ('Маркетолог', 'middle', 65000, 100000, 'Специалист по маркетингу', 'Опыт маркетинга от 2 лет'),
    ('Бухгалтер', 'senior', 80000, 130000, 'Старший бухгалтер', 'Высшее экономическое, опыт от 5 лет'),
    ('HR-менеджер', 'middle', 60000, 95000, 'Специалист по персоналу', 'Опыт HR от 2 лет'),
    ('Специалист техподдержки', 'junior', 40000, 60000, 'Специалист поддержки пользователей', 'Технические знания, клиентоориентированность'),
    ('Аналитик данных', 'middle', 85000, 130000, 'Специалист по аналитике', 'Знание SQL, статистики, опыт от 2 лет'),
    ('Администратор', 'junior', 35000, 50000, 'Офис-менеджер', 'Организаторские навыки, опыт работы с документами')
) AS new_positions(pos_title, pos_level, min_sal, max_sal, descr, reqs)
WHERE NOT EXISTS (
    SELECT 1 FROM positions p WHERE p.position_title = new_positions.pos_title
);

-- 3. Назначаем должности сотрудникам на основе зарплаты и отдела
DO $$
DECLARE
    emp_record RECORD;
    pos_id INT;
BEGIN
    FOR emp_record IN 
        SELECT e.employee_id, e.salary, e.department_id, d.department_name
        FROM employees e
        JOIN departments d ON e.department_id = d.department_id
        WHERE e.position_id IS NULL
    LOOP
        -- Определяем должность на основе зарплаты и отдела
        pos_id := CASE 
            WHEN emp_record.salary >= 250000 THEN 1  -- Гендир
            WHEN emp_record.salary >= 200000 AND emp_record.department_name LIKE '%Руковод%' THEN 1
            WHEN emp_record.salary >= 200000 AND emp_record.department_name LIKE '%ИТ%' THEN 2  -- Техдир
            WHEN emp_record.salary >= 180000 AND emp_record.department_name LIKE '%Финан%' THEN 3  -- Финдир
            WHEN emp_record.salary >= 150000 AND emp_record.department_name LIKE '%Разраб%' THEN 4  -- Рук. разработки
            WHEN emp_record.salary >= 150000 AND emp_record.department_name LIKE '%Продаж%' THEN 6  -- Рук. продаж
            WHEN emp_record.salary >= 120000 AND emp_record.department_name LIKE '%ИТ%' THEN 7  -- Старший разработчик
            WHEN emp_record.salary >= 90000 AND emp_record.department_name LIKE '%ИТ%' THEN 8  -- Разработчик
            WHEN emp_record.salary >= 80000 AND emp_record.department_name LIKE '%Бухгал%' THEN 14  -- Бухгалтер
            WHEN emp_record.salary >= 70000 AND emp_record.department_name LIKE '%Продаж%' THEN 12  -- Менеджер продаж
            WHEN emp_record.salary >= 65000 AND emp_record.department_name LIKE '%Маркет%' THEN 13  -- Маркетолог
            WHEN emp_record.salary >= 60000 AND emp_record.department_name LIKE '%Кадр%' THEN 15  -- HR
            WHEN emp_record.salary >= 50000 AND emp_record.department_name LIKE '%ИТ%' THEN 9  -- Младший разработчик
            WHEN emp_record.salary >= 40000 AND emp_record.department_name LIKE '%Поддерж%' THEN 16  -- Техподдержка
            WHEN emp_record.salary >= 35000 THEN 18  -- Администратор
            ELSE 18  -- По умолчанию администратор
        END;
        
        UPDATE employees 
        SET position_id = pos_id 
        WHERE employee_id = emp_record.employee_id;
    END LOOP;
    
    RAISE NOTICE 'Назначены должности сотрудникам';
END $$;

-- 4. Назначаем менеджеров сотрудникам
DO $$
DECLARE
    dept_record RECORD;
    manager_id INT;
BEGIN
    FOR dept_record IN 
        SELECT d.department_id, d.manager_id
        FROM departments d
        WHERE d.manager_id IS NOT NULL
    LOOP
        -- Назначаем менеджером руководителя отдела для всех сотрудников этого отдела
        -- (кроме самого руководителя)
        UPDATE employees e
        SET manager_id = dept_record.manager_id
        WHERE e.department_id = dept_record.department_id
            AND e.employee_id != dept_record.manager_id
            AND e.manager_id IS NULL;
    END LOOP;
    
    -- Для руководителей отделов назначаем менеджером гендира
    UPDATE employees e
    SET manager_id = (
        SELECT d.manager_id 
        FROM departments d 
        WHERE d.department_id = 1
        LIMIT 1
    )
    WHERE e.employee_id IN (
        SELECT manager_id FROM departments WHERE department_id > 1
    )
    AND e.manager_id IS NULL;
    
    RAISE NOTICE 'Назначены менеджеры сотрудникам';
END $$;

-- СОЗДАНИЕ ПРОЕКТОВ И ДРУГИХ СВЯЗАННЫХ ДАННЫХ

-- 5. Создаем навыки (если их еще нет)
INSERT INTO skills (skill_name, category, description) 
SELECT * FROM (VALUES
    ('Java', 'programming', 'Язык программирования Java'),
    ('Python', 'programming', 'Язык программирования Python'),
    ('SQL', 'databases', 'Язык запросов к базам данных'),
    ('JavaScript', 'programming', 'Язык программирования для веб-разработки'),
    ('Docker', 'devops', 'Контейнеризация приложений'),
    ('Git', 'version_control', 'Система контроля версий'),
    ('Selenium', 'testing', 'Автоматизация тестирования веб-приложений'),
    ('JUnit', 'testing', 'Фреймворк для модульного тестирования'),
    ('Тестирование API', 'testing', 'Тестирование программных интерфейсов'),
    ('Управление проектами', 'management', 'Методологии управления проектами'),
    ('Agile/Scrum', 'management', 'Гибкие методологии разработки'),
    ('Продажи', 'business', 'Навыки продаж и ведения переговоров'),
    ('Маркетинг', 'business', 'Маркетинговые стратегии и аналитика'),
    ('Лидерство', 'soft_skills', 'Умение вести за собой команду'),
    ('Коммуникация', 'soft_skills', 'Эффективная коммуникация'),
    ('Аналитическое мышление', 'soft_skills', 'Способность к анализу и решению проблем'),
    ('Клиентоориентированность', 'soft_skills', 'Фокус на потребностях клиента'),
    ('Бухгалтерский учет', 'finance', 'Ведение бухгалтерского учета'),
    ('Финансовый анализ', 'finance', 'Анализ финансовых показателей')
) AS new_skills(skill_name, category, description)
WHERE NOT EXISTS (
    SELECT 1 FROM skills s WHERE s.skill_name = new_skills.skill_name
);

-- 6. Создаем проекты
INSERT INTO projects (project_name, description, department_id, start_date, end_date, budget, status, project_manager_id) 
SELECT * FROM (VALUES
    ('Разработка CRM-системы', 'Создание системы управления взаимоотношениями с клиентами', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%ИТ%' LIMIT 1), 
     '2023-01-15', '2023-12-31', 5000000.00, 'active',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%ИТ%' LIMIT 1)),
    
    ('Мобильное приложение банка', 'Разработка мобильного банкинга для iOS и Android', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%ИТ%' LIMIT 1), 
     '2023-03-01', '2024-06-30', 8000000.00, 'active',
     (SELECT e.employee_id FROM employees e 
      WHERE e.department_id = (SELECT department_id FROM departments WHERE department_name LIKE '%ИТ%' LIMIT 1)
      ORDER BY e.salary DESC LIMIT 1 OFFSET 1)),
    
    ('Автоматизация тестирования', 'Внедрение автоматизированного тестирования для всех продуктов', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%Тест%' OR department_name LIKE '%QA%' LIMIT 1), 
     '2023-05-10', '2023-11-30', 1500000.00, 'active',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%Тест%' OR department_name LIKE '%QA%' LIMIT 1)),
    
    ('Расширение рынка продаж', 'Выход на новые региональные рынки', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%Продаж%' LIMIT 1), 
     '2023-02-01', '2023-12-31', 3000000.00, 'active',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%Продаж%' LIMIT 1)),
    
    ('Ребрендинг компании', 'Обновление бренда и маркетинговой стратегии', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%Маркет%' LIMIT 1), 
     '2023-04-15', '2024-02-28', 2000000.00, 'planning',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%Маркет%' LIMIT 1)),
    
    ('Оптимизация финансовых процессов', 'Автоматизация финансовой отчетности', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%Бухгал%' OR department_name LIKE '%Финан%' LIMIT 1), 
     '2023-06-01', '2023-12-15', 1200000.00, 'active',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%Бухгал%' OR department_name LIKE '%Финан%' LIMIT 1)),
    
    ('Система поддержки пользователей', 'Внедрение новой системы техподдержки', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%Поддерж%' LIMIT 1), 
     '2023-03-20', '2023-10-31', 800000.00, 'active',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%Поддерж%' LIMIT 1)),
    
    ('Аналитика больших данных', 'Создание системы аналитики для бизнес-решений', 
     (SELECT department_id FROM departments WHERE department_name LIKE '%Аналит%' LIMIT 1), 
     '2023-07-01', '2024-03-31', 2500000.00, 'active',
     (SELECT manager_id FROM departments WHERE department_name LIKE '%Аналит%' LIMIT 1))
) AS new_projects(project_name, description, department_id, start_date, end_date, budget, status, project_manager_id)
WHERE NOT EXISTS (
    SELECT 1 FROM projects p WHERE p.project_name = new_projects.project_name
);

-- НАЗНАЧЕНИЕ НАВЫКОВ И ПРОЕКТОВ СОТРУДНИКАМ

-- 7. Назначаем навыки сотрудникам
DO $$
BEGIN
    -- Для разработчиков
    INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, certified)
    SELECT 
        e.employee_id,
        s.skill_id,
        CASE 
            WHEN e.salary >= 150000 THEN 'expert'
            WHEN e.salary >= 100000 THEN 'advanced'
            WHEN e.salary >= 70000 THEN 'intermediate'
            ELSE 'beginner'
        END as level,
        (e.salary >= 100000) as certified
    FROM employees e
    CROSS JOIN skills s
    WHERE e.department_id IN (
        SELECT department_id FROM departments 
        WHERE department_name LIKE '%ИТ%' 
           OR department_name LIKE '%Разраб%'
    )
    AND s.category IN ('programming', 'databases', 'devops', 'version_control')
    AND NOT EXISTS (
        SELECT 1 FROM employee_skills es 
        WHERE es.employee_id = e.employee_id 
        AND es.skill_id = s.skill_id
    )
    ORDER BY random()
    LIMIT 100;  -- Ограничиваем количество назначений
    
    RAISE NOTICE 'Назначены навыки сотрудникам';
END $$;

-- 8. Назначаем сотрудников на проекты
DO $$
BEGIN
    INSERT INTO employee_projects (employee_id, project_id, role_in_project, participation_percentage, start_date)
    SELECT 
        e.employee_id,
        p.project_id,
        CASE 
            WHEN e.employee_id = p.project_manager_id THEN 'Руководитель проекта'
            WHEN e.salary >= 150000 THEN 'Ведущий специалист'
            WHEN e.salary >= 100000 THEN 'Старший специалист'
            ELSE 'Специалист'
        END as role,
        70 + random() * 30 as participation,  -- От 70% до 100%
        p.start_date + (random() * 30) * INTERVAL '1 day'  -- В течение первых 30 дней
    FROM employees e
    CROSS JOIN projects p
    WHERE e.department_id = p.department_id
    AND NOT EXISTS (
        SELECT 1 FROM employee_projects ep 
        WHERE ep.employee_id = e.employee_id 
        AND ep.project_id = p.project_id
    )
    ORDER BY random()
    LIMIT 200;  -- Ограничиваем количество назначений
    
    RAISE NOTICE 'Сотрудники назначены на проекты';
END $$;

-- ВЫВОД СТАТИСТИКИ И ИТОГОВ

SELECT '=== ОТЧЕТ ПО ЗАГРУЖЕННЫМ ДАННЫМ ===' as report_header;

SELECT 
    (SELECT COUNT(*) FROM departments) as total_departments,
    (SELECT COUNT(*) FROM positions) as total_positions,
    (SELECT COUNT(*) FROM employees) as total_employees,
    (SELECT COUNT(*) FROM employees WHERE is_active = TRUE) as active_employees,
    (SELECT COUNT(*) FROM skills) as total_skills,
    (SELECT COUNT(*) FROM projects) as total_projects,
    (SELECT COUNT(*) FROM employee_projects) as total_project_assignments,
    (SELECT COUNT(*) FROM employee_skills) as total_skill_assignments;

-- Пример иерархии подчинения
SELECT '=== ПРИМЕР ИЕРАРХИИ (первые 10 записей) ===' as hierarchy_header;
SELECT 
    e.first_name || ' ' || e.last_name as employee,
    p.position_title,
    d.department_name,
    CASE 
        WHEN e.manager_id IS NULL THEN 'Нет руководителя'
        ELSE (SELECT first_name || ' ' || last_name FROM employees WHERE employee_id = e.manager_id)
    END as manager
FROM employees e
LEFT JOIN positions p ON e.position_id = p.position_id
LEFT JOIN departments d ON e.department_id = d.department_id
ORDER BY e.department_id, e.salary DESC
LIMIT 10;

-- Отчет по отделам
SELECT '=== СТАТИСТИКА ПО ОТДЕЛАМ ===' as department_header;
SELECT 
    d.department_name,
    COUNT(e.employee_id) as total_employees,
    COALESCE(SUM(e.salary), 0) as total_salary_fund,
    COALESCE(AVG(e.salary), 0) as avg_salary,
    d.budget
FROM departments d
LEFT JOIN employees e ON d.department_id = e.department_id AND e.is_active = TRUE
GROUP BY d.department_id, d.department_name, d.budget
ORDER BY total_salary_fund DESC;

-- СОЗДАНИЕ ОТПУСКОВ (ДЛЯ ПРИМЕРА)
INSERT INTO vacations (employee_id, vacation_type, start_date, end_date, status, notes)
SELECT 
    e.employee_id,
    CASE 
        WHEN random() > 0.7 THEN 'sick'
        WHEN random() > 0.9 THEN 'unpaid'
        ELSE 'annual'
    END as vacation_type,
    CURRENT_DATE + (random() * 180) * INTERVAL '1 day' as start_date,
    CURRENT_DATE + (random() * 180 + 7) * INTERVAL '1 day' as end_date,
    CASE 
        WHEN random() > 0.3 THEN 'approved'
        WHEN random() > 0.6 THEN 'taken'
        ELSE 'requested'
    END as status,
    CASE 
        WHEN random() > 0.8 THEN 'Плановый отпуск'
        WHEN random() > 0.6 THEN 'Семейные обстоятельства'
        ELSE NULL
    END as notes
FROM employees e
WHERE e.is_active = TRUE
ORDER BY random()
LIMIT 20;

-- ФИНАЛЬНЫЙ ОТЧЕТ

DO $$
DECLARE
    dept_count INT;
    emp_count INT;
    proj_count INT;
BEGIN
    SELECT COUNT(*) INTO dept_count FROM departments;
    SELECT COUNT(*) INTO emp_count FROM employees;
    SELECT COUNT(*) INTO proj_count FROM projects;
    
    RAISE NOTICE 'НАСТРОЙКА ДАННЫХ ЗАВЕРШЕНА!';
    RAISE NOTICE '=============================';
    RAISE NOTICE 'Загружено отделов: %', dept_count;
    RAISE NOTICE 'Загружено сотрудников: %', emp_count;
    RAISE NOTICE 'Создано проектов: %', proj_count;
    RAISE NOTICE '=============================';
    RAISE NOTICE '';
    RAISE NOTICE 'Для полной загрузки выполните:';
    RAISE NOTICE 'psql -U ваш_пользователь -d ваша_база -f 07_load_generated.sql';
    RAISE NOTICE 'а затем этот файл';
    RAISE NOTICE '';
    RAISE NOTICE 'Примеры запросов:';
    RAISE NOTICE '1. SELECT * FROM employee_details WHERE department_id = 1;';
    RAISE NOTICE '2. SELECT * FROM get_manager_subordinates(1);';
    RAISE NOTICE '3. SELECT * FROM department_salary_report;';
END $$;

-- Сброс контекста аудита
SELECT set_config('app.current_user_id', '', FALSE);
SELECT set_config('app.salary_change_reason', '', FALSE);