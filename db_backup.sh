#!/bin/bash

# --- Configuration Variables ---
APP_DIR="/home/hunter/freshrss_app" # Absolute path to your FreshRSS app directory
DATA_DIR="$APP_DIR/data"
DB_DATA_DIR="$DATA_DIR/db"          # Directory where PostgreSQL data is persistently stored
DB_BACKUP_DIR="$DATA_DIR/db_backups" # Directory to store backups
DB_CONTAINER_NAME="freshrss_db"     # Name of your PostgreSQL Docker container
APP_CONTAINER_NAME="freshrss_app"   # Name of your FreshRSS Docker container
POSTGRES_CONTAINER_UID="999"        # Default UID for postgres user in official Docker images

# Number of days to keep backups for cleanup (e.g., 30 days)
BACKUP_RETENTION_DAYS=05

# --- Functions ---

# Function to ensure backup directory exists and has correct permissions
ensure_backup_dir() {
    echo "Ensuring backup directory exists: $DB_BACKUP_DIR"
    sudo mkdir -p "$DB_BACKUP_DIR"
    if [ ! -d "$DB_BACKUP_DIR" ]; then
        echo "Error: Failed to create backup directory. Please check permissions."
        exit 1
    fi
    # Ensure ownership is correct, though sudo will handle writes
    sudo chown -R $(id -un):$(id -gn) "$DB_BACKUP_DIR"
    echo "Backup directory is ready."
}

# Function to check if Docker daemon is running
pre_check_docker() {
    echo "Checking Docker daemon status..."
    if ! sudo systemctl is-active --quiet docker; then
        echo "Error: Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
    echo "Docker daemon is running."
}

# Function to take a database backup
take_backup() {
    pre_check_docker # Check Docker status before proceeding
    ensure_backup_dir # Ensure backup directory is ready

    DATE_SUFFIX=$(date +"%Y-%m-%d_%H%M%S")
    BACKUP_FILE="${DB_BACKUP_DIR}/${DATE_SUFFIX}_db_backup.tar.gz"

    echo "Stopping FreshRSS application container ($APP_CONTAINER_NAME) for consistent backup..."
    # Suppress output of stop command unless there's a problem
    sudo docker stop "$APP_CONTAINER_NAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Warning: Could not stop FreshRSS app container. Backup might still proceed but could have minor consistency issues if app is writing heavily."
    fi

    echo "Taking backup of PostgreSQL data from $DB_DATA_DIR (this may take a moment, showing verbose output)..."
    # Use tar directly on the host volume path with verbose output
    sudo tar -czvf "$BACKUP_FILE" -C "$DB_DATA_DIR" . # The '.' means tar the contents of the current dir (DB_DATA_DIR)
    
    if [ $? -eq 0 ]; then
        echo "Backup successful: $BACKUP_FILE"
    else
        echo "Error: Backup failed!"
    fi

    echo "Starting FreshRSS application container ($APP_CONTAINER_NAME)..."
    sudo docker start "$APP_CONTAINER_NAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Warning: Could not start FreshRSS app container. Please check docker logs for $APP_CONTAINER_NAME."
    else
        echo "FreshRSS app container restarted."
    fi
}

# Function to restore a database backup
restore_backup() {
    pre_check_docker # Check Docker status before proceeding
    ensure_backup_dir # Ensure backup directory exists

    echo "Available backups:"
    # Use ls -lh for displaying file sizes
    mapfile -t BACKUP_FILES_FULLPATH < <(find "$DB_BACKUP_DIR" -maxdepth 1 -name "*_db_backup.tar.gz" -print0 | xargs -0 ls -lh | awk '{print $9, $5}' | sort -rV)
    # Reformat for selection, keeping original full path for later use
    declare -A BACKUP_MAP
    BACKUP_INDEX=1
    for item in "${BACKUP_FILES_FULLPATH[@]}"; do
        FILE_NAME=$(echo "$item" | awk '{print $1}')
        FILE_SIZE=$(echo "$item" | awk '{print $2}')
        CLEAN_FILE_NAME=$(basename "$FILE_NAME") # Extract just the filename
        DISPLAY_TEXT="[$BACKUP_INDEX] $CLEAN_FILE_NAME ($FILE_SIZE)"
        echo "$DISPLAY_TEXT"
        BACKUP_MAP["$BACKUP_INDEX"]="$FILE_NAME"
        ((BACKUP_INDEX++))
    done

    if [ ${#BACKUP_FILES_FULLPATH[@]} -eq 0 ]; then
        echo "No backups found in $DB_BACKUP_DIR."
        return
    fi

    echo "Enter the number of the backup to restore, or 0 to cancel."
    read -p "Your choice: " selection_index

    if [[ "$selection_index" == "0" ]]; then
        echo "Restore cancelled."
        return
    fi

    SELECTED_FILE_PATH="${BACKUP_MAP[$selection_index]}"

    if [[ -z "$SELECTED_FILE_PATH" ]]; then
        echo "Invalid selection. Please try again."
        return
    fi

    echo "Selected backup: $(basename "$SELECTED_FILE_PATH")"

    read -p "WARNING: Restoring will overwrite current database data. Are you sure? (y/N): " confirm_restore
    if [[ ! "$confirm_restore" =~ ^[Yy]$ ]]; then
        echo "Restore cancelled by user."
        return
    fi

    echo "Stopping FreshRSS database and application containers..."
    sudo docker stop "$APP_CONTAINER_NAME" "$DB_CONTAINER_NAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error stopping containers. Please check Docker status. Exiting restore."
        return
    fi

    echo "Clearing current database data in $DB_DATA_DIR..."
    # Ensure we only remove contents, not the directory itself
    # ':?' ensures script exits if variable is unset or null (safety measure)
    if [ -d "$DB_DATA_DIR" ]; then
        sudo rm -rf "${DB_DATA_DIR:?}"/*
    else
        echo "Warning: Database data directory $DB_DATA_DIR does not exist. Creating it."
        sudo mkdir -p "$DB_DATA_DIR"
    fi

    echo "Extracting backup from $(basename "$SELECTED_FILE_PATH") to $DB_DATA_DIR (showing verbose output)..."
    sudo tar -xzvf "$SELECTED_FILE_PATH" -C "$DB_DATA_DIR"

    # Fix permissions - crucial for PostgreSQL to start
    echo "Setting correct permissions for PostgreSQL data..."
    sudo chown -R "$POSTGRES_CONTAINER_UID":"$POSTGRES_CONTAINER_UID" "$DB_DATA_DIR"

    # Remove postmaster.pid if it exists (prevents startup issues after direct data restore)
    if [ -f "$DB_DATA_DIR/postmaster.pid" ]; then
        echo "Removing old postmaster.pid file..."
        sudo rm "$DB_DATA_DIR/postmaster.pid"
    fi

    echo "Starting FreshRSS database container ($DB_CONTAINER_NAME)..."
    sudo docker start "$DB_CONTAINER_NAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error starting DB container. Please check docker logs for $DB_CONTAINER_NAME. Exiting restore."
        return
    fi
    
    # Wait for DB to be healthy before starting app (optional, but good practice)
    echo "Waiting for database to become healthy..."
    # Added a timeout for the health check loop
    HEALTH_CHECK_TIMEOUT=60 # seconds
    ELAPSED_TIME=0
    while [[ "$(sudo docker inspect -f {{.State.Health.Status}} $DB_CONTAINER_NAME)" != "healthy" ]]; do
        printf "."
        sleep 2
        ELAPSED_TIME=$((ELAPSED_TIME + 2))
        if [ "$ELAPSED_TIME" -ge "$HEALTH_CHECK_TIMEOUT" ]; then
            echo "\nError: Database did not become healthy within $HEALTH_CHECK_TIMEOUT seconds. Check DB container logs."
            return
        fi
    done
    echo "Database is healthy."

    echo "Starting FreshRSS application container ($APP_CONTAINER_NAME)..."
    sudo docker start "$APP_CONTAINER_NAME" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Restore successful. FreshRSS containers are starting/restarting."
        echo "Please allow a minute for FreshRSS to become fully accessible."
    else
        echo "Error: Application container failed to start after restore! Check logs for $APP_CONTAINER_NAME."
    fi
}

# Function to clean up old backups
cleanup_old_backups() {
    ensure_backup_dir # Ensure backup directory exists

    echo "Cleaning up backups older than $BACKUP_RETENTION_DAYS days in $DB_BACKUP_DIR..."
    find "$DB_BACKUP_DIR" -type f -name "*_db_backup.tar.gz" -mtime +"$BACKUP_RETENTION_DAYS" -print -delete
    if [ $? -eq 0 ]; then
        echo "Old backups removed successfully (if any)."
    else
        echo "Error: Failed to cleanup old backups."
    fi
}

# Function to display the main menu
display_menu() {
    echo -e "\n--- FreshRSS Database Management ---"
    echo "1. Take DB Backup"
    echo "2. Restore DB Backup"
    echo "3. Clean Up Old Backups (older than ${BACKUP_RETENTION_DAYS} days)"
    echo "0. Exit"
    echo "------------------------------------"
}

# Main loop for interaction
main_loop() {
    # Request sudo privileges at the start to avoid multiple prompts
    sudo -v
    if [ $? -ne 0 ]; then
        echo "Error: Sudo privileges required. Exiting."
        exit 1
    fi
    echo "Sudo privileges acquired."

    while true; do
        display_menu
        read -p "Enter your choice: " choice
        case "$choice" in
            1) take_backup ;;
            2) restore_backup ;;
            3) cleanup_old_backups ;;
            0) echo "Exiting. Goodbye!"; exit 0 ;;
            *) echo "Invalid choice. Please enter 1, 2, 3, or 0." ;;
        esac
    done
}

# --- Execute Main Loop ---
main_loop

