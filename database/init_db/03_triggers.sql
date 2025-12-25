
-- СОЗДАНИЕ ТРИГГЕРОВ ДЛЯ HRM-СИСТЕМЫ

-- 1. УНИВЕРСАЛЬНАЯ ФУНКЦИЯ ДЛЯ ОБНОВЛЕНИЯ ПОЛЯ updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. ТРИГГЕРЫ ДЛЯ ОБНОВЛЕНИЯ ВРЕМЕНИ В ТАБЛИЦАХ
CREATE TRIGGER update_employees_updated_at 
    BEFORE UPDATE ON employees 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_departments_updated_at 
    BEFORE UPDATE ON departments 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- 3. ТРИГГЕР ДЛЯ АВТОМАТИЧЕСКОГО ОБНОВЛЕНИЯ МЕНЕДЖЕРА ОТДЕЛА
-- Когда сотрудник становится руководителем отдела
CREATE OR REPLACE FUNCTION update_department_manager()
RETURNS TRIGGER AS $$
BEGIN
    -- Если сотруднику присвоена должность руководителя отдела (position_level = 'manager' или 'director')
    -- и у него есть department_id, обновляем менеджера в таблице departments
    IF NEW.position_id IN (
        SELECT position_id FROM positions 
        WHERE position_level IN ('manager', 'director', 'executive')
    ) THEN
        UPDATE departments 
        SET manager_id = NEW.employee_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE department_id = NEW.department_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_department_manager_on_position_change
    AFTER INSERT OR UPDATE OF position_id, department_id ON employees
    FOR EACH ROW
    WHEN (NEW.position_id IS DISTINCT FROM OLD.position_id OR NEW.department_id IS DISTINCT FROM OLD.department_id)
    EXECUTE FUNCTION update_department_manager();

-- 4. ТРИГГЕР ДЛЯ АВТОМАТИЧЕСКОЙ ЗАПИСИ В ИСТОРИЮ ЗАРПЛАТ
CREATE OR REPLACE FUNCTION log_salary_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Если изменилась зарплата, записываем в историю
    IF NEW.salary IS DISTINCT FROM OLD.salary THEN
        INSERT INTO salary_history (
            employee_id, 
            old_salary, 
            new_salary, 
            change_date, 
            change_reason,
            changed_by
        )
        VALUES (
            NEW.employee_id,
            COALESCE(OLD.salary, 0),
            NEW.salary,
            CURRENT_DATE,
            COALESCE(
                current_setting('app.salary_change_reason', TRUE),
                'salary_adjustment'
            ),
            COALESCE(
                NULLIF(current_setting('app.current_user_id', TRUE), '')::INT,
                1  -- системный пользователь по умолчанию
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER track_salary_changes
    AFTER UPDATE OF salary ON employees
    FOR EACH ROW
    WHEN (NEW.salary IS DISTINCT FROM OLD.salary)
    EXECUTE FUNCTION log_salary_change();

-- 5. ТРИГГЕР ДЛЯ ПРОВЕРКИ ИЕРАРХИИ ПОДЧИНЕНИЯ (НЕТ ЦИКЛИЧЕСКИХ СВЯЗЕЙ)
CREATE OR REPLACE FUNCTION check_management_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    current_id INT := NEW.employee_id;
    manager_id INT := NEW.manager_id;
BEGIN
    -- Проверка на цикл: сотрудник не может быть своим же менеджером
    IF NEW.manager_id = NEW.employee_id THEN
        RAISE EXCEPTION 'Сотрудник не может быть своим собственным менеджером';
    END IF;
    
    -- Проверка на циклические связи (сотрудник не может быть руководителем своего руководителя)
    WHILE manager_id IS NOT NULL LOOP
        IF manager_id = current_id THEN
            RAISE EXCEPTION 'Обнаружена циклическая ссылка в иерархии подчинения';
        END IF;
        
        -- Переходим на уровень выше
        SELECT e.manager_id INTO manager_id
        FROM employees e
        WHERE e.employee_id = manager_id;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_management_hierarchy
    BEFORE INSERT OR UPDATE OF manager_id ON employees
    FOR EACH ROW
    EXECUTE FUNCTION check_management_hierarchy();

-- 6. ТРИГГЕР ДЛЯ АВТОМАТИЧЕСКОГО РАСЧЕТА ДНЕЙ ОТПУСКА
CREATE OR REPLACE FUNCTION calculate_vacation_days()
RETURNS TRIGGER AS $$
BEGIN
    -- Автоматически рассчитываем количество дней отпуска
    IF NEW.start_date IS NOT NULL AND NEW.end_date IS NOT NULL THEN
        NEW.days_count = NEW.end_date - NEW.start_date + 1;
        
        -- Проверка: отпуск не может быть длиннее 60 дней
        IF NEW.days_count > 60 THEN
            RAISE EXCEPTION 'Продолжительность отпуска не может превышать 60 дней';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_vacation_days
    BEFORE INSERT OR UPDATE OF start_date, end_date ON vacations
    FOR EACH ROW
    EXECUTE FUNCTION calculate_vacation_days();

-- 7. ТРИГГЕР ДЛЯ АУДИТА ИЗМЕНЕНИЙ В ТАБЛИЦЕ СОТРУДНИКОВ
CREATE OR REPLACE FUNCTION audit_employee_changes()
RETURNS TRIGGER AS $$
DECLARE
    changed_by_user INT;
BEGIN
    -- Получаем ID пользователя, внесшего изменения
    changed_by_user := COALESCE(
        NULLIF(current_setting('app.current_user_id', TRUE), '')::INT,
        1  -- системный пользователь по умолчанию
    );
    
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (
            table_name, 
            record_id, 
            operation_type, 
            new_values, 
            changed_by,
            changed_at
        )
        VALUES (
            'employees', 
            NEW.employee_id, 
            'INSERT', 
            jsonb_build_object(
                'first_name', NEW.first_name,
                'last_name', NEW.last_name,
                'email', NEW.email,
                'salary', NEW.salary,
                'department_id', NEW.department_id,
                'position_id', NEW.position_id,
                'manager_id', NEW.manager_id
            ),
            changed_by_user,
            CURRENT_TIMESTAMP
        );
        
    ELSIF TG_OP = 'UPDATE' THEN
        -- Логируем только измененные поля
        INSERT INTO audit_log (
            table_name, 
            record_id, 
            operation_type, 
            old_values, 
            new_values,
            changed_by,
            changed_at
        )
        VALUES (
            'employees', 
            NEW.employee_id, 
            'UPDATE', 
            jsonb_build_object(
                'first_name', OLD.first_name,
                'last_name', OLD.last_name,
                'email', OLD.email,
                'salary', OLD.salary,
                'department_id', OLD.department_id,
                'position_id', OLD.position_id,
                'manager_id', OLD.manager_id
            ),
            jsonb_build_object(
                'first_name', NEW.first_name,
                'last_name', NEW.last_name,
                'email', NEW.email,
                'salary', NEW.salary,
                'department_id', NEW.department_id,
                'position_id', NEW.position_id,
                'manager_id', NEW.manager_id
            ),
            changed_by_user,
            CURRENT_TIMESTAMP
        );
        
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (
            table_name, 
            record_id, 
            operation_type, 
            old_values,
            changed_by,
            changed_at
        )
        VALUES (
            'employees', 
            OLD.employee_id, 
            'DELETE', 
            jsonb_build_object(
                'first_name', OLD.first_name,
                'last_name', OLD.last_name,
                'email', OLD.email,
                'salary', OLD.salary,
                'department_id', OLD.department_id,
                'position_id', OLD.position_id,
                'manager_id', OLD.manager_id
            ),
            changed_by_user,
            CURRENT_TIMESTAMP
        );
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_employees_changes
    AFTER INSERT OR UPDATE OR DELETE ON employees
    FOR EACH ROW
    EXECUTE FUNCTION audit_employee_changes();

-- 8. ТРИГГЕР ДЛЯ ОБНОВЛЕНИЯ СТАТУСА ПРОЕКТА ПОСЛЕ ИЗМЕНЕНИЙ
CREATE OR REPLACE FUNCTION update_project_status_auto()
RETURNS TRIGGER AS $$
BEGIN
    -- Если проект завершен (end_date прошел), автоматически меняем статус
    IF NEW.end_date IS NOT NULL AND NEW.end_date < CURRENT_DATE THEN
        NEW.status = 'completed';
    -- Если началась дата начала проекта
    ELSIF NEW.start_date <= CURRENT_DATE AND NEW.status = 'planning' THEN
        NEW.status = 'active';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER auto_update_project_status
    BEFORE INSERT OR UPDATE OF start_date, end_date ON projects
    FOR EACH ROW
    EXECUTE FUNCTION update_project_status_auto();

-- 9. ТРИГГЕР ДЛЯ ПРОВЕРКИ БЮДЖЕТА ОТДЕЛА ПРИ НАЙМЕ СОТРУДНИКА
CREATE OR REPLACE FUNCTION check_department_budget()
RETURNS TRIGGER AS $$
DECLARE
    dept_budget DECIMAL(15, 2);
    current_salary_sum DECIMAL(15, 2);
    new_salary_sum DECIMAL(15, 2);
BEGIN
    -- Получаем бюджет отдела
    SELECT budget INTO dept_budget
    FROM departments
    WHERE department_id = NEW.department_id;
    
    -- Сумма зарплат активных сотрудников в отделе
    SELECT COALESCE(SUM(salary), 0) INTO current_salary_sum
    FROM employees
    WHERE department_id = NEW.department_id 
      AND is_active = TRUE
      AND employee_id != COALESCE(NEW.employee_id, 0);  -- исключаем текущего сотрудника для UPDATE
    
    -- Новая сумма с учетом нового сотрудника
    new_salary_sum := current_salary_sum + NEW.salary;
    
    -- Проверяем, не превышает ли фонд оплаты труда 70% бюджета отдела
    -- (оставляем 30% на оборудование, обучение и другие расходы)
    IF new_salary_sum > (dept_budget * 0.7) THEN
        RAISE EXCEPTION 
            'Превышен бюджет отдела. Фонд оплаты труда (%.2f) превышает 70%% бюджета отдела (%.2f)',
            new_salary_sum, dept_budget * 0.7;
    END IF;
    
    RETURN NEW;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NEW;  -- если отдел не найден, пропускаем проверку
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_department_budget_on_hire
    BEFORE INSERT OR UPDATE OF salary, department_id ON employees
    FOR EACH ROW
    EXECUTE FUNCTION check_department_budget();

-- 10. ТРИГГЕР ДЛЯ ОБНОВЛЕНИЯ СРЕДНЕЙ ЗАРПЛАТЫ ПО ОТДЕЛУ
CREATE OR REPLACE FUNCTION update_department_salary_stats()
RETURNS TRIGGER AS $$
BEGIN
    -- Пересчитываем среднюю зарплату по отделу при изменениях
    -- Это можно вынести в отдельную материализованную таблицу или представление
    -- В данном случае просто логируем для демонстрации
    
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        -- Можно добавить вычисление статистик в отдельную таблицу
        -- Для простоты демонстрации просто записываем в аудит
        INSERT INTO audit_log (
            table_name,
            record_id,
            operation_type,
            new_values,
            changed_at
        )
        VALUES (
            'department_salary_stats',
            NEW.department_id,
            'CALCULATE',
            jsonb_build_object(
                'employee_id', NEW.employee_id,
                'salary', NEW.salary,
                'operation', 'salary_update_triggered_recalc'
            ),
            CURRENT_TIMESTAMP
        );
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER recalc_department_stats_on_salary_change
    AFTER INSERT OR UPDATE OF salary, department_id ON employees
    FOR EACH ROW
    EXECUTE FUNCTION update_department_salary_stats();


-- ФУНКЦИЯ ДЛЯ УСТАНОВКИ КОНТЕКСТА ПОЛЬЗОВАТЕЛЯ (для триггеров аудита)

CREATE OR REPLACE FUNCTION set_audit_context(user_id INT, change_reason TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    -- Устанавливаем ID пользователя, вносящего изменения
    PERFORM set_config('app.current_user_id', user_id::TEXT, FALSE);
    
    -- Устанавливаем причину изменения (например, для зарплаты)
    IF change_reason IS NOT NULL THEN
        PERFORM set_config('app.salary_change_reason', change_reason, FALSE);
    END IF;
END;
$$ LANGUAGE plpgsql;


-- УВЕДОМЛЕНИЕ О СОЗДАНИИ ТРИГГЕРОВ

DO $$
BEGIN
    RAISE NOTICE 'Создано 10 триггеров для HRM-системы:';
    RAISE NOTICE '1. update_updated_at_column - обновление времени изменения';
    RAISE NOTICE '2. update_department_manager - автоматическое назначение менеджера отдела';
    RAISE NOTICE '3. log_salary_change - аудит изменений зарплаты';
    RAISE NOTICE '4. check_management_hierarchy - проверка иерархии подчинения';
    RAISE NOTICE '5. calculate_vacation_days - автоматический расчет дней отпуска';
    RAISE NOTICE '6. audit_employee_changes - полный аудит изменений сотрудников';
    RAISE NOTICE '7. update_project_status_auto - автоматическое обновление статуса проектов';
    RAISE NOTICE '8. check_department_budget - проверка бюджета отдела при найме';
    RAISE NOTICE '9. update_department_salary_stats - обновление статистик по отделам';
    RAISE NOTICE '10. set_audit_context - вспомогательная функция для аудита';
END $$;