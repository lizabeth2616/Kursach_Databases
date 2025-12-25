from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text, func
import pandas as pd
import json
from datetime import datetime
import io
import logging

from database import get_db, engine
import models
import schemas

# Настройка логирования для батчевой загрузки
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="HR Management System API",
    description="API для системы управления персоналом и зарплатами",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ========== БАЗОВЫЕ CRUD ЭНДПОИНТЫ ==========

# 1. Сотрудники (Employees)
@app.get("/employees/", response_model=list[schemas.EmployeeResponse])
def get_employees(
    skip: int = 0, 
    limit: int = 100, 
    department_id: int = None,
    db: Session = Depends(get_db)
):
    """Получить список сотрудников с фильтрацией"""
    query = db.query(models.Employee)
    
    if department_id:
        query = query.filter(models.Employee.department_id == department_id)
    
    employees = query.offset(skip).limit(limit).all()
    return employees

@app.get("/employees/{employee_id}", response_model=schemas.EmployeeResponse)
def get_employee(employee_id: int, db: Session = Depends(get_db)):
    """Получить сотрудника по ID"""
    employee = db.query(models.Employee).filter(models.Employee.employee_id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    return employee

@app.post("/employees/", response_model=schemas.EmployeeResponse)
def create_employee(employee: schemas.EmployeeCreate, db: Session = Depends(get_db)):
    """Создать нового сотрудника"""
    # Проверка email на уникальность
    existing_employee = db.query(models.Employee).filter(
        models.Employee.email == employee.email
    ).first()
    if existing_employee:
        raise HTTPException(status_code=400, detail="Email уже используется")
    
    # Проверка существования отдела
    if employee.department_id:
        department = db.query(models.Department).filter(
            models.Department.department_id == employee.department_id
        ).first()
        if not department:
            raise HTTPException(status_code=400, detail="Отдел не существует")
    
    # Проверка существования руководителя
    if employee.manager_id:
        manager = db.query(models.Employee).filter(
            models.Employee.employee_id == employee.manager_id
        ).first()
        if not manager:
            raise HTTPException(status_code=400, detail="Руководитель не существует")
    
    db_employee = models.Employee(**employee.dict())
    db.add(db_employee)
    db.commit()
    db.refresh(db_employee)
    return db_employee

@app.put("/employees/{employee_id}", response_model=schemas.EmployeeResponse)
def update_employee(employee_id: int, employee_data: schemas.EmployeeUpdate, db: Session = Depends(get_db)):
    """Обновить данные сотрудника"""
    employee = db.query(models.Employee).filter(models.Employee.employee_id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    
    # Обновление полей
    update_data = employee_data.dict(exclude_unset=True)
    
    for key, value in update_data.items():
        setattr(employee, key, value)
    
    db.commit()
    db.refresh(employee)
    return employee

@app.delete("/employees/{employee_id}")
def delete_employee(employee_id: int, db: Session = Depends(get_db)):
    """Удалить сотрудника"""
    employee = db.query(models.Employee).filter(models.Employee.employee_id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    
    db.delete(employee)
    db.commit()
    return {"message": "Сотрудник удален"}

# 2. Отделы (Departments)
@app.get("/departments/", response_model=list[schemas.DepartmentResponse])
def get_departments(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """Получить список отделов"""
    departments = db.query(models.Department).offset(skip).limit(limit).all()
    return departments

@app.post("/departments/", response_model=schemas.DepartmentResponse)
def create_department(department: schemas.DepartmentCreate, db: Session = Depends(get_db)):
    """Создать новый отдел"""
    db_department = models.Department(**department.dict())
    db.add(db_department)
    db.commit()
    db.refresh(db_department)
    return db_department

# 3. Должности (Positions)
@app.get("/positions/", response_model=list[schemas.PositionResponse])
def get_positions(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """Получить список должностей"""
    positions = db.query(models.Position).offset(skip).limit(limit).all()
    return positions

# ========== СЛОЖНЫЕ SQL-ЗАПРОСЫ (RAW SQL) ==========

@app.get("/reports/department-salary")
def get_department_salary_report(db: Session = Depends(get_db)):
    """Отчет: общий фонд заработной платы по отделам (GROUP BY, SUM)"""
    query = """
        SELECT 
            d.department_id,
            d.department_name,
            COUNT(e.employee_id) as employee_count,
            SUM(e.salary) as total_salary,
            AVG(e.salary) as avg_salary
        FROM departments d
        LEFT JOIN employees e ON d.department_id = e.department_id
        GROUP BY d.department_id, d.department_name
        ORDER BY total_salary DESC
    """
    result = db.execute(text(query))
    return [dict(row._mapping) for row in result]

@app.get("/employees/{employee_id}/subordinates")
def get_employee_subordinates(employee_id: int, db: Session = Depends(get_db)):
    """Найти всех подчиненных для конкретного менеджера (SELF JOIN)"""
    query = """
        WITH RECURSIVE subordinates AS (
            -- Начальная точка: сам менеджер
            SELECT e.*, 0 as level
            FROM employees e
            WHERE e.employee_id = :employee_id
            
            UNION ALL
            
            -- Рекурсивно находим подчиненных
            SELECT e.*, s.level + 1
            FROM employees e
            INNER JOIN subordinates s ON e.manager_id = s.employee_id
        )
        SELECT * FROM subordinates WHERE employee_id != :employee_id
        ORDER BY level, last_name, first_name
    """
    result = db.execute(text(query), {"employee_id": employee_id})
    return [dict(row._mapping) for row in result]

@app.get("/reports/employee-hierarchy")
def get_employee_hierarchy(db: Session = Depends(get_db)):
    """Иерархия сотрудников с их руководителями"""
    query = """
        SELECT 
            e.employee_id,
            e.first_name || ' ' || e.last_name as employee_name,
            e.position_id,
            p.position_title,
            d.department_name,
            m.first_name || ' ' || m.last_name as manager_name,
            e.manager_id
        FROM employees e
        LEFT JOIN employees m ON e.manager_id = m.employee_id
        LEFT JOIN departments d ON e.department_id = d.department_id
        LEFT JOIN positions p ON e.position_id = p.position_id
        ORDER BY d.department_name, e.last_name
    """
    result = db.execute(text(query))
    return [dict(row._mapping) for row in result]

@app.get("/reports/department/{department_id}/employees")
def get_department_employees(department_id: int, db: Session = Depends(get_db)):
    """Все сотрудники указанного отдела"""
    query = """
        SELECT 
            e.*,
            p.position_title,
            m.first_name || ' ' || m.last_name as manager_name
        FROM employees e
        LEFT JOIN positions p ON e.position_id = p.position_id
        LEFT JOIN employees m ON e.manager_id = m.employee_id
        WHERE e.department_id = :department_id
        ORDER BY e.last_name, e.first_name
    """
    result = db.execute(text(query), {"department_id": department_id})
    return [dict(row._mapping) for row in result]

# ========== ПРЕДСТАВЛЕНИЯ (VIEWS) ==========

@app.get("/views/employee-full-info")
def get_employee_full_info(db: Session = Depends(get_db)):
    """Получить данные из представления v_employee_info"""
    result = db.execute(text("SELECT * FROM v_employee_info ORDER BY full_name"))
    return [dict(row._mapping) for row in result]

@app.get("/views/department-budget")
def get_department_budget_view(db: Session = Depends(get_db)):
    """Получить данные из представления v_department_budget"""
    result = db.execute(text("SELECT * FROM v_department_budget ORDER BY total_salary DESC"))
    return [dict(row._mapping) for row in result]

# ========== ХРАНИМЫЕ ПРОЦЕДУРЫ И ФУНКЦИИ ==========

@app.post("/procedures/increase-salary")
def increase_department_salary(
    department_id: int, 
    percent: float,
    db: Session = Depends(get_db)
):
    """Повысить зарплату всем сотрудникам отдела на указанный процент"""
    try:
        # Вызов хранимой процедуры
        result = db.execute(
            text("CALL increase_department_salary(:dept_id, :percent)"),
            {"dept_id": department_id, "percent": percent}
        )
        db.commit()
        
        # Получение результатов обновления
        updated_count = db.execute(
            text("SELECT COUNT(*) FROM employees WHERE department_id = :dept_id"),
            {"dept_id": department_id}
        ).scalar()
        
        return {
            "message": f"Зарплаты успешно повышены на {percent}%",
            "department_id": department_id,
            "affected_employees": updated_count
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка: {str(e)}")

@app.get("/functions/employee-tenure/{employee_id}")
def get_employee_tenure(employee_id: int, db: Session = Depends(get_db)):
    """Получить стаж работы сотрудника с помощью функции"""
    result = db.execute(
        text("SELECT * FROM get_employee_tenure(:emp_id)"),
        {"emp_id": employee_id}
    )
    return [dict(row._mapping) for row in result]

# ========== БАТЧЕВАЯ ЗАГРУЗКА ДАННЫХ ==========

@app.post("/batch/import-employees")
async def batch_import_employees(
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    """Батчевая загрузка сотрудников из CSV файла"""
    results = {
        "success": 0,
        "failed": 0,
        "errors": [],
        "total_processed": 0
    }
    
    try:
        # Чтение CSV файла
        contents = await file.read()
        df = pd.read_csv(io.StringIO(contents.decode('utf-8')))
        
        # Логирование начала загрузки
        logger.info(f"Начата обработка файла: {file.filename}, строк: {len(df)}")
        
        for index, row in df.iterrows():
            results["total_processed"] += 1
            
            try:
                # Валидация данных
                if pd.isna(row.get('email')) or pd.isna(row.get('first_name')):
                    raise ValueError("Отсутствуют обязательные поля")
                
                # Проверка формата email
                if '@' not in str(row.get('email', '')):
                    raise ValueError("Неверный формат email")
                
                # Проверка уникальности email
                existing = db.query(models.Employee).filter(
                    models.Employee.email == row['email']
                ).first()
                if existing:
                    raise ValueError(f"Email {row['email']} уже существует")
                
                # Создание сотрудника
                employee_data = {
                    "first_name": str(row.get('first_name', '')),
                    "last_name": str(row.get('last_name', '')),
                    "email": str(row.get('email', '')),
                    "hire_date": pd.to_datetime(row.get('hire_date')).date() if pd.notna(row.get('hire_date')) else datetime.now().date(),
                    "salary": float(row.get('salary', 0)) if pd.notna(row.get('salary')) else 0.0,
                    "department_id": int(row.get('department_id')) if pd.notna(row.get('department_id')) else None,
                    "position_id": int(row.get('position_id')) if pd.notna(row.get('position_id')) else None,
                    "manager_id": int(row.get('manager_id')) if pd.notna(row.get('manager_id')) else None
                }
                
                # Проверка валидности salary
                if employee_data["salary"] < 0:
                    raise ValueError("Зарплата не может быть отрицательной")
                
                db_employee = models.Employee(**employee_data)
                db.add(db_employee)
                db.commit()
                results["success"] += 1
                
                logger.info(f"Успешно импортирован: {employee_data['email']}")
                
            except Exception as e:
                db.rollback()
                results["failed"] += 1
                error_msg = f"Строка {index + 1}: {str(e)}"
                results["errors"].append({
                    "row": index + 1,
                    "data": row.to_dict(),
                    "error": error_msg
                })
                logger.error(error_msg)
        
        logger.info(f"Импорт завершен. Успешно: {results['success']}, Ошибок: {results['failed']}")
        
        return results
        
    except Exception as e:
        logger.error(f"Критическая ошибка при импорте: {str(e)}")
        raise HTTPException(status_code=400, detail=f"Ошибка обработки файла: {str(e)}")

# ========== АУДИТ И ТРИГГЕРЫ ==========

@app.get("/audit/logs")
def get_audit_logs(
    skip: int = 0,
    limit: int = 100,
    table_name: str = None,
    action: str = None,
    db: Session = Depends(get_db)
):
    """Получить журнал аудита с фильтрацией"""
    query = db.query(models.AuditLog)
    
    if table_name:
        query = query.filter(models.AuditLog.table_name == table_name)
    if action:
        query = query.filter(models.AuditLog.action == action)
    
    logs = query.order_by(models.AuditLog.changed_at.desc()).offset(skip).limit(limit).all()
    return logs

# ========== ПРОВЕРКА РАБОТЫ СИСТЕМЫ ==========

@app.get("/")
def root():
    return {
        "message": "HR Management System API работает",
        "docs": "/docs",
        "endpoints": {
            "employees": "/employees/",
            "departments": "/departments/",
            "reports": "/reports/",
            "batch_import": "/batch/import-employees",
            "audit": "/audit/logs"
        }
    }

@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    """Проверка состояния системы"""
    try:
        # Проверка подключения к БД
        db.execute(text("SELECT 1"))
        
        # Проверка количества таблиц
        employee_count = db.query(func.count(models.Employee.employee_id)).scalar()
        department_count = db.query(func.count(models.Department.department_id)).scalar()
        
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": datetime.now().isoformat(),
            "statistics": {
                "employees": employee_count,
                "departments": department_count
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка системы: {str(e)}")

@app.get("/database/info")
def get_database_info(db: Session = Depends(get_db)):
    """Получить информацию о структуре базы данных"""
    # Получение списка таблиц
    tables_result = db.execute(text("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
        ORDER BY table_name
    """))
    
    tables = [row[0] for row in tables_result]
    
    # Получение списка представлений
    views_result = db.execute(text("""
        SELECT table_name 
        FROM information_schema.views 
        WHERE table_schema = 'public'
        ORDER BY table_name
    """))
    
    views = [row[0] for row in views_result]
    
    return {
        "tables": tables,
        "views": views,
        "timestamp": datetime.now().isoformat()
    }