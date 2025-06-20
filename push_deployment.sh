#!/bin/bash

# This script automates pushing code to GitHub and building/pushing a Docker image to Docker Hub.
# It includes force push capabilities for GitHub and handles Docker Hub login.

# --- Configuration ---
# Your GitHub repository URL (ensure it's the SSH or HTTPS URL you use for pushing)
# Example: GITHUB_REPO_URL="https://github.com/yourusername/your-repo.git"
# Example: GITHUB_REPO_URL="git@github.com:yourusername/your-repo.git"
GITHUB_REPO_URL="https://github.com/randumduck/upsc-daily-news-digest.git"

# The local path to your Git project root
PROJECT_ROOT="/home/hunter/Desktop/freshrss_app"

# Your Docker Hub username
DOCKERHUB_USERNAME="randumduck69" # <--- IMPORTANT: Fill in your Docker Hub username here if not already.
# The name for your Docker image on Docker Hub
# This should typically match your service name, or be more generic (e.g., "news-feeder")
DOCKER_IMAGE_NAME="freshrss_app-news-feeder" # Matches the default name from docker compose build news-feeder
# The tag for your Docker image (e.g., latest, v1.0, a timestamp)
DOCKER_IMAGE_TAG="latest"

# --- Functions ---

# Function to check if a command exists
command_exists () {
  command -v "$1" >/dev/null 2>&1
}

# Function to check essential prerequisites
check_prerequisites() {
  echo "--- Checking prerequisites (git, docker, docker compose) ---"
  if ! command_exists git; then
    echo "Error: Git is not installed. Please install Git."
    exit 1
  fi
  if ! command_exists docker; then
    echo "Error: Docker is not installed. Please install Docker."
    exit 1
  fi
  if ! command_exists docker compose; then
    if ! command_exists docker-compose; then
      echo "Error: Docker Compose (or docker-compose) is not installed."
      exit 1
    fi
  fi
  echo "All required tools are installed."
}

# Function to push all changes to GitHub forcefully
push_to_github() {
  echo -e "\n--- Pushing to GitHub (Forcefully) ---"
  cd "$PROJECT_ROOT" || { echo "Error: Could not change to project directory for Git operations."; exit 1; }

  # Ensure the local branch is named 'main'. This handles both new repos (defaulting to 'master')
  # and existing repos that might have a different branch name.
  # This command is crucial for resolving 'src refspec main does not match any' errors.
  git branch -M main
  if [ $? -ne 0 ]; then
      echo "Error: Failed to set local branch name to 'main'. Aborting Git push."
      exit 1
  fi
  echo "Ensured local branch is named 'main'."

  # --- Handle Fresh Setup (Not a Git Repository Yet) ---
  if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "Directory is not a Git repository. Initializing and preparing for first push..."
    git init # This initializes the repo. The branch name is handled by 'git branch -M main' above.
    if [ $? -ne 0 ]; then echo "Error: Failed to initialize Git repository."; exit 1; fi

    git remote add origin "$GITHUB_REPO_URL"
    if [ $? -ne 0 ]; then echo "Error: Failed to add remote origin."; exit 1; fi

    echo "New Git repository initialized and remote 'origin' added."
  fi

  # --- Common Logic for both Fresh and Existing Repos ---
  # Add all changes to the staging area
  echo "Adding all changes to Git staging area..."
  git add .
  if [ $? -ne 0 ]; then
    echo "Error: Failed to add files to Git staging area."
    exit 1
  fi

  # Commit changes.
  echo "Committing changes..."
  if ! git diff-index --quiet HEAD --; then
      git commit -m "Automated deployment update (force push)"
      if [ $? -ne 0 ]; then
        echo "Error: Failed to commit changes."
        exit 1
      fi
  else
      echo "No new changes to commit."
  fi

  # Force push to GitHub (using --force-with-lease for safer overwrite)
  echo -e "\nWARNING: This will forcefully overwrite the 'main' branch on GitHub!"
  echo "Use it with extreme caution. This can lead to lost work for collaborators."
  read -p "Are you sure you want to proceed with forceful GitHub push? (yes/no): " confirm_push
  if [[ "$confirm_push" != "yes" ]]; then
    echo "GitHub push aborted by user."
    return 1 # Indicate that this function did not complete successfully
  fi

  echo "Force pushing to '$GITHUB_REPO_URL' 'main' branch..."
  # -u flag sets the upstream, allowing future 'git push' without specifying origin main.
  git push -u origin main --force-with-lease
  if [ $? -ne 0 ]; then
    echo "Error: Failed to force push to GitHub. Check your credentials and repository URL."
    echo "If you have 2FA enabled, ensure you are using a Personal Access Token (PAT)."
    exit 1
  fi
  echo "Successfully force pushed to GitHub."
}

# Function to log in to Docker Hub
login_docker_hub() {
  echo -e "\n--- Logging into Docker Hub ---"
  if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -p "Please enter your Docker Hub username: " DOCKERHUB_USERNAME_INPUT
    DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME_INPUT" # Update variable in script scope
    if [ -z "$DOCKERHUB_USERNAME" ]; then
      echo "Error: Docker Hub username cannot be empty. Aborting."
      exit 1
    fi
  fi

  echo "Attempting to log into Docker Hub as '$DOCKERHUB_USERNAME'..."
  # Docker will prompt for password interactively
  docker login --username "$DOCKERHUB_USERNAME"
  if [ $? -ne 0 ]; then
    echo "Error: Docker Hub login failed. Check your username and password/PAT."
    exit 1
  fi
  echo "Successfully logged into Docker Hub."
}

# Function to build and push the Docker image
build_and_push_docker_image() {
  echo -e "\n--- Building and Pushing Docker Image to Docker Hub ---"
  cd "$PROJECT_ROOT" || { echo "Error: Could not change to project directory for Docker operations."; exit 1; }

  # Build the image (re-build in case there are Dockerfile/context changes)
  echo "Building Docker image '$DOCKER_IMAGE_NAME'..."
  docker compose build news-feeder
  if [ $? -ne 0 ]; then
    echo "Error: Failed to build Docker image. Check your Dockerfile."
    exit 1
  fi
  echo "Docker image built successfully."

  # Tag the image for Docker Hub
  LOCAL_IMAGE_ID=$(docker images -q freshrss_app-news-feeder:latest)
  if [ -z "$LOCAL_IMAGE_ID" ]; then
    echo "Error: Could not find locally built image 'freshrss_app-news-feeder:latest'."
    echo "Please ensure the build step completed successfully and the image name is correct."
    exit 1
  fi
  
  TARGET_IMAGE="${DOCKERHUB_USERNAME}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
  echo "Tagging image 'freshrss_app-news-feeder:latest' (ID: $LOCAL_IMAGE_ID) as '$TARGET_IMAGE'..."
  docker tag "$LOCAL_IMAGE_ID" "$TARGET_IMAGE"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to tag Docker image."
    exit 1
  fi
  echo "Image tagged successfully."

  # Push the tagged image to Docker Hub
  echo "Pushing image '$TARGET_IMAGE' to Docker Hub..."
  docker push "$TARGET_IMAGE"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to push Docker image to Docker Hub. Check your Docker Hub account and repository."
    exit 1
  fi
  echo "Successfully pushed Docker image to Docker Hub."
}

# --- Main Execution ---
clear # Clear screen for a cleaner output

echo "--- Starting GitHub and Docker Hub Push Script ---"
echo "Project directory: $PROJECT_ROOT"
echo "GitHub Repository: $GITHUB_REPO_URL"
echo "Docker Image: ${DOCKERHUB_USERNAME:-<your_username>}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
echo "---------------------------------------------------"

check_prerequisites
push_to_github || { echo "GitHub push aborted or failed. Exiting."; exit 1; } # Exit if GitHub push is not confirmed or fails
login_docker_hub
build_and_push_docker_image

echo -e "\n--- Script finished successfully ---"
echo "Your code has been pushed to GitHub."
echo "Your Docker image has been pushed to Docker Hub."
