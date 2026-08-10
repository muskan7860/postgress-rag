# use Python 3.12 because the application requires python >= 3.12
FROM python:3.12-slim

# Prevent Python from creating .pyc files
# and make python output appear immediately in Docker Logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Application directory inside the container
WORKDIR /app

COPY requirements.txt .

# Install Python dependencies
RUN pip install \
    --no-cache-dir \
    --default-timeout=300 \
    --retries=10 \
    -r requirements.txt

# Copy application source code
COPY app.py .
COPY main.py .

# streamlit default port
EXPOSE 8501

# start the streamlit application
CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]

