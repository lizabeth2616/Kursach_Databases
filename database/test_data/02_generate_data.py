import random
from datetime import datetime, timedelta

def generate_hrm_data():
    with open('hrm_load_data.sql', 'w', encoding='utf-8') as f:
        # 1. Отделы (Departments): 10 записей
        f.write('-- Заполнение таблицы отделов\n')
        f.write('INSERT INTO departments (department_name, budget) VALUES\n')
        depts = [
            "('Руководство', 500000.00)",
            "('Отдел разработки', 300000.00)",
            "('Тестирование и QA', 200000.00)",
            "('Отдел продаж', 250000.00)",
            "('Маркетинг', 180000.00)",
            "('Финансовый отдел', 220000.00)",
            "('Отдел кадров', 150000.00)",
            "('Техническая поддержка', 170000.00)",
            "('Аналитика данных', 210000.00)",
            "('Административный отдел', 120000.00)"
        ]
        f.write(',\n'.join(depts) + ';\n\n')
        
        # 2. Должности (Positions): 15 записей
        f.write('-- Заполнение таблицы должностей\n')
        f.write('INSERT INTO positions (position_title) VALUES\n')
        positions = [
            "('Генеральный директор')",
            "('Технический директор')",
            "('Руководитель отдела разработки')",
            "('Старший разработчик')",
            "('Разработчик')",
            "('Младший разработчик')",
            "('Руководитель тестирования')",
            "('Тестировщик')",
            "('Менеджер по продажам')",
            "('Маркетолог')",
            "('Бухгалтер')",
            "('HR-менеджер')",
            "('Специалист техподдержки')",
            "('Аналитик данных')",
            "('Администратор')"
        ]
        f.write(',\n'.join(positions) + ';\n\n')
        
        # 3. Сотрудники (Employees): 1000 записей с иерархией
        f.write('-- Заполнение таблицы сотрудников\n')
        f.write('INSERT INTO employees (first_name, last_name, email, hire_date, salary, department_id, position_id, manager_id) VALUES\n')
        
        employees = []
        
        # Списки имен и фамилий для генерации реалистичных данных
        first_names = ['Иван', 'Алексей', 'Дмитрий', 'Сергей', 'Андрей', 'Максим', 'Александр', 'Михаил', 'Евгений', 'Владимир',
                      'Ольга', 'Елена', 'Анна', 'Мария', 'Наталья', 'Ирина', 'Светлана', 'Татьяна', 'Екатерина', 'Юлия']
        
        last_names = ['Иванов', 'Петров', 'Сидоров', 'Смирнов', 'Кузнецов', 'Попов', 'Васильев', 'Павлов', 'Семенов', 'Голубев',
                     'Иванова', 'Петрова', 'Сидорова', 'Смирнова', 'Кузнецова', 'Попова', 'Васильева', 'Павлова', 'Семенова', 'Голубева']
        
        # Сначала создадим руководство (первые 5 записей - топ-менеджеры)
        for i in range(5):
            first = random.choice(first_names)
            last = random.choice(last_names)
            email = f'{first.lower()}.{last.lower()}{i+1}@company.com'
            
            # Дата приема от 3 до 10 лет назад
            years_ago = random.randint(3, 10)
            hire_date = datetime.now() - timedelta(days=365*years_ago + random.randint(0, 365))
            hire_date_str = hire_date.strftime('%Y-%m-%d')
            
            # Зарплата для руководства выше
            salary = round(random.uniform(80000, 150000), 2)
            
            # Первые 2 сотрудника в отделе руководства, остальные - начальники отделов
            dept_id = 1 if i < 2 else i + 1  # Руководство(1) или отделы(2-6)
            position_id = i + 1  # Соответствует позициям 1-5
            manager_id = 'NULL' if i == 0 else 1  # Первый - гендир, остальные под ним
            
            employees.append(f"('{first}', '{last}', '{email}', '{hire_date_str}', {salary}, {dept_id}, {position_id}, {manager_id})")
        
        # Остальные сотрудники (рядовые)
        for i in range(5, 1000):
            first = random.choice(first_names)
            last = random.choice(last_names)
            email = f'{first.lower()}.{last.lower()}{i+1}@company.com'
            
            # Дата приема от 0 до 5 лет назад
            years_ago = random.uniform(0, 5)
            hire_date = datetime.now() - timedelta(days=int(365*years_ago))
            hire_date_str = hire_date.strftime('%Y-%m-%d')
            
            # Зарплата в зависимости от позиции
            position_id = random.randint(3, 15)  # Позиции от 3 до 15
            salary_base = {
                3: (60000, 90000),   # Руководитель отдела
                4: (50000, 80000),   # Старший разработчик
                5: (40000, 65000),   # Разработчик
                6: (30000, 45000),   # Младший разработчик
                7: (45000, 70000),   # Руководитель тестирования
                8: (35000, 55000),   # Тестировщик
                9: (40000, 75000),   # Менеджер по продажам (+ премии)
                10: (35000, 60000),  # Маркетолог
                11: (40000, 65000),  # Бухгалтер
                12: (35000, 60000),  # HR-менеджер
                13: (30000, 45000),  # Техподдержка
                14: (45000, 70000),  # Аналитик
                15: (30000, 40000)   # Администратор
            }
            min_sal, max_sal = salary_base.get(position_id, (30000, 50000))
            salary = round(random.uniform(min_sal, max_sal), 2)
            
            # Отдел в зависимости от должности
            dept_mapping = {
                3: 2, 4: 2, 5: 2, 6: 2,      # Разработка
                7: 3, 8: 3,                   # Тестирование
                9: 4,                         # Продажи
                10: 5,                        # Маркетинг
                11: 6,                        # Финансы
                12: 7,                        # Кадры
                13: 8,                        # Техподдержка
                14: 9,                        # Аналитика
                15: 10                        # Административный
            }
            dept_id = dept_mapping.get(position_id, random.randint(2, 10))
            
            # Менеджер: либо руководитель отдела, либо старший сотрудник
            # Руководители отделов (id 2-6) подчиняются напрямую гендиру или техдиру
            if position_id == 3:  # Руководитель отдела
                manager_id = random.choice([1, 2])  # Гендир или техдир
            else:
                # Для остальных: 70% под начальником отдела, 30% под старшим сотрудником
                if random.random() < 0.7:
                    manager_id = dept_id  # Начальник отдела (id совпадает с dept_id для первых 5)
                else:
                    manager_id = random.randint(2, 50)  # Старший сотрудник
            
            employees.append(f"('{first}', '{last}', '{email}', '{hire_date_str}', {salary}, {dept_id}, {position_id}, {manager_id})")
        
        # Разбиваем на группы по 100 записей для удобства
        for i in range(0, len(employees), 100):
            batch = employees[i:i+100]
            f.write(',\n'.join(batch))
            if i + 100 < len(employees):
                f.write(',\n\n')
            else:
                f.write(';\n\n')
        
        # 4. Заполнение журнала аудита (для демонстрации)
        f.write('-- Пример заполнения журнала аудита (несколько записей)\n')
        f.write('INSERT INTO audit_log (table_name, record_id, operation_type, old_values, new_values, changed_by, changed_at) VALUES\n')
        
        audit_entries = []
        # Примеры изменений зарплат
        for i in range(1, 21):
            emp_id = random.randint(1, 1000)
            old_salary = round(random.uniform(30000, 80000), 2)
            new_salary = round(old_salary * random.uniform(1.05, 1.15), 2)  # Повышение на 5-15%
            changed_by = random.randint(1, 5)  # Изменение сделал кто-то из руководства
            
            audit_entries.append(
                f"('employees', {emp_id}, 'UPDATE', "
                f"'{{""salary"": {old_salary}}}', "
                f"'{{""salary"": {new_salary}}}', "
                f"{changed_by}, CURRENT_TIMESTAMP)"
            )
        
        # Примеры приема на работу
        for i in range(21, 31):
            emp_id = random.randint(900, 1000)
            changed_by = random.randint(1, 5)
            
            audit_entries.append(
                f"('employees', {emp_id}, 'INSERT', "
                f"'NULL', "
                f"'{{""employee_id"": {emp_id}, ""operation"": ""hire""}}', "
                f"{changed_by}, CURRENT_TIMESTAMP)"
            )
        
        f.write(',\n'.join(audit_entries) + ';\n\n')
        
        print(f"Сгенерирован файл 'hrm_load_data.sql' с тестовыми данными:")
        print(f"- 10 отделов")
        print(f"- 15 должностей")
        print(f"- 1000 сотрудников с иерархической структурой")
        print(f"- 30 записей в журнале аудита")
        print(f"\nДля выполнения SQL-скрипта используйте команду:")
        print(f"psql -U ваш_пользователь -d ваша_база -f hrm_load_data.sql")

# Запуск генерации
generate_hrm_data()