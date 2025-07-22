FROM python:3.12-alpine

# Set the working directory
WORKDIR /app

# Copy the dependency file (to optimize caching)
COPY requirements.txt ./

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Specify the port the Flask app will use
EXPOSE 5000

# Set environment variables (optional)
ENV FLASK_APP=app.py
ENV FLASK_RUN_HOST=0.0.0.0
ENV FLASK_RUN_PORT=5000

# Create a non-root user (for security)
RUN adduser -D -s /bin/sh appuser && \
    chown -R appuser:appuser /app
USER appuser

# Run the Flask application
CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
