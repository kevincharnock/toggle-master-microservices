FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir Werkzeug==2.3.8

COPY . .

EXPOSE 8005

CMD ["python", "app.py"]