FROM python:3.11-slim

WORKDIR /app

# Prevent generation of pyc files
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create user with UID 1000 to match host permissions
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup -m appuser && \
    chown -R appuser:appgroup /app

# Copy files and set permissions
COPY --chown=appuser:appgroup . .

# Switch user
USER appuser

# Expose port
EXPOSE 38317

# Startup command
CMD ["python", "app.py"]