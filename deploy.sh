#!/bin/bash

# This script automates the deployment of FreshRSS and News Feeder using Docker Compose.
# It handles Git operations, Docker image building, service deployment,
# and displays the access URL at the end.

# --- Configuration ---
# The directory where your FreshRSS and News Feeder project resides
PROJECT_ROOT="/home/hunter/Desktop/freshrss_app"
# Your GitHub repository URL
GITHUB_REPO_URL="https://github.com/randumduck/upsc-daily-news-digest.git"

# --- Functions ---

# Function to check if a command exists
command_exists () {
  command -v "$1" >/dev/null 2>&1
}

# Function to ensure Docker and Docker Compose are installed and running
check_docker_prerequisites() {
  echo "--- Checking Docker and Docker Compose prerequisites ---"
  if ! command_exists docker; then
    echo "Error: Docker is not installed. Please install Docker first."
    echo "Refer to: https://docs.docker.com/engine/install/ubuntu/"
    exit 1
  fi

  # Check if Docker daemon is running, start if not. Requires sudo.
  if ! sudo systemctl is-active --quiet docker; then
    echo "Error: Docker daemon is not running. Attempting to start Docker..."
    sudo systemctl start docker
    if ! sudo systemctl is-active --quiet docker; then
      echo "Error: Failed to start Docker daemon. Please troubleshoot manually."
      exit 1
    fi
    echo "Docker daemon started successfully."
  fi

  # Check for Docker Compose (prefers 'docker compose' plugin, falls back to old 'docker-compose')
  if ! command_exists docker compose; then
    if ! command_exists docker-compose; then
      echo "Error: Docker Compose (or docker-compose) is not installed."
      echo "Refer to: https://docs.docker.com/compose/install/"
      exit 1
    fi
  fi
  echo "Docker and Docker Compose are installed and running."
}

# Function to configure Git credentials and ensure safe directory
configure_git_operations() {
  echo "--- Performing Git operations ---"

  # Add directory to Git's safe.directory to prevent dubious ownership errors
  # This command is safe to run multiple times.
  echo "Configuring Git safe directory for '$PROJECT_ROOT'..."
  git config --global --add safe.directory "$PROJECT_ROOT"
  if [ $? -ne 0 ]; then
    echo "Warning: Failed to add '$PROJECT_ROOT' to Git safe directories. This might cause issues."
  fi

  if [ -d "$PROJECT_ROOT" ]; then
    echo "Project directory '$PROJECT_ROOT' already exists. Pulling latest changes..."
    cd "$PROJECT_ROOT" || { echo "Error: Could not change to project directory for Git operations."; exit 1; }

    # Pull latest changes from the main branch
    git pull --rebase origin main
    if [ $? -ne 0 ]; then
        echo "Warning: 'git pull --rebase' failed. This might be due to local uncommitted changes or network issues."
        echo "Please resolve manually if issues persist."
    fi
    echo "Pulled latest changes from Git."
  else
    echo "Project directory '$PROJECT_ROOT' does not exist. Cloning repository..."
    mkdir -p "$(dirname "$PROJECT_ROOT")" # Create parent directory if needed
    git clone "$GITHUB_REPO_URL" "$PROJECT_ROOT"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to clone repository. Please check URL and network connectivity."
      exit 1
    fi
    cd "$PROJECT_ROOT" || { echo "Error: Could not change to cloned directory."; exit 1; }
    echo "Repository cloned successfully."

    # Set initial Git identity for the repository if not already set
    if ! git config user.email > /dev/null; then
        echo "Setting local Git identity (email and name for this repository)..."
        git config user.email "kmrnik95@gmail.com" # <--- IMPORTANT: Replace with your actual email
        git config user.name "randumduck" # <--- IMPORTANT: Replace with your actual GitHub username
    fi
  fi
  # IMPORTANT: The primary chown for the entire project root is moved AFTER Docker Compose up,
  # to handle potential re-creation of volume directories by Docker.
  # A placeholder chown might be needed here if certain Git operations require host user write access immediately.
  # For now, we rely on the post-docker-compose chown for volumes.
}

# Function to build and deploy Docker services
deploy_docker_services() {
  echo "--- Building and deploying Docker services ---"
  cd "$PROJECT_ROOT" || { echo "Error: Could not change to project directory for Docker operations."; exit 1; }

  # Stop and remove existing containers (to ensure a clean restart with latest images/configs)
  echo "Stopping and removing existing Docker Compose services..."
  # No sudo needed here, as the user is expected to be in the 'docker' group
  docker compose down --remove-orphans > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Warning: Failed to stop existing Docker Compose services. Continuing with build/start."
  fi
  echo "Existing services stopped (if any)."

  # Build the news-feeder image
  echo "Building news-feeder Docker image..."
  # No sudo needed here
  docker compose build news-feeder
  if [ $? -ne 0 ]; then
    echo "Error: Failed to build news-feeder Docker image. Check your Dockerfile and requirements.txt."
    exit 1
  fi
  echo "News feeder Docker image built successfully."

  # Start all services in detached mode
  echo "Starting all Docker Compose services (db, freshrss, news-feeder)..."
  # No sudo needed here. Docker Compose will find .env in the current directory automatically.
  docker compose up -d
  if [ $? -ne 0 ]; then
    echo "Error: Failed to start Docker Compose services. Check your docker-compose.yml for errors."
    exit 1
  fi
  echo "Docker Compose services started successfully in detached mode."

  # --- NEW / MOVED CHOWN COMMAND ---
  # Re-ensure correct ownership of the project directory and specifically volume directories
  # This runs *after* docker compose up, to fix permissions if docker recreated volumes as root.
  echo "Ensuring correct ownership of project and Docker volume directories after startup..."
  sudo chown -R $(id -un):$(id -gn) "$PROJECT_ROOT"
  if [ $? -ne 0 ]; then
      echo "Error: Failed to set correct ownership for '$PROJECT_ROOT' after Docker startup. This might cause future Docker volume permission issues."
      echo "Please ensure you have sudo privileges and try again."
      exit 1
  fi
  echo "Ownership set to current user for host directories."

  # Provide instructions for verifying services
  echo -e "\n--- Deployment Status ---"
  echo "To check if containers are running, execute: docker ps"
  echo "The 'news-feeder' container will run once and then exit."
  echo "You can check its past run logs with: docker logs news_feeder_app"
}

# Function to display the VM's IP address
display_ip_address() {
  echo -e "\n--- Accessing FreshRSS ---"
  VM_IP=$(ip a | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)

  if [ -z "$VM_IP" ]; then
    echo "Could not automatically determine VM's IP address."
    echo "Please find your VM's IP address manually (e.g., using 'ip a' or 'ifconfig')."
    echo "Then, open your web browser and navigate to: http://<Your_VM_IP_Address>"
  else
    echo "Your FreshRSS application should now be accessible at:"
    echo "http://$VM_IP"
    echo "Open this URL in your web browser to complete the FreshRSS setup."
  fi
}

# --- Main Execution ---
clear # Clear screen for a cleaner output

echo "Starting FreshRSS and News Feeder Deployment Script"
echo "Current time (IST): $(TZ='Asia/Kolkata' date)"
echo "Project directory: $PROJECT_ROOT"
echo "GitHub repository: $GITHUB_REPO_URL"
echo "---------------------------------------------------"

check_docker_prerequisites
configure_git_operations # Git operations (clone/pull) happen here
deploy_docker_services   # Docker build/up and the crucial post-startup chown happen here
display_ip_address

echo -e "\n--- Deployment script finished ---"
