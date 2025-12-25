-- СОЗДАНИЕ ПРЕДСТАВЛЕНИЙ (VIEWS) ДЛЯ HRM-СИСТЕМЫ

-- 1. ДЕТАЛЬНАЯ ИНФОРМАЦИЯ О СОТРУДНИКАХ С ИЕРАРХИЕЙ
CREATE OR REPLACE VIEW employee_details AS
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    e.email,
    e.phone,
    e.hire_date,
    e.salary,
    e.is_active,
    
    -- Информация об отделе
    d.department_name,
    d.budget as department_budget,
    
    -- Информация о должности
    p.position_title,
    p.position_level,
    p.base_salary_min,
    p.base_salary_max,
    
    -- Информация о руководителе
    m.first_name as manager_first_name,
    m.last_name as manager_last_name,
    m.email as manager_email,
    
    -- Расчетные поля
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.hire_date)) as years_in_company,
    CASE 
        WHEN e.salary < p.base_salary_min THEN 'Ниже вилки'
        WHEN e.salary > p.base_salary_max THEN 'Выше вилки'
        ELSE 'В пределах вилки'
    END as salary_benchmark,
    
    -- Статус активности
    CASE 
        WHEN e.is_active = TRUE THEN 'Активен'
        ELSE 'Не активен'
    END as activity_status
    
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id
LEFT JOIN positions p ON e.position_id = p.position_id
LEFT JOIN employees m ON e.manager_id = m.employee_id
ORDER BY d.department_name, p.position_level DESC, e.last_name;

-- 2. ОТЧЕТ ПО ЗАРПЛАТАМ ПО ОТДЕЛАМ (МЕСЯЧНЫЙ)
CREATE OR REPLACE VIEW department_salary_report AS
SELECT 
    d.department_id,
    d.department_name,
    d.budget,
    
    -- Статистика по сотрудникам
    COUNT(e.employee_id) as total_employees,
    COUNT(e.employee_id) FILTER (WHERE e.is_active = TRUE) as active_employees,
    COUNT(e.employee_id) FILTER (WHERE e.is_active = FALSE) as inactive_employees,
    
    -- Статистика по зарплатам
    COALESCE(SUM(e.salary) FILTER (WHERE e.is_active = TRUE), 0) as total_salary_fund,
    COALESCE(AVG(e.salary) FILTER (WHERE e.is_active = TRUE), 0) as avg_salary,
    COALESCE(MIN(e.salary) FILTER (WHERE e.is_active = TRUE), 0) as min_salary,
    COALESCE(MAX(e.salary) FILTER (WHERE e.is_active = TRUE), 0) as max_salary,
    
    -- Анализ бюджета
    ROUND(
        COALESCE(SUM(e.salary) FILTER (WHERE e.is_active = TRUE), 0) * 100.0 / NULLIF(d.budget, 0), 
        2
    ) as salary_to_budget_percentage,
    
    -- Выход за вилки зарплат
    COUNT(e.employee_id) FILTER (
        WHERE e.is_active = TRUE 
        AND e.salary < p.base_salary_min
    ) as below_min_salary,
    COUNT(e.employee_id) FILTER (
        WHERE e.is_active = TRUE 
        AND e.salary > p.base_salary_max
    ) as above_max_salary
    
FROM departments d
LEFT JOIN employees e ON d.department_id = e.department_id
LEFT JOIN positions p ON e.position_id = p.position_id
GROUP BY d.department_id, d.department_name, d.budget
ORDER BY total_salary_fund DESC;

-- 3. ИЕРАРХИЯ ПОДЧИНЕНИЯ (РЕКУРСИВНОЕ ПРЕДСТАВЛЕНИЕ)
CREATE OR REPLACE VIEW employee_hierarchy AS
WITH RECURSIVE employee_tree AS (
    -- Начальные строки: топ-менеджеры (те, у кого нет менеджера)
    SELECT 
        employee_id,
        first_name,
        last_name,
        position_id,
        department_id,
        manager_id,
        1 as level,
        first_name || ' ' || last_name as path
    FROM employees
    WHERE manager_id IS NULL AND is_active = TRUE
    
    UNION ALL
    
    -- Рекурсивная часть: подчиненные
    SELECT 
        e.employee_id,
        e.first_name,
        e.last_name,
        e.position_id,
        e.department_id,
        e.manager_id,
        et.level + 1,
        et.path || ' → ' || e.first_name || ' ' || e.last_name
    FROM employees e
    INNER JOIN employee_tree et ON e.manager_id = et.employee_id
    WHERE e.is_active = TRUE
)
SELECT 
    et.employee_id,
    et.first_name,
    et.last_name,
    p.position_title,
    d.department_name,
    et.manager_id,
    m.first_name || ' ' || m.last_name as manager_name,
    et.level,
    et.path as reporting_path,
    
    -- Форматирование отступов для визуального отображения иерархии
    REPEAT('  ', et.level - 1) || et.first_name || ' ' || et.last_name as indented_name
    
FROM employee_tree et
LEFT JOIN positions p ON et.position_id = p.position_id
LEFT JOIN departments d ON et.department_id = d.department_id
LEFT JOIN employees m ON et.manager_id = m.employee_id
ORDER BY et.path;

-- 4. ОТЧЕТ ПО ПРОЕКТАМ С РАСПРЕДЕЛЕНИЕМ РЕСУРСОВ
CREATE OR REPLACE VIEW project_resource_report AS
SELECT 
    p.project_id,
    p.project_name,
    p.start_date,
    p.end_date,
    p.budget,
    p.status,
    
    -- Информация об отделе
    d.department_name,
    
    -- Руководитель проекта
    pm.first_name || ' ' || pm.last_name as project_manager,
    pm.email as project_manager_email,
    
    -- Статистика по участникам
    COUNT(DISTINCT ep.employee_id) as total_team_members,
    COUNT(DISTINCT ep.employee_id) FILTER (
        WHERE ep.end_date IS NULL OR ep.end_date >= CURRENT_DATE
    ) as current_team_members,
    
    -- Анализ загрузки
    ROUND(AVG(ep.participation_percentage), 1) as avg_participation_percentage,
    SUM(ep.participation_percentage) as total_participation_percentage,
    
    -- Расчетная стоимость человеко-часов
    COALESCE(SUM(
        CASE 
            WHEN ep.hourly_rate IS NOT NULL THEN ep.hourly_rate * 160 * ep.participation_percentage / 100
            ELSE e.salary / 12 * ep.participation_percentage / 100
        END
    ), 0) as estimated_monthly_cost,
    
    -- Прогресс проекта (если есть дата окончания)
    CASE 
        WHEN p.end_date IS NOT NULL AND p.start_date IS NOT NULL THEN
            ROUND(
                GREATEST(0, LEAST(100, 
                    (CURRENT_DATE - p.start_date)::NUMERIC / 
                    NULLIF((p.end_date - p.start_date)::NUMERIC, 0) * 100
                )), 
                1
            )
        ELSE NULL
    END as progress_percentage,
    
    -- Статус проекта с учетом дат
    CASE 
        WHEN p.end_date < CURRENT_DATE THEN 'Просрочен'
        WHEN p.end_date < CURRENT_DATE + INTERVAL '7 days' THEN 'Срочный'
        WHEN p.status = 'active' THEN 'В работе'
        ELSE p.status
    END as project_status_detailed
    
FROM projects p
LEFT JOIN departments d ON p.department_id = d.department_id
LEFT JOIN employees pm ON p.project_manager_id = pm.employee_id
LEFT JOIN employee_projects ep ON p.project_id = ep.project_id
LEFT JOIN employees e ON ep.employee_id = e.employee_id
GROUP BY 
    p.project_id, p.project_name, p.start_date, p.end_date, p.budget, p.status,
    d.department_name, pm.first_name, pm.last_name, pm.email
ORDER BY 
    CASE p.status 
        WHEN 'active' THEN 1
        WHEN 'planning' THEN 2
        WHEN 'on_hold' THEN 3
        WHEN 'completed' THEN 4
        ELSE 5
    END,
    p.end_date ASC NULLS FIRST;

-- 5. АНАЛИТИКА НАВЫКОВ И КОМПЕТЕНЦИЙ
CREATE OR REPLACE VIEW skill_analytics AS
SELECT 
    s.skill_id,
    s.skill_name,
    s.category,
    
    -- Статистика по сотрудникам
    COUNT(DISTINCT es.employee_id) as employees_with_skill,
    COUNT(DISTINCT es.employee_id) FILTER (WHERE es.certified = TRUE) as certified_employees,
    
    -- Распределение по уровням владения
    COUNT(DISTINCT es.employee_id) FILTER (WHERE es.proficiency_level = 'beginner') as beginners,
    COUNT(DISTINCT es.employee_id) FILTER (WHERE es.proficiency_level = 'intermediate') as intermediate,
    COUNT(DISTINCT es.employee_id) FILTER (WHERE es.proficiency_level = 'advanced') as advanced,
    COUNT(DISTINCT es.employee_id) FILTER (WHERE es.proficiency_level = 'expert') as experts,
    
    -- Средняя зарплата по уровням навыка
    ROUND(AVG(e.salary) FILTER (WHERE es.proficiency_level = 'beginner'), 2) as avg_salary_beginner,
    ROUND(AVG(e.salary) FILTER (WHERE es.proficiency_level = 'intermediate'), 2) as avg_salary_intermediate,
    ROUND(AVG(e.salary) FILTER (WHERE es.proficiency_level = 'advanced'), 2) as avg_salary_advanced,
    ROUND(AVG(e.salary) FILTER (WHERE es.proficiency_level = 'expert'), 2) as avg_salary_expert,
    
    -- Распределение по отделам (топ-3 отдела с навыком)
    ARRAY_AGG(
        DISTINCT d.department_name
        ORDER BY COUNT(DISTINCT es.employee_id) OVER (PARTITION BY d.department_id) DESC
        LIMIT 3
    ) as top_departments
    
FROM skills s
LEFT JOIN employee_skills es ON s.skill_id = es.skill_id
LEFT JOIN employees e ON es.employee_id = e.employee_id AND e.is_active = TRUE
LEFT JOIN departments d ON e.department_id = d.department_id
GROUP BY s.skill_id, s.skill_name, s.category
ORDER BY employees_with_skill DESC, s.category, s.skill_name;

-- 6. ПЛАНИРОВАНИЕ ОТПУСКОВ (КАЛЕНДАРЬ)
CREATE OR REPLACE VIEW vacation_calendar AS
SELECT 
    v.vacation_id,
    v.start_date,
    v.end_date,
    v.days_count,
    v.vacation_type,
    v.status,
    
    -- Информация о сотруднике
    e.employee_id,
    e.first_name || ' ' || e.last_name as employee_name,
    e.email as employee_email,
    
    -- Информация об отделе и должности
    d.department_name,
    p.position_title,
    
    -- Утвердивший руководитель
    a.first_name || ' ' || a.last_name as approved_by_name,
    a.email as approved_by_email,
    
    -- Анализ сроков
    CASE 
        WHEN v.start_date > CURRENT_DATE THEN 'Запланирован'
        WHEN v.end_date < CURRENT_DATE THEN 'Завершен'
        ELSE 'Текущий'
    END as vacation_timeline,
    
    -- Предупреждения
    CASE 
        WHEN v.days_count > 30 THEN 'Длительный отпуск'
        WHEN v.end_date - CURRENT_DATE < 7 AND v.status = 'approved' THEN 'Скоро начало'
        ELSE 'Норма'
    END as vacation_alert
    
FROM vacations v
JOIN employees e ON v.employee_id = e.employee_id
LEFT JOIN departments d ON e.department_id = d.department_id
LEFT JOIN positions p ON e.position_id = p.position_id
LEFT JOIN employees a ON v.approved_by = a.employee_id
WHERE v.status IN ('approved', 'taken')
ORDER BY v.start_date, d.department_name, e.last_name;

-- 7. ОБЗОР СТАТИСТИКИ ИЗМЕНЕНИЙ ЗАРПЛАТ
CREATE OR REPLACE VIEW salary_change_analysis AS
SELECT 
    -- Группировка по месяцам
    DATE_TRUNC('month', sh.change_date) as change_month,
    TO_CHAR(DATE_TRUNC('month', sh.change_date), 'Month YYYY') as month_name,
    
    -- Статистика по изменениям
    COUNT(DISTINCT sh.employee_id) as employees_with_changes,
    COUNT(sh.salary_change_id) as total_changes,
    
    -- Анализ изменений
    ROUND(AVG((sh.new_salary - sh.old_salary) * 100.0 / sh.old_salary), 2) as avg_percentage_increase,
    ROUND(AVG(sh.new_salary - sh.old_salary), 2) as avg_amount_increase,
    SUM(sh.new_salary - sh.old_salary) as total_salary_increase,
    
    -- Причины изменений (топ-3)
    (SELECT ARRAY_AGG(DISTINCT change_reason ORDER BY COUNT(*) DESC LIMIT 3)
     FROM salary_history sh2 
     WHERE DATE_TRUNC('month', sh2.change_date) = DATE_TRUNC('month', sh.change_date)
     GROUP BY change_reason) as top_reasons,
    
    -- Отделы с наибольшим количеством изменений
    (SELECT ARRAY_AGG(DISTINCT d.department_name ORDER BY COUNT(*) DESC LIMIT 3)
     FROM salary_history sh2 
     JOIN employees e2 ON sh2.employee_id = e2.employee_id
     JOIN departments d ON e2.department_id = d.department_id
     WHERE DATE_TRUNC('month', sh2.change_date) = DATE_TRUNC('month', sh.change_date)
     GROUP BY d.department_name) as top_departments
    
FROM salary_history sh
GROUP BY DATE_TRUNC('month', sh.change_date)
ORDER BY change_month DESC;

-- ПРЕДСТАВЛЕНИЯ ДЛЯ АНАЛИТИКИ И ОТЧЕТОВ

-- 8. СВОДНЫЙ АНАЛИТИЧЕСКИЙ ОТЧЕТ
CREATE OR REPLACE VIEW hr_analytics_dashboard AS
SELECT 
    -- Общая статистика
    (SELECT COUNT(*) FROM employees WHERE is_active = TRUE) as total_active_employees,
    (SELECT COUNT(*) FROM departments) as total_departments,
    (SELECT COUNT(*) FROM projects WHERE status = 'active') as active_projects,
    (SELECT AVG(salary) FROM employees WHERE is_active = TRUE) as company_avg_salary,
    
    -- Статистика по найму
    (SELECT COUNT(*) FROM employees 
     WHERE EXTRACT(YEAR FROM hire_date) = EXTRACT(YEAR FROM CURRENT_DATE)) as hires_this_year,
    (SELECT COUNT(*) FROM employees 
     WHERE EXTRACT(MONTH FROM hire_date) = EXTRACT(MONTH FROM CURRENT_DATE)
       AND EXTRACT(YEAR FROM hire_date) = EXTRACT(YEAR FROM CURRENT_DATE)) as hires_this_month,
    
    -- Статистика по увольнениям
    (SELECT COUNT(*) FROM employees 
     WHERE is_active = FALSE 
       AND EXTRACT(YEAR FROM updated_at) = EXTRACT(YEAR FROM CURRENT_DATE)) as terminations_this_year,
    
    -- Отпуска
    (SELECT COUNT(*) FROM vacations 
     WHERE status = 'approved' 
       AND start_date <= CURRENT_DATE 
       AND end_date >= CURRENT_DATE) as employees_on_vacation_today,
    
    -- Бюджет
    (SELECT SUM(budget) FROM departments) as total_company_budget,
    (SELECT SUM(salary) FROM employees WHERE is_active = TRUE) as total_salary_fund,
    
    -- Расчет процента
    ROUND(
        (SELECT SUM(salary) FROM employees WHERE is_active = TRUE) * 100.0 / 
        NULLIF((SELECT SUM(budget) FROM departments), 0), 
        2
    ) as salary_to_budget_percentage_company;



DO $$
BEGIN
    RAISE NOTICE 'Создано 8 представлений для HRM-системы:';
    RAISE NOTICE '1. employee_details - детальная информация о сотрудниках с иерархией';
    RAISE NOTICE '2. department_salary_report - отчет по зарплатам по отделам';
    RAISE NOTICE '3. employee_hierarchy - рекурсивное представление иерархии подчинения';
    RAISE NOTICE '4. project_resource_report - отчет по проектам с распределением ресурсов';
    RAISE NOTICE '5. skill_analytics - аналитика навыков и компетенций';
    RAISE NOTICE '6. vacation_calendar - планирование и календарь отпусков';
    RAISE NOTICE '7. salary_change_analysis - анализ изменений зарплат';
    RAISE NOTICE '8. hr_analytics_dashboard - сводный аналитический отчет';
END $$;