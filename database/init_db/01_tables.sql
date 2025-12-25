-- СОЗДАНИЕ ТАБЛИЦ ДЛЯ СИСТЕМЫ УПРАВЛЕНИЯ ПЕРСОНАЛОМ

-- Удаление существующих таблиц (для чистого запуска) в правильном порядке
DROP TABLE IF EXISTS employee_projects CASCADE;
DROP TABLE IF EXISTS employee_skills CASCADE;
DROP TABLE IF EXISTS salary_history CASCADE;
DROP TABLE IF EXISTS vacations CASCADE;
DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS skills CASCADE;
DROP TABLE IF EXISTS positions CASCADE;
DROP TABLE IF EXISTS departments CASCADE;

-- 1. ТАБЛИЦА ОТДЕЛОВ (DEPARTMENTS)
CREATE TABLE departments (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(255) UNIQUE NOT NULL,
    budget DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    manager_id INT NULL,
    location VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_budget_positive CHECK (budget >= 0)
);

-- 2. ТАБЛИЦА ДОЛЖНОСТЕЙ (POSITIONS)
CREATE TABLE positions (
    position_id SERIAL PRIMARY KEY,
    position_title VARCHAR(255) UNIQUE NOT NULL,
    position_level VARCHAR(50) NOT NULL DEFAULT 'junior',
    base_salary_min DECIMAL(10, 2) NOT NULL,
    base_salary_max DECIMAL(10, 2) NOT NULL,
    description TEXT,
    requirements TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_salary_range CHECK (base_salary_max >= base_salary_min),
    CONSTRAINT chk_level_value CHECK (position_level IN ('trainee', 'junior', 'middle', 'senior', 'lead', 'manager', 'director', 'executive'))
);

-- 3. ТАБЛИЦА СОТРУДНИКОВ (EMPLOYEES)
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    hire_date DATE NOT NULL,
    salary DECIMAL(12, 2) NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL,
    manager_id INT NULL, -- САМОСВЯЗЬ: ссылка на руководителя в той же таблице
    address TEXT,
    birth_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Внешние ключи
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE RESTRICT,
    FOREIGN KEY (position_id) REFERENCES positions(position_id) ON DELETE RESTRICT,
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id) ON DELETE SET NULL,
    
    -- Проверки
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_salary_positive CHECK (salary >= 0),
    CONSTRAINT chk_hire_date CHECK (hire_date <= CURRENT_DATE),
    CONSTRAINT chk_birth_date CHECK (birth_date <= CURRENT_DATE - INTERVAL '18 years')
    
    -- Уникальность телефона будет реализована через частичный индекс ниже
);

-- 4. ТАБЛИЦА ПРОЕКТОВ (PROJECTS)
CREATE TABLE projects (
    project_id SERIAL PRIMARY KEY,
    project_name VARCHAR(255) NOT NULL,
    description TEXT,
    department_id INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL, -- NULL для текущих проектов
    budget DECIMAL(15, 2) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'planning',
    project_manager_id INT NOT NULL,
    
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE CASCADE,
    FOREIGN KEY (project_manager_id) REFERENCES employees(employee_id) ON DELETE RESTRICT,
    
    CONSTRAINT chk_budget_positive CHECK (budget >= 0),
    CONSTRAINT chk_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT chk_status_value CHECK (status IN ('planning', 'active', 'on_hold', 'completed', 'cancelled'))
);

-- 5. ТАБЛИЦА СВЯЗИ СОТРУДНИКОВ С ПРОЕКТАМИ (EMPLOYEE_PROJECTS)
CREATE TABLE employee_projects (
    employee_project_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    project_id INT NOT NULL,
    role_in_project VARCHAR(100) NOT NULL,
    participation_percentage INT NOT NULL DEFAULT 100, -- процент занятости в проекте
    start_date DATE NOT NULL,
    end_date DATE NULL,
    hourly_rate DECIMAL(10, 2), -- ставка для проекта (может отличаться от оклада)
    
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
    
    CONSTRAINT chk_percentage CHECK (participation_percentage >= 0 AND participation_percentage <= 100),
    CONSTRAINT chk_hourly_rate CHECK (hourly_rate IS NULL OR hourly_rate >= 0),
    CONSTRAINT chk_dates_project CHECK (end_date IS NULL OR end_date >= start_date)
    -- Уникальность для активных назначений будет реализована через частичный индекс ниже
);

-- 6. ТАБЛИЦА ИСТОРИИ ЗАРПЛАТ (SALARY_HISTORY)
CREATE TABLE salary_history (
    salary_change_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    old_salary DECIMAL(12, 2) NOT NULL,
    new_salary DECIMAL(12, 2) NOT NULL,
    change_date DATE NOT NULL,
    change_reason VARCHAR(255) NOT NULL,
    changed_by INT NOT NULL, -- кто изменил (обычно HR или руководитель)
    notes TEXT,
    
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (changed_by) REFERENCES employees(employee_id) ON DELETE RESTRICT,
    
    CONSTRAINT chk_salary_increase CHECK (new_salary >= old_salary), -- запрещаем уменьшение через эту таблицу
    CONSTRAINT chk_change_date CHECK (change_date <= CURRENT_DATE)
);

-- 7. ТАБЛИЦА ОТПУСКОВ (VACATIONS)
CREATE TABLE vacations (
    vacation_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    vacation_type VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    days_count INT GENERATED ALWAYS AS (end_date - start_date + 1) STORED,
    status VARCHAR(50) NOT NULL DEFAULT 'requested',
    approved_by INT NULL,
    notes TEXT,
    
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (approved_by) REFERENCES employees(employee_id) ON DELETE SET NULL,
    
    CONSTRAINT chk_dates_vacation CHECK (end_date >= start_date),
    CONSTRAINT chk_vacation_type CHECK (vacation_type IN ('annual', 'sick', 'maternity', 'unpaid', 'other')),
    CONSTRAINT chk_status CHECK (status IN ('requested', 'approved', 'rejected', 'taken', 'cancelled'))
);

-- 8. ТАБЛИЦА НАВЫКОВ (SKILLS)
CREATE TABLE skills (
    skill_id SERIAL PRIMARY KEY,
    skill_name VARCHAR(255) UNIQUE NOT NULL,
    category VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 9. ТАБЛИЦА СВЯЗИ СОТРУДНИКОВ С НАВЫКАМИ (EMPLOYEE_SKILLS)
CREATE TABLE employee_skills (
    employee_skill_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    skill_id INT NOT NULL,
    proficiency_level VARCHAR(50) NOT NULL DEFAULT 'intermediate',
    certified BOOLEAN DEFAULT FALSE,
    certification_date DATE NULL,
    notes TEXT,
    
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (skill_id) REFERENCES skills(skill_id) ON DELETE CASCADE,
    
    CONSTRAINT chk_proficiency_level CHECK (proficiency_level IN ('beginner', 'intermediate', 'advanced', 'expert')),
    CONSTRAINT chk_certification_date CHECK (certification_date IS NULL OR certification_date <= CURRENT_DATE),
    CONSTRAINT uniq_employee_skill UNIQUE (employee_id, skill_id)
);

-- 10. ТАБЛИЦА АУДИТА (AUDIT_LOG)
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id INT NOT NULL,
    operation_type VARCHAR(10) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by INT, 
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (changed_by) REFERENCES employees(employee_id) ON DELETE SET NULL,
    
    CONSTRAINT chk_operation_type CHECK (operation_type IN ('INSERT', 'UPDATE', 'DELETE'))
);

