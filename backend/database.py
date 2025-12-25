from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os

# URL базы данных из переменных окружения (для Docker) или локальный
DATABASE_URL = os.getenv(
    "DATABASE_URL", 
    "postgresql://postgres:ecole1286@localhost:5432/hr_management"
)

# Создание движка SQLAlchemy с настройками для улучшения производительности
engine = create_engine(
    DATABASE_URL,
    pool_size=20,  # Количество соединений в пуле
    max_overflow=30,  # Максимальное количество соединений сверх pool_size
    pool_pre_ping=True,  # Проверка соединения перед использованием
    echo=False  # Установите True для отладки SQL-запросов
)

# Создание фабрики сессий
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

# Базовый класс для моделей
Base = declarative_base()

def get_db():
    """
    Зависимость для получения сессии базы данных.
    Используется в FastAPI эндпоинтах.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db():
    """
    Инициализация базы данных - создание всех таблиц.
    Вызывается при запуске приложения или в скриптах миграции.
    """
    Base.metadata.create_all(bind=engine)
    
def drop_db():
    """
    Удаление всех таблиц из базы данных.
    Использовать с осторожностью - только для разработки!
    """
    Base.metadata.drop_all(bind=engine)

# Функции для проверки и обслуживания базы данных
def check_database_connection():
    """Проверка подключения к базе данных"""
    try:
        with engine.connect() as connection:
            result = connection.execute("SELECT 1")
            return result.scalar() == 1
    except Exception as e:
        print(f"Ошибка подключения к БД: {e}")
        return False

def get_database_info():
    """Получение информации о базе данных"""
    try:
        with engine.connect() as connection:
            # Версия PostgreSQL
            version_result = connection.execute("SELECT version()")
            postgres_version = version_result.scalar()
            
            # Время сервера
            time_result = connection.execute("SELECT now()")
            server_time = time_result.scalar()
            
            # Количество таблиц
            tables_result = connection.execute("""
                SELECT COUNT(*) 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
            """)
            tables_count = tables_result.scalar()
            
            return {
                "postgres_version": postgres_version,
                "server_time": server_time,
                "tables_count": tables_count,
                "connection_url": str(engine.url).replace(str(engine.url.password), "***") if engine.url.password else str(engine.url)
            }
    except Exception as e:
        return {"error": str(e)}

# Если этот файл запускается напрямую, проверяем подключение
if __name__ == "__main__":
    print("Проверка подключения к базе данных...")
    if check_database_connection():
        print("✓ Подключение успешно")
        info = get_database_info()
        print(f"Информация о БД:")
        print(f"  Версия: {info.get('postgres_version', 'неизвестно')}")
        print(f"  Время сервера: {info.get('server_time', 'неизвестно')}")
        print(f"  Количество таблиц: {info.get('tables_count', 0)}")
    else:
        print("✗ Не удалось подключиться к базе данных")
        print(f"URL: {DATABASE_URL}")