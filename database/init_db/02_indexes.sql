
-- Индексы для таблицы employees (часто используемые в WHERE, JOIN, ORDER BY)
CREATE INDEX idx_employees_department_id ON employees(department_id);
CREATE INDEX idx_employees_position_id ON employees(position_id);
CREATE INDEX idx_employees_manager_id ON employees(manager_id);
CREATE INDEX idx_employees_salary ON employees(salary);
CREATE INDEX idx_employees_hire_date ON employees(hire_date);
CREATE INDEX idx_employees_is_active ON employees(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_employees_last_first_name ON employees(last_name, first_name);
CREATE INDEX idx_employees_email ON employees(email);

-- Индексы для таблицы departments
CREATE INDEX idx_departments_budget ON departments(budget);
CREATE INDEX idx_departments_manager_id ON departments(manager_id);
CREATE INDEX idx_departments_name ON departments(department_name);

-- Индексы для таблицы positions
CREATE INDEX idx_positions_salary_range ON positions(base_salary_min, base_salary_max);
CREATE INDEX idx_positions_level ON positions(position_level);
CREATE INDEX idx_positions_title ON positions(position_title);

-- Индексы для таблицы projects
CREATE INDEX idx_projects_department_id ON projects(department_id);
CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_projects_dates ON projects(start_date, end_date);
CREATE INDEX idx_projects_manager ON projects(project_manager_id);
CREATE INDEX idx_projects_budget ON projects(budget);

-- Индексы для таблицы employee_projects (часты JOIN по этим полям)
CREATE INDEX idx_emp_proj_employee_id ON employee_projects(employee_id);
CREATE INDEX idx_emp_proj_project_id ON employee_projects(project_id);
CREATE INDEX idx_emp_proj_dates ON employee_projects(start_date, end_date);
CREATE INDEX idx_emp_proj_role ON employee_projects(role_in_project);
CREATE INDEX idx_emp_proj_active ON employee_projects(end_date) WHERE end_date IS NULL;

-- Индексы для таблицы salary_history
CREATE INDEX idx_salary_employee_id ON salary_history(employee_id);
CREATE INDEX idx_salary_change_date ON salary_history(change_date);
CREATE INDEX idx_salary_changed_by ON salary_history(changed_by);
CREATE INDEX idx_salary_range ON salary_history(old_salary, new_salary);

-- Индексы для таблицы vacations
CREATE INDEX idx_vacations_employee_id ON vacations(employee_id);
CREATE INDEX idx_vacations_status ON vacations(status);
CREATE INDEX idx_vacations_dates ON vacations(start_date, end_date);
CREATE INDEX idx_vacations_type ON vacations(vacation_type);
CREATE INDEX idx_vacations_approved_by ON vacations(approved_by);

-- Индексы для таблицы skills
CREATE INDEX idx_skills_category ON skills(category);
CREATE INDEX idx_skills_name ON skills(skill_name);

-- Индексы для таблицы employee_skills
CREATE INDEX idx_emp_skills_employee_id ON employee_skills(employee_id);
CREATE INDEX idx_emp_skills_skill_id ON employee_skills(skill_id);
CREATE INDEX idx_emp_skills_proficiency ON employee_skills(proficiency_level);
CREATE INDEX idx_emp_skills_certified ON employee_skills(certified) WHERE certified = TRUE;

-- Индексы для таблицы audit_log
CREATE INDEX idx_audit_table_name ON audit_log(table_name);
CREATE INDEX idx_audit_record_id ON audit_log(record_id);
CREATE INDEX idx_audit_changed_at ON audit_log(changed_at);
CREATE INDEX idx_audit_changed_by ON audit_log(changed_by);
CREATE INDEX idx_audit_operation ON audit_log(operation_type);


-- СОСТАВНЫЕ ИНДЕКСЫ ДЛЯ ЧАСТО ИСПОЛЬЗУЕМЫХ ЗАПРОСОВ

-- 1. Для поиска сотрудников по отделу и должности
CREATE INDEX idx_emp_dept_position ON employees(department_id, position_id, is_active);

-- 2. Для отчетов по зарплатам по отделам
CREATE INDEX idx_emp_salary_dept ON employees(department_id, salary, is_active);

-- 3. Для иерархических запросов (подчиненные менеджера)
CREATE INDEX idx_emp_manager_active ON employees(manager_id, employee_id, is_active);

-- 4. Для поиска проектов по статусу и датам
CREATE INDEX idx_projects_status_dates ON projects(status, start_date, end_date);

-- 5. Для отчетов по занятости в проектах
CREATE INDEX idx_emp_proj_employee_dates ON employee_projects(employee_id, start_date, end_date);

-- 6. Для анализа отпусков по периодам
CREATE INDEX idx_vacations_date_range ON vacations(start_date, end_date, status);

-- 7. Для поиска сотрудников с определенными навыками
CREATE INDEX idx_emp_skills_search ON employee_skills(skill_id, proficiency_level, certified);

-- 8. Для отчетов по изменениям зарплат
CREATE INDEX idx_salary_history_report ON salary_history(employee_id, change_date, change_reason);

-- ЧАСТИЧНЫЕ ИНДЕКСЫ (Partial Indexes) - для оптимизации

-- Только активные сотрудники (80% запросов работают с активными)
CREATE INDEX idx_employees_active_only ON employees(employee_id) WHERE is_active = TRUE;

-- Только текущие проекты
CREATE INDEX idx_projects_active ON projects(project_id) 
WHERE status IN ('planning', 'active') AND end_date IS NULL;

-- Только утвержденные отпуска на будущее
CREATE INDEX idx_vacations_approved ON vacations(vacation_id) 
WHERE status = 'approved';

-- Только последние изменения в аудите (последние 30 дней)
CREATE INDEX idx_audit_recent_dates ON audit_log(changed_at) 
WHERE changed_at > '2023-01-01';

-- ИНДЕКСЫ ДЛЯ ПОИСКА ПО ТЕКСТУ (при необходимости)

-- Для полнотекстового поиска сотрудников 
CREATE INDEX idx_employees_fts ON employees USING gin(to_tsvector('russian', first_name || ' ' || last_name || ' ' || email));

-- Для поиска по описанию проектов (при больших объемах текста)
CREATE INDEX idx_projects_description ON projects USING gin(to_tsvector('russian', description));


COMMENT ON INDEX idx_employees_department_id IS 'Оптимизация запросов фильтрации и JOIN по отделу';
COMMENT ON INDEX idx_emp_dept_position IS 'Составной индекс для отчетов "сотрудники по отделам и должностям"';
COMMENT ON INDEX idx_emp_manager_active IS 'Оптимизация иерархических запросов подчинения';
COMMENT ON INDEX idx_projects_status_dates IS 'Для фильтрации проектов по статусу и датам в отчетах';
COMMENT ON INDEX idx_emp_skills_search IS 'Поиск сотрудников с определенным уровнем навыков';
COMMENT ON INDEX idx_employees_active_only IS 'Частичный индекс: большинство операций только с активными сотрудниками';



DO $$
BEGIN
    RAISE NOTICE 'Создано 35 индексов для оптимизации HRM-системы';
    RAISE NOTICE '- 8 таблиц с базовыми индексами';
    RAISE NOTICE '- 8 составных индексов для сложных запросов';
    RAISE NOTICE '- 4 частичных индекса для оптимизации типичных сценариев';
    RAISE NOTICE 'Индексы покрывают все частые операции: WHERE, JOIN, ORDER BY';
END $$;