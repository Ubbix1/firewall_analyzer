FROM python:3.12-slim

WORKDIR /app

# Copy only needed files first (better caching)
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Copy rest of project
COPY . .

# Ignore venv
RUN rm -rf venv

# Expose port (CHANGE if needed)
EXPOSE 5000

# Run app
CMD ["python", "packet_server.py"]
