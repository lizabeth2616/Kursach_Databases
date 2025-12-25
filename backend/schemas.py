from pydantic import BaseModel, EmailStr, Field, validator, ConfigDict
from datetime import datetime, date
from typing import Optional, List
from decimal import Decimal


class EmployeeBase(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=100, description="Имя сотрудника")
    last_name: str = Field(..., min_length=1, max_length=100, description="Фамилия сотрудника")
    email: EmailStr = Field(..., description="Электронная почта")
    phone: Optional[str] = Field(None, max_length=20, description="Телефон")
    hire_date: date = Field(..., description="Дата приема на работу")
    birth_date: Optional[date] = Field(None, description="Дата рождения")
    salary: Decimal = Field(..., gt=0, description="Зарплата")
    department_id: Optional[int] = Field(None, description="ID отдела")
    position_id: Optional[int] = Field(None, description="ID должности")
    manager_id: Optional[int] = Field(None, description="ID руководителя")
    address: Optional[str] = Field(None, description="Адрес")
    city: Optional[str] = Field(None, max_length=100, description="Город")
    country: Optional[str] = Field("Russia", max_length=100, description="Страна")
    postal_code: Optional[str] = Field(None, max_length=20, description="Почтовый индекс")
    employment_type: Optional[str] = Field("full_time", description="Тип занятости")

    @validator('hire_date')
    def validate_hire_date(cls, v):
        if v > date.today():
            raise ValueError('Дата найма не может быть в будущем')
        return v

    @validator('salary')
    def validate_salary(cls, v):
        if v <= 0:
            raise ValueError('Зарплата должна быть положительной')
        return v

class EmployeeCreate(EmployeeBase):
    pass

class EmployeeUpdate(BaseModel):
    first_name: Optional[str] = Field(None, min_length=1, max_length=100)
    last_name: Optional[str] = Field(None, min_length=1, max_length=100)
    email: Optional[EmailStr] = None
    phone: Optional[str] = Field(None, max_length=20)
    salary: Optional[Decimal] = Field(None, gt=0)
    department_id: Optional[int] = None
    position_id: Optional[int] = None
    manager_id: Optional[int] = None
    address: Optional[str] = None
    is_active: Optional[bool] = True

class EmployeeResponse(EmployeeBase):
    employee_id: int
    is_active: bool
    created_at: datetime
    updated_at: Optional[datetime] = None
    full_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)



class DepartmentBase(BaseModel):
    department_name: str = Field(..., min_length=1, max_length=150, description="Название отдела")
    department_code: Optional[str] = Field(None, max_length=20, description="Код отдела")
    budget: Decimal = Field(default=0, ge=0, description="Бюджет отдела")
    manager_id: Optional[int] = Field(None, description="ID руководителя отдела")
    location: Optional[str] = Field(None, description="Местоположение")
    description: Optional[str] = Field(None, description="Описание отдела")

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentUpdate(BaseModel):
    department_name: Optional[str] = Field(None, min_length=1, max_length=150)
    budget: Optional[Decimal] = Field(None, ge=0)
    manager_id: Optional[int] = None
    location: Optional[str] = None
    is_active: Optional[bool] = True

class DepartmentResponse(DepartmentBase):
    department_id: int
    established_date: date
    is_active: bool
    created_at: datetime
    total_salary_budget: Optional[Decimal] = None
    employee_count: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class PositionBase(BaseModel):
    position_title: str = Field(..., min_length=1, max_length=150, description="Название должности")
    position_code: Optional[str] = Field(None, max_length=20, description="Код должности")
    description: Optional[str] = Field(None, description="Описание должности")
    min_salary: Optional[Decimal] = Field(None, ge=0, description="Минимальная зарплата")
    max_salary: Optional[Decimal] = Field(None, ge=0, description="Максимальная зарплата")
    grade_level: Optional[str] = Field(None, max_length=10, description="Уровень грейда")

    @validator('max_salary')
    def validate_salary_range(cls, v, values):
        if 'min_salary' in values and values['min_salary'] and v:
            if v < values['min_salary']:
                raise ValueError('Максимальная зарплата не может быть меньше минимальной')
        return v

class PositionCreate(PositionBase):
    pass

class PositionResponse(PositionBase):
    position_id: int
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ProjectBase(BaseModel):
    project_name: str = Field(..., min_length=1, max_length=200, description="Название проекта")
    project_code: Optional[str] = Field(None, max_length=30, description="Код проекта")
    description: Optional[str] = Field(None, description="Описание проекта")
    start_date: Optional[date] = Field(None, description="Дата начала")
    end_date: Optional[date] = Field(None, description="Дата окончания")
    budget: Optional[Decimal] = Field(None, ge=0, description="Бюджет проекта")
    status: Optional[str] = Field("planning", description="Статус проекта")
    department_id: Optional[int] = Field(None, description="ID отдела")
    manager_id: Optional[int] = Field(None, description="ID руководителя проекта")

    @validator('end_date')
    def validate_project_dates(cls, v, values):
        if 'start_date' in values and values['start_date'] and v:
            if v < values['start_date']:
                raise ValueError('Дата окончания должна быть позже даты начала')
        return v

class ProjectCreate(ProjectBase):
    pass

class ProjectResponse(ProjectBase):
    project_id: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class VacationBase(BaseModel):
    employee_id: int = Field(..., description="ID сотрудника")
    start_date: date = Field(..., description="Дата начала отпуска")
    end_date: date = Field(..., description="Дата окончания отпуска")
    vacation_type: Optional[str] = Field("annual", description="Тип отпуска")
    status: Optional[str] = Field("pending", description="Статус отпуска")
    notes: Optional[str] = Field(None, description="Примечания")

    @validator('end_date')
    def validate_vacation_dates(cls, v, values):
        if 'start_date' in values and v < values['start_date']:
            raise ValueError('Дата окончания должна быть позже даты начала')
        return v

class VacationCreate(VacationBase):
    pass

class VacationResponse(VacationBase):
    vacation_id: int
    created_at: datetime
    approved_by: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class SalaryChangeBase(BaseModel):
    employee_id: int = Field(..., description="ID сотрудника")
    new_salary: Decimal = Field(..., gt=0, description="Новая зарплата")
    change_type: str = Field(..., description="Тип изменения")
    reason: Optional[str] = Field(None, description="Причина изменения")
    approved_by: Optional[int] = Field(None, description="ID утвердившего")

class SalaryChangeCreate(SalaryChangeBase):
    pass

class SalaryChangeResponse(SalaryChangeBase):
    change_id: int
    old_salary: Optional[Decimal] = None
    change_date: date
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class SystemUserBase(BaseModel):
    username: str = Field(..., min_length=3, max_length=100, description="Имя пользователя")
    email: EmailStr = Field(..., description="Электронная почта")
    employee_id: int = Field(..., description="ID сотрудника")
    role: Optional[str] = Field("user", description="Роль пользователя")

class SystemUserCreate(SystemUserBase):
    password: str = Field(..., min_length=6, description="Пароль")

class SystemUserLogin(BaseModel):
    username: str = Field(..., description="Имя пользователя")
    password: str = Field(..., description="Пароль")

class SystemUserResponse(SystemUserBase):
    user_id: int
    is_active: bool
    created_at: datetime
    last_login: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class DepartmentSalaryReport(BaseModel):
    department_id: int
    department_name: str
    employee_count: int
    total_salary: Decimal
    avg_salary: Decimal

    model_config = ConfigDict(from_attributes=True)

class EmployeeHierarchy(BaseModel):
    employee_id: int
    employee_name: str
    position_title: Optional[str] = None
    department_name: Optional[str] = None
    manager_name: Optional[str] = None
    manager_id: Optional[int] = None
    level: Optional[int] = 0

    model_config = ConfigDict(from_attributes=True)

class EmployeeStatistics(BaseModel):
    total_employees: int
    active_employees: int
    total_salary_budget: Decimal
    avg_salary: Decimal
    department_distribution: List[dict]

    model_config = ConfigDict(from_attributes=True)

class ProjectLoadReport(BaseModel):
    project_id: int
    project_name: str
    total_employees: int
    allocation_sum: int
    status: str

    model_config = ConfigDict(from_attributes=True)


class BatchImportRequest(BaseModel):
    data: List[dict] = Field(..., description="Данные для импорта")
    import_type: str = Field(..., description="Тип импорта (employees, departments, etc.)")

class BatchImportResult(BaseModel):
    success: int = 0
    failed: int = 0
    total_processed: int = 0
    errors: List[dict] = []


class AuditLogResponse(BaseModel):
    log_id: int
    table_name: str
    record_id: int
    action: str
    old_data: Optional[dict] = None
    new_data: Optional[dict] = None
    changed_by: Optional[int] = None
    changed_at: datetime

    model_config = ConfigDict(from_attributes=True)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user_id: int
    role: str

class TokenData(BaseModel):
    user_id: Optional[int] = None
    role: Optional[str] = None


class DepartmentFilter(BaseModel):
    department_id: Optional[int] = None
    is_active: Optional[bool] = True

class EmployeeFilter(BaseModel):
    department_id: Optional[int] = None
    position_id: Optional[int] = None
    manager_id: Optional[int] = None
    is_active: Optional[bool] = True
    min_salary: Optional[Decimal] = None
    max_salary: Optional[Decimal] = None

class SalaryIncreaseRequest(BaseModel):
    department_id: int
    percent: Decimal = Field(..., gt=0, le=100, description="Процент повышения (0-100)")


class SearchResult(BaseModel):
    employees: List[EmployeeResponse] = []
    departments: List[DepartmentResponse] = []
    total_results: int


class HealthCheck(BaseModel):
    status: str
    database: str
    timestamp: datetime
    uptime: float
    version: str

class DatabaseInfo(BaseModel):
    postgres_version: str
    server_time: datetime
    tables_count: int
    connection_info: dict

class PaginationParams(BaseModel):
    skip: int = Field(0, ge=0, description="Сколько записей пропустить")
    limit: int = Field(100, ge=1, le=1000, description="Лимит записей")

class PaginatedResponse(BaseModel):
    data: List
    total: int
    skip: int
    limit: int
    has_more: bool