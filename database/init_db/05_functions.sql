
-- СОЗДАНИЕ ФУНКЦИЙ ДЛЯ HRM-СИСТЕМЫ

-- 1. ФУНКЦИЯ: РАСЧЕТ ОБЩЕГО ФОНДА ЗАРПЛАТЫ ОТДЕЛА
CREATE OR REPLACE FUNCTION calculate_department_salary_fund(department_id_param INT)
RETURNS DECIMAL(15,2) AS $$
DECLARE
    total_fund DECIMAL(15,2);
BEGIN
    SELECT COALESCE(SUM(salary), 0)
    INTO total_fund
    FROM employees
    WHERE department_id = department_id_param
      AND is_active = TRUE;
    
    RETURN total_fund;
END;
$$ LANGUAGE plpgsql;

-- 2. ФУНКЦИЯ: ПРОВЕРКА БЮДЖЕТА ОТДЕЛА ПРИ НАЙМЕ
CREATE OR REPLACE FUNCTION check_department_budget_for_hire(
    department_id_param INT,
    proposed_salary DECIMAL(12,2)
)
RETURNS BOOLEAN AS $$
DECLARE
    department_budget DECIMAL(15,2);
    current_salary_fund DECIMAL(15,2);
    max_allowed_fund DECIMAL(15,2);
BEGIN
    -- Получаем бюджет отдела
    SELECT budget INTO department_budget
    FROM departments
    WHERE department_id = department_id_param;
    
    -- Рассчитываем текущий фонд зарплат
    SELECT calculate_department_salary_fund(department_id_param) 
    INTO current_salary_fund;
    
    -- Максимально допустимый фонд (70% бюджета)
    max_allowed_fund := department_budget * 0.7;
    
    -- Проверяем, не превысит ли новый фонд лимит
    RETURN (current_salary_fund + proposed_salary) <= max_allowed_fund;
END;
$$ LANGUAGE plpgsql;

-- 3. ФУНКЦИЯ: ПОВЫШЕНИЕ ЗАРПЛАТЫ ВСЕМ СОТРУДНИКАМ ОТДЕЛА (ВОПРОС ИЗ ЗАДАНИЯ)
CREATE OR REPLACE FUNCTION increase_department_salaries(
    department_id_param INT,
    increase_percentage DECIMAL(5,2)
)
RETURNS TABLE(
    employee_id INT,
    employee_name TEXT,
    old_salary DECIMAL(12,2),
    new_salary DECIMAL(12,2),
    increase_amount DECIMAL(12,2)
) AS $$
DECLARE
    change_reason_text TEXT;
BEGIN
    -- Проверка входных параметров
    IF increase_percentage <= 0 OR increase_percentage > 100 THEN
        RAISE EXCEPTION 'Процент повышения должен быть от 0.01 до 100';
    END IF;
    
    -- Устанавливаем причину изменения
    change_reason_text := format('Повышение зарплаты отделу %s на %s%%', 
                               department_id_param, increase_percentage);
    PERFORM set_config('app.salary_change_reason', change_reason_text, FALSE);
    
    -- Обновляем зарплаты и возвращаем результаты
    RETURN QUERY
    WITH updated_employees AS (
        UPDATE employees e
        SET salary = ROUND(e.salary * (1 + increase_percentage / 100), 2),
            updated_at = CURRENT_TIMESTAMP
        WHERE e.department_id = department_id_param
          AND e.is_active = TRUE
        RETURNING 
            e.employee_id,
            e.first_name || ' ' || e.last_name as employee_name,
            e.salary / (1 + increase_percentage / 100) as old_salary,
            e.salary as new_salary,
            e.salary - (e.salary / (1 + increase_percentage / 100)) as increase_amount
    )
    SELECT * FROM updated_employees
    ORDER BY increase_amount DESC;
END;
$$ LANGUAGE plpgsql;

-- 4. ФУНКЦИЯ: ПОЛУЧЕНИЕ ИЕРАРХИИ ПОДЧИНЕННЫХ ДЛЯ МЕНЕДЖЕРА (SELF JOIN АНАЛОГ)
CREATE OR REPLACE FUNCTION get_manager_subordinates(manager_id_param INT)
RETURNS TABLE(
    subordinate_id INT,
    subordinate_name TEXT,
    subordinate_position TEXT,
    hierarchy_level INT,
    reporting_path TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE subordinates_tree AS (
        -- Начальный уровень: прямые подчиненные
        SELECT 
            e.employee_id,
            e.first_name || ' ' || e.last_name as employee_name,
            p.position_title,
            1 as level,
            e.first_name || ' ' || e.last_name as path
        FROM employees e
        JOIN positions p ON e.position_id = p.position_id
        WHERE e.manager_id = manager_id_param
          AND e.is_active = TRUE
        
        UNION ALL
        
        -- Рекурсивная часть: подчиненные подчиненных
        SELECT 
            e.employee_id,
            e.first_name || ' ' || e.last_name as employee_name,
            p.position_title,
            st.level + 1,
            st.path || ' → ' || e.first_name || ' ' || e.last_name
        FROM employees e
        JOIN positions p ON e.position_id = p.position_id
        INNER JOIN subordinates_tree st ON e.manager_id = st.subordinate_id
        WHERE e.is_active = TRUE
    )
    SELECT 
        subordinate_id as employee_id,
        employee_name,
        position_title,
        level,
        path
    FROM subordinates_tree
    ORDER BY level, employee_name;
END;
$$ LANGUAGE plpgsql;

-- 5. ФУНКЦИЯ: РАСЧЕТ ОБЩЕЙ СТОИМОСТИ ПРОЕКТА
CREATE OR REPLACE FUNCTION calculate_project_cost(project_id_param INT)
RETURNS TABLE(
    cost_component VARCHAR(100),
    amount DECIMAL(15,2),
    percentage_of_budget DECIMAL(5,2)
) AS $$
DECLARE
    project_budget DECIMAL(15,2);
BEGIN
    -- Получаем бюджет проекта
    SELECT budget INTO project_budget
    FROM projects
    WHERE project_id = project_id_param;
    
    RETURN QUERY
    WITH cost_breakdown AS (
        -- Стоимость человеческих ресурсов
        SELECT 
            'human_resources' as component,
            COALESCE(SUM(
                CASE 
                    WHEN ep.hourly_rate IS NOT NULL THEN 
                        ep.hourly_rate * 160 * ep.participation_percentage / 100
                    ELSE 
                        e.salary / 12 * ep.participation_percentage / 100
                END
            ), 0) as amount
        FROM employee_projects ep
        JOIN employees e ON ep.employee_id = e.employee_id
        WHERE ep.project_id = project_id_param
          AND (ep.end_date IS NULL OR ep.end_date >= CURRENT_DATE)
          AND e.is_active = TRUE
        
        UNION ALL
        
        -- Другие расходы (остаток бюджета)
        SELECT 
            'other_expenses' as component,
            project_budget - COALESCE(SUM(
                CASE 
                    WHEN ep.hourly_rate IS NOT NULL THEN 
                        ep.hourly_rate * 160 * ep.participation_percentage / 100
                    ELSE 
                        e.salary / 12 * ep.participation_percentage / 100
                END
            ), 0) as amount
        FROM employee_projects ep
        JOIN employees e ON ep.employee_id = e.employee_id
        WHERE ep.project_id = project_id_param
          AND (ep.end_date IS NULL OR ep.end_date >= CURRENT_DATE)
          AND e.is_active = TRUE
    )
    SELECT 
        CASE 
            WHEN cb.component = 'human_resources' THEN 'Стоимость человеческих ресурсов'
            ELSE 'Прочие расходы'
        END as cost_component,
        cb.amount,
        ROUND(cb.amount * 100.0 / NULLIF(project_budget, 0), 2) as percentage_of_budget
    FROM cost_breakdown cb;
END;
$$ LANGUAGE plpgsql;

-- 6. ФУНКЦИЯ: АНАЛИЗ КАДРОВОЙ СТАТИСТИКИ ЗА ПЕРИОД
CREATE OR REPLACE FUNCTION analyze_hr_statistics(
    start_date DATE DEFAULT (CURRENT_DATE - INTERVAL '1 year'),
    end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    metric_name VARCHAR(100),
    metric_value NUMERIC,
    metric_unit VARCHAR(50),
    trend VARCHAR(20)
) AS $$
BEGIN
    RETURN QUERY
    WITH statistics AS (
        -- Количество новых сотрудников
        SELECT 
            'new_hires' as metric,
            COUNT(*) as value,
            'человек' as unit,
            CASE 
                WHEN COUNT(*) > LAG(COUNT(*), 1, 0) OVER (ORDER BY DATE_TRUNC('month', hire_date)) THEN '↑ рост'
                WHEN COUNT(*) < LAG(COUNT(*), 1, 0) OVER (ORDER BY DATE_TRUNC('month', hire_date)) THEN '↓ снижение'
                ELSE '→ стабильно'
            END as trend
        FROM employees
        WHERE hire_date BETWEEN start_date AND end_date
          AND is_active = TRUE
        GROUP BY DATE_TRUNC('month', hire_date)
        ORDER BY DATE_TRUNC('month', hire_date) DESC
        LIMIT 1
        
        UNION ALL
        
        -- Средняя зарплата
        SELECT 
            'avg_salary' as metric,
            ROUND(AVG(salary), 2) as value,
            'руб.' as unit,
            CASE 
                WHEN AVG(salary) > LAG(AVG(salary), 1, 0) OVER (ORDER BY DATE_TRUNC('month', hire_date)) THEN '↑ рост'
                WHEN AVG(salary) < LAG(AVG(salary), 1, 0) OVER (ORDER BY DATE_TRUNC('month', hire_date)) THEN '↓ снижение'
                ELSE '→ стабильно'
            END as trend
        FROM employees
        WHERE hire_date BETWEEN start_date AND end_date
          AND is_active = TRUE
        GROUP BY DATE_TRUNC('month', hire_date)
        ORDER BY DATE_TRUNC('month', hire_date) DESC
        LIMIT 1
        
        UNION ALL
        
        -- Текучесть кадров
        SELECT 
            'turnover_rate' as metric,
            ROUND(
                COUNT(*) FILTER (WHERE is_active = FALSE) * 100.0 / 
                NULLIF(COUNT(*), 0), 
                2
            ) as value,
            '%' as unit,
            CASE 
                WHEN ROUND(
                    COUNT(*) FILTER (WHERE is_active = FALSE) * 100.0 / 
                    NULLIF(COUNT(*), 0), 
                    2
                ) > 10 THEN '⚠ высокая'
                WHEN ROUND(
                    COUNT(*) FILTER (WHERE is_active = FALSE) * 100.0 / 
                    NULLIF(COUNT(*), 0), 
                    2
                ) < 5 THEN '✓ низкая'
                ELSE '→ средняя'
            END as trend
        FROM employees
        WHERE hire_date BETWEEN start_date AND end_date
          OR (is_active = FALSE AND updated_at BETWEEN start_date AND end_date)
        
        UNION ALL
        
        -- Заполненность отделов
        SELECT 
            'department_utilization' as metric,
            ROUND(
                AVG(
                    calculate_department_salary_fund(department_id) * 100.0 / 
                    NULLIF(budget, 0)
                ), 
                2
            ) as value,
            '%' as unit,
            CASE 
                WHEN AVG(
                    calculate_department_salary_fund(department_id) * 100.0 / 
                    NULLIF(budget, 0)
                ) > 65 THEN '⚠ перегружен'
                WHEN AVG(
                    calculate_department_salary_fund(department_id) * 100.0 / 
                    NULLIF(budget, 0)
                ) < 40 THEN '✓ недогружен'
                ELSE '→ оптимально'
            END as trend
        FROM departments d
        WHERE EXISTS (
            SELECT 1 FROM employees e 
            WHERE e.department_id = d.department_id 
              AND e.is_active = TRUE
        )
    )
    SELECT 
        CASE 
            WHEN s.metric = 'new_hires' THEN 'Новых сотрудников'
            WHEN s.metric = 'avg_salary' THEN 'Средняя зарплата'
            WHEN s.metric = 'turnover_rate' THEN 'Текучесть кадров'
            WHEN s.metric = 'department_utilization' THEN 'Использование бюджета отделов'
            ELSE s.metric
        END::VARCHAR(100) as metric_name,
        s.value,
        s.unit::VARCHAR(50),
        s.trend::VARCHAR(20)
    FROM statistics s;
END;
$$ LANGUAGE plpgsql;

-- 7. ФУНКЦИЯ: ПОИСК СОТРУДНИКОВ ПО КРИТЕРИЯМ (ГИБКИЙ ПОИСК)
CREATE OR REPLACE FUNCTION search_employees(
    department_filter INT DEFAULT NULL,
    position_filter INT DEFAULT NULL,
    min_salary DECIMAL(12,2) DEFAULT 0,
    max_salary DECIMAL(12,2) DEFAULT 10000000,
    skill_filter INT[] DEFAULT NULL,
    min_hire_date DATE DEFAULT '1900-01-01',
    max_hire_date DATE DEFAULT '9999-12-31'
)
RETURNS TABLE(
    employee_id INT,
    full_name TEXT,
    email VARCHAR(255),
    department_name VARCHAR(255),
    position_title VARCHAR(255),
    salary DECIMAL(12,2),
    hire_date DATE,
    skills TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.employee_id,
        e.first_name || ' ' || e.last_name as full_name,
        e.email,
        d.department_name,
        p.position_title,
        e.salary,
        e.hire_date,
        ARRAY_AGG(DISTINCT s.skill_name ORDER BY s.skill_name) as skills
    FROM employees e
    JOIN departments d ON e.department_id = d.department_id
    JOIN positions p ON e.position_id = p.position_id
    LEFT JOIN employee_skills es ON e.employee_id = es.employee_id
    LEFT JOIN skills s ON es.skill_id = s.skill_id
    WHERE e.is_active = TRUE
      AND (department_filter IS NULL OR e.department_id = department_filter)
      AND (position_filter IS NULL OR e.position_id = position_filter)
      AND e.salary BETWEEN min_salary AND max_salary
      AND e.hire_date BETWEEN min_hire_date AND max_hire_date
      AND (
        skill_filter IS NULL 
        OR es.skill_id = ANY(skill_filter)
        OR EXISTS (
            SELECT 1 FROM employee_skills es2 
            WHERE es2.employee_id = e.employee_id 
              AND es2.skill_id = ANY(skill_filter)
        )
      )
    GROUP BY 
        e.employee_id, e.first_name, e.last_name, e.email,
        d.department_name, p.position_title, e.salary, e.hire_date
    ORDER BY e.last_name, e.first_name;
END;
$$ LANGUAGE plpgsql;

-- 8. ФУНКЦИЯ: РАСЧЕТ ОТПУСКНЫХ ДНЕЙ СОТРУДНИКА
CREATE OR REPLACE FUNCTION calculate_employee_vacation_days(
    employee_id_param INT,
    year_filter INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)
)
RETURNS TABLE(
    vacation_type VARCHAR(50),
    days_taken INT,
    days_planned INT,
    days_remaining INT,
    total_entitled INT
) AS $$
BEGIN
    RETURN QUERY
    WITH vacation_summary AS (
        SELECT 
            v.vacation_type,
            -- Уже использованные дни (взят отпуск)
            SUM(CASE 
                WHEN v.status = 'taken' 
                AND EXTRACT(YEAR FROM v.start_date) = year_filter 
                THEN v.days_count 
                ELSE 0 
            END) as taken_days,
            -- Запланированные дни (утвержден, но еще не начался)
            SUM(CASE 
                WHEN v.status = 'approved' 
                AND v.start_date > CURRENT_DATE
                AND EXTRACT(YEAR FROM v.start_date) = year_filter 
                THEN v.days_count 
                ELSE 0 
            END) as planned_days,
            -- Всего положено дней (28 дней в год для примера)
            28 as entitled_days
        FROM vacations v
        WHERE v.employee_id = employee_id_param
          AND v.status IN ('taken', 'approved')
        GROUP BY v.vacation_type
    )
    SELECT 
        COALESCE(vs.vacation_type, 'annual') as vacation_type,
        COALESCE(vs.taken_days, 0) as days_taken,
        COALESCE(vs.planned_days, 0) as days_planned,
        COALESCE(vs.entitled_days, 28) - COALESCE(vs.taken_days, 0) - COALESCE(vs.planned_days, 0) as days_remaining,
        COALESCE(vs.entitled_days, 28) as total_entitled
    FROM vacation_summary vs
    UNION ALL
    SELECT 
        'total' as vacation_type,
        SUM(COALESCE(taken_days, 0)) as days_taken,
        SUM(COALESCE(planned_days, 0)) as days_planned,
        28 - SUM(COALESCE(taken_days, 0) + COALESCE(planned_days, 0)) as days_remaining,
        28 as total_entitled
    FROM vacation_summary vs;
END;
$$ LANGUAGE plpgsql;

-- УВЕДОМЛЕНИЕ О СОЗДАНИИ ФУНКЦИЙ

DO $$
BEGIN
    RAISE NOTICE 'Создано 8 функций для HRM-системы:';
    RAISE NOTICE '1. calculate_department_salary_fund - расчет общего фонда зарплаты отдела';
    RAISE NOTICE '2. check_department_budget_for_hire - проверка бюджета отдела при найме';
    RAISE NOTICE '3. increase_department_salaries - повышение зарплаты всем сотрудникам отдела (задание)';
    RAISE NOTICE '4. get_manager_subordinates - получение иерархии подчиненных (SELF JOIN)';
    RAISE NOTICE '5. calculate_project_cost - расчет общей стоимости проекта';
    RAISE NOTICE '6. analyze_hr_statistics - анализ кадровой статистики за период';
    RAISE NOTICE '7. search_employees - гибкий поиск сотрудников по критериям';
    RAISE NOTICE '8. calculate_employee_vacation_days - расчет отпускных дней сотрудника';
END $$;