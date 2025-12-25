FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY . .

# Создаем пользователя для безопасности
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

USER appuser

# Убедитесь, что используете правильный модуль
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]