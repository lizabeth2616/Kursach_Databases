from sqlalchemy import Column, Integer, String, Float, Text, Boolean, DateTime, ForeignKey, DECIMAL, Date, JSON, CheckConstraint, UniqueConstraint
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from sqlalchemy.ext.declarative import declared_attr
from database import Base
from datetime import datetime

class Employee(Base):
    __tablename__ = "employees"
    
    employee_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    first_name = Column(String(100), nullable=False)
    last_name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, nullable=False, index=True)
    phone = Column(String(20))
    hire_date = Column(Date, nullable=False, default=func.current_date())
    birth_date = Column(Date)
    salary = Column(DECIMAL(10, 2), nullable=False)
    
    # ВАЖНО: сначала определяем все Column, потом relationships
    department_id = Column(Integer, ForeignKey("departments.department_id", ondelete="SET NULL"))  # ДОБАВЬТЕ ЭТУ СТРОКУ
    position_id = Column(Integer, ForeignKey("positions.position_id", ondelete="SET NULL"))
    manager_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    
    address = Column(Text)
    city = Column(String(100))
    country = Column(String(100), default="Russia")
    postal_code = Column(String(20))
    is_active = Column(Boolean, default=True)
    employment_type = Column(String(50), default="full_time")  # full_time, part_time, contract
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    # Внешние связи - используйте строки для foreign_keys
    department = relationship("Department", back_populates="employees", 
                             foreign_keys=[department_id])  # Теперь department_id определен
    
    # Самореферентная связь для иерархии
    manager = relationship("Employee", remote_side=[employee_id], 
                          back_populates="subordinates", foreign_keys=[manager_id])
    subordinates = relationship("Employee", back_populates="manager", 
                               foreign_keys=[manager_id])
    
    # Другие связи
    position = relationship("Position", back_populates="employees")
    
    # Аудит и дополнительные связи
    salary_changes = relationship("SalaryChange", back_populates="employee")
    vacations = relationship("Vacation", back_populates="employee")
    projects = relationship("EmployeeProject", back_populates="employee")
    
    __table_args__ = (
        CheckConstraint('salary >= 0', name='check_salary_positive'),
        CheckConstraint("email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}$'", name='valid_email'),
    )
    
    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}"
    
    def calculate_experience(self):
        """Рассчитать стаж работы"""
        if self.hire_date:
            from datetime import date
            today = date.today()
            experience = today - self.hire_date
            return experience.days // 365 
        return 0

class Department(Base):
    __tablename__ = "departments"
    
    department_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    department_name = Column(String(150), nullable=False, unique=True)
    department_code = Column(String(20), unique=True)
    budget = Column(DECIMAL(15, 2), default=0)
    manager_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    location = Column(String(255))
    description = Column(Text)
    established_date = Column(Date, default=func.current_date())
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Используем строки для foreign_keys, чтобы избежать циклических зависимостей
    manager = relationship("Employee", foreign_keys=[manager_id])
    employees = relationship("Employee", back_populates="department", 
                            foreign_keys="Employee.department_id")
    
    @property
    def total_salary_budget(self):
        total = 0
        for emp in self.employees:
            if emp.is_active and emp.salary:
                total += float(emp.salary)
        return total
    
    @property
    def employee_count(self):
        return len([emp for emp in self.employees if emp.is_active])

class Position(Base):
    __tablename__ = "positions"
    
    position_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    position_title = Column(String(150), nullable=False, unique=True)
    position_code = Column(String(20), unique=True)
    description = Column(Text)
    min_salary = Column(DECIMAL(10, 2))
    max_salary = Column(DECIMAL(10, 2))
    grade_level = Column(String(10))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
  
    employees = relationship("Employee", back_populates="position")
    
    __table_args__ = (
        CheckConstraint('min_salary <= max_salary', name='check_salary_range'),
    )

class SalaryGrade(Base):
    __tablename__ = "salary_grades"
    
    grade_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    grade_name = Column(String(50), nullable=False, unique=True)
    min_salary = Column(DECIMAL(10, 2), nullable=False)
    max_salary = Column(DECIMAL(10, 2), nullable=False)
    description = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    __table_args__ = (
        CheckConstraint('min_salary <= max_salary', name='check_grade_salary_range'),
    )

class Project(Base):
    __tablename__ = "projects"
    
    project_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    project_name = Column(String(200), nullable=False)
    project_code = Column(String(30), unique=True)
    description = Column(Text)
    start_date = Column(Date)
    end_date = Column(Date)
    budget = Column(DECIMAL(15, 2))
    status = Column(String(50), default="planning")
    department_id = Column(Integer, ForeignKey("departments.department_id", ondelete="SET NULL"))
    manager_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    department = relationship("Department")
    manager = relationship("Employee", foreign_keys=[manager_id])
    employee_projects = relationship("EmployeeProject", back_populates="project")

class EmployeeProject(Base):
    __tablename__ = "employee_projects"
    
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    employee_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="CASCADE"), nullable=False)
    project_id = Column(Integer, ForeignKey("projects.project_id", ondelete="CASCADE"), nullable=False)
    role = Column(String(100)) 
    allocation_percentage = Column(Integer, default=100) 
    start_date = Column(Date, default=func.current_date())
    end_date = Column(Date)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    __table_args__ = (
        UniqueConstraint('employee_id', 'project_id', name='uq_employee_project'),
    )
    
    employee = relationship("Employee", back_populates="projects")
    project = relationship("Project", back_populates="employee_projects")

class Vacation(Base):
    __tablename__ = "vacations"
    
    vacation_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    employee_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="CASCADE"), nullable=False)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    vacation_type = Column(String(50), default="annual")  # annual, sick, maternity, unpaid
    status = Column(String(50), default="pending")  # pending, approved, rejected, taken
    approved_by = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    notes = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    employee = relationship("Employee", back_populates="vacations", foreign_keys=[employee_id])
    approver = relationship("Employee", foreign_keys=[approved_by])
    
    __table_args__ = (
        CheckConstraint('end_date >= start_date', name='check_vacation_dates'),
    )

class SalaryChange(Base):
    __tablename__ = "salary_changes"
    
    change_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    employee_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="CASCADE"), nullable=False)
    old_salary = Column(DECIMAL(10, 2))
    new_salary = Column(DECIMAL(10, 2), nullable=False)
    change_date = Column(Date, nullable=False, default=func.current_date())
    change_type = Column(String(50))  # promotion, annual_raise, adjustment, bonus
    reason = Column(Text)
    approved_by = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    employee = relationship("Employee", back_populates="salary_changes")
    approver = relationship("Employee", foreign_keys=[approved_by])

class AuditLog(Base):
    __tablename__ = "audit_log"
    
    log_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    table_name = Column(String(100), nullable=False)
    record_id = Column(Integer, nullable=False)
    action = Column(String(10), nullable=False)  # INSERT, UPDATE, DELETE
    old_data = Column(JSON)
    new_data = Column(JSON)
    changed_by = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    changed_at = Column(DateTime(timezone=True), server_default=func.now())
    ip_address = Column(String(45))
    user_agent = Column(Text)
    
    changer = relationship("Employee", foreign_keys=[changed_by])

class ImportLog(Base):
    __tablename__ = "import_logs"
    
    import_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    filename = Column(String(255))
    import_type = Column(String(50))  # employees, departments, etc.
    total_records = Column(Integer)
    successful_records = Column(Integer)
    failed_records = Column(Integer)
    error_details = Column(JSON)
    imported_by = Column(Integer, ForeignKey("employees.employee_id", ondelete="SET NULL"))
    import_date = Column(DateTime(timezone=True), server_default=func.now())
    
    importer = relationship("Employee", foreign_keys=[imported_by])

class SystemUser(Base):
    __tablename__ = "system_users"
    
    user_id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    username = Column(String(100), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    email = Column(String(255), unique=True)
    employee_id = Column(Integer, ForeignKey("employees.employee_id", ondelete="CASCADE"), unique=True)
    role = Column(String(50), default="user")  # admin, hr_manager, department_head, user
    is_active = Column(Boolean, default=True)
    last_login = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    employee = relationship("Employee", foreign_keys=[employee_id])