# Use a lightweight Python base image
FROM python:3.9-slim-buster

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install dependencies first
# This improves build cache efficiency: if requirements.txt doesn't change,
# these steps won't rerun.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of your application code
# This includes news_feeder.py and config.py
COPY . .

# Create the data and docs directories
# These are needed for news_archive.db and the generated HTML files
RUN mkdir -p data docs

# Command to run your Python script when the container starts
# CMD is preferred for the main purpose of the container
CMD ["python", "news_feeder.py"]

# Optional: If you need a specific user (e.g., for permissions on mounted volumes)
# USER 1000 # Example: run as non-root user (adjust UID if needed for consistency with host or other actions)
