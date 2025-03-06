#!/bin/bash

# OpenWebUI Installation Script
# This script automates the installation and configuration of OpenWebUI
# Author: DevOps Assistant
# Version: 1.0

set -e

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables with defaults
REPO_URL="https://github.com/open-webui/open-webui.git"
OPENWEBUI_DIR="$HOME/open-webui"
CONTAINER_NAME="open-webui"
OLLAMA_CONTAINER_NAME="ollama"
WEBUI_PORT=3000
INSTALL_DIR="$(pwd)/open-webui-installation"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"
LOG_FILE="$INSTALL_DIR/install.log"
VERBOSE=false
SKIP_CONFIRMATIONS=false

# Features and configurations
ENABLE_OPENAI=false
ENABLE_WEBSEARCH=false
ENABLE_RAG=false
ENABLE_STT=false
ENABLE_TTS=false
ENABLE_CHANNELS=false
ENABLE_AUTHENTICATION=true
ENABLE_ALL_MODELS_ACCESS=false

# API keys
OPENAI_API_KEY=""
OPENAI_API_BASE_URL="https://api.openai.com/v1"

# Function to display the help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

This script automates the installation and configuration of OpenWebUI.

Options:
  -h, --help             Show this help message
  -v, --verbose          Enable verbose output
  -y, --yes              Skip all confirmations
  -p, --port PORT        Specify the port (default: 3000)
  -d, --directory DIR    Specify installation directory (default: ./open-webui-installation)

Examples:
  $0                    # Standard installation with prompts
  $0 --yes --port 8080  # Install with port 8080 and skip confirmations
  $0 --verbose          # Verbose installation

EOF
    exit 0
}

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo -e "$timestamp [$level] $message" >> "$LOG_FILE"
    
    if [ "$VERBOSE" = true ] || [ "$level" != "DEBUG" ]; then
        case $level in
            "INFO")
                echo -e "${BLUE}[INFO]${NC} $message"
                ;;
            "SUCCESS")
                echo -e "${GREEN}[SUCCESS]${NC} $message"
                ;;
            "WARNING")
                echo -e "${YELLOW}[WARNING]${NC} $message"
                ;;
            "ERROR")
                echo -e "${RED}[ERROR]${NC} $message"
                ;;
            *)
                echo -e "[DEBUG] $message"
                ;;
        esac
    fi
}

# Function to confirm actions with the user
confirm() {
    if [ "$SKIP_CONFIRMATIONS" = true ]; then
        return 0
    fi
    
    local message=$1
    local default=${2:-"n"}
    
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -p "$message $prompt " response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if a command exists
check_command() {
    local cmd=$1
    local package=$2
    local install_cmd=$3
    
    if ! command -v "$cmd" &> /dev/null; then
        log "WARNING" "$cmd is not installed."
        if [ -n "$package" ] && [ -n "$install_cmd" ] && confirm "Do you want to install $package?"; then
            log "INFO" "Installing $package..."
            $install_cmd
            if ! command -v "$cmd" &> /dev/null; then
                log "ERROR" "Failed to install $cmd. Please install it manually."
                return 1
            fi
            log "SUCCESS" "$package installed successfully."
        else
            log "ERROR" "$cmd is required but not installed. Please install it manually."
            return 1
        fi
    else
        log "INFO" "$cmd is already installed. Version: $(($cmd --version 2>/dev/null || echo 'unknown') | head -n1)"
    fi
    return 0
}

# Function to check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check system memory
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_total" -lt 4000 ]; then
        log "WARNING" "System has less than 4GB RAM ($mem_total MB). This might affect performance."
    else
        log "INFO" "System memory: $mem_total MB"
    fi
    
    # Check disk space
    local disk_space=$(df -h . | awk 'NR==2 {print $4}')
    log "INFO" "Available disk space: $disk_space"
    
    # Check for required commands
    check_command "git" "git" "sudo apt-get update && sudo apt-get install -y git" || return 1
    check_command "docker" "docker" "curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh" || return 1
    check_command "docker-compose" "docker-compose" "sudo apt-get update && sudo apt-get install -y docker-compose-plugin" || return 1
    check_command "dialog" "dialog" "sudo apt-get update && sudo apt-get install -y dialog" || return 1
    check_command "curl" "curl" "sudo apt-get update && sudo apt-get install -y curl" || return 1
    
    # Check Docker service status
    if ! systemctl is-active --quiet docker; then
        log "WARNING" "Docker service is not running."
        if confirm "Do you want to start the Docker service?"; then
            sudo systemctl start docker
            if ! systemctl is-active --quiet docker; then
                log "ERROR" "Failed to start Docker service."
                return 1
            fi
            log "SUCCESS" "Docker service started."
        else
            log "ERROR" "Docker service is required but not running."
            return 1
        fi
    else
        log "INFO" "Docker service is running."
    fi
    
    # Check if current user is in the docker group
    if ! groups | grep -q docker; then
        log "WARNING" "Current user is not in the docker group."
        if confirm "Do you want to add current user to the docker group?"; then
            sudo usermod -aG docker $USER
            log "WARNING" "You may need to log out and log back in for the changes to take effect."
            log "WARNING" "Alternatively, you might need to run this script with sudo."
        fi
    else
        log "INFO" "Current user is in the docker group."
    fi
    
    return 0
}

# Function to configure OpenWebUI settings using dialog
configure_openwebui() {
    log "INFO" "Starting configuration..."
    
    # Create temporary files for dialog output
    features_file=$(mktemp)
    api_config_file=$(mktemp)
    port_file=$(mktemp)
    
    # Configure features using checklist
    dialog --backtitle "OpenWebUI Setup" \
           --title "Feature Configuration" \
           --checklist "Select features to enable:" 0 0 0 \
           "openai" "Enable OpenAI API integration" $([ "$ENABLE_OPENAI" = true ] && echo "on" || echo "off") \
           "websearch" "Enable Web Search capabilities" $([ "$ENABLE_WEBSEARCH" = true ] && echo "on" || echo "off") \
           "rag" "Enable Retrieval Augmented Generation (RAG)" $([ "$ENABLE_RAG" = true ] && echo "on" || echo "off") \
           "stt" "Enable Speech-to-Text" $([ "$ENABLE_STT" = true ] && echo "on" || echo "off") \
           "tts" "Enable Text-to-Speech" $([ "$ENABLE_TTS" = true ] && echo "on" || echo "off") \
           "channels" "Enable Channels feature" $([ "$ENABLE_CHANNELS" = true ] && echo "on" || echo "off") \
           "authentication" "Enable User Authentication" $([ "$ENABLE_AUTHENTICATION" = true ] && echo "on" || echo "off") \
           "allmodels" "Allow all users to access all models" $([ "$ENABLE_ALL_MODELS_ACCESS" = true ] && echo "on" || echo "off") \
           2> "$features_file"
    
    # Process feature selections
    ENABLE_OPENAI=false
    ENABLE_WEBSEARCH=false
    ENABLE_RAG=false
    ENABLE_STT=false
    ENABLE_TTS=false
    ENABLE_CHANNELS=false
    ENABLE_AUTHENTICATION=true
    ENABLE_ALL_MODELS_ACCESS=false
    
    for feature in $(cat "$features_file"); do
        feature=$(echo $feature | tr -d '"')
        case $feature in
            "openai")
                ENABLE_OPENAI=true
                ;;
            "websearch")
                ENABLE_WEBSEARCH=true
                ;;
            "rag")
                ENABLE_RAG=true
                ;;
            "stt")
                ENABLE_STT=true
                ;;
            "tts")
                ENABLE_TTS=true
                ;;
            "channels")
                ENABLE_CHANNELS=true
                ;;
            "authentication")
                ENABLE_AUTHENTICATION=true
                ;;
            "allmodels")
                ENABLE_ALL_MODELS_ACCESS=true
                ;;
        esac
    done
    
    # Configure port
    dialog --backtitle "OpenWebUI Setup" \
           --title "Port Configuration" \
           --inputbox "Enter the port for OpenWebUI:" 8 40 "$WEBUI_PORT" \
           2> "$port_file"
    
    WEBUI_PORT=$(cat "$port_file")
    
    # Configure API keys if enabled
    if [ "$ENABLE_OPENAI" = true ]; then
        # OpenAI API configuration
        dialog --backtitle "OpenWebUI Setup" \
               --title "OpenAI API Configuration" \
               --form "Enter your OpenAI API details:" 12 60 0 \
               "API Key:" 1 1 "$OPENAI_API_KEY" 1 15 40 0 \
               "API Base URL:" 2 1 "$OPENAI_API_BASE_URL" 2 15 40 0 \
               2> "$api_config_file"
        
        # Reading the form output
        IFS=$'\n' read -d '' -r -a api_lines < "$api_config_file"
        OPENAI_API_KEY="${api_lines[0]}"
        OPENAI_API_BASE_URL="${api_lines[1]:-https://api.openai.com/v1}"
    fi
    
    # Clean up temp files
    rm -f "$features_file" "$api_config_file" "$port_file"
    
    # Display configuration summary
    dialog --backtitle "OpenWebUI Setup" \
           --title "Configuration Summary" \
           --msgbox "Port: $WEBUI_PORT\n\nFeatures Enabled:\nOpenAI API: $([ "$ENABLE_OPENAI" = true ] && echo "Yes" || echo "No")\nWeb Search: $([ "$ENABLE_WEBSEARCH" = true ] && echo "Yes" || echo "No")\nRAG: $([ "$ENABLE_RAG" = true ] && echo "Yes" || echo "No")\nSpeech-to-Text: $([ "$ENABLE_STT" = true ] && echo "Yes" || echo "No")\nText-to-Speech: $([ "$ENABLE_TTS" = true ] && echo "Yes" || echo "No")\nChannels: $([ "$ENABLE_CHANNELS" = true ] && echo "Yes" || echo "No")\nAuthentication: $([ "$ENABLE_AUTHENTICATION" = true ] && echo "Yes" || echo "No")\nAll Models Access: $([ "$ENABLE_ALL_MODELS_ACCESS" = true ] && echo "Yes" || echo "No")" 16 60
    
    log "INFO" "Configuration completed."
    return 0
}

# Function to generate docker-compose.yml
generate_docker_compose() {
    log "INFO" "Generating docker-compose.yml..."
    
    mkdir -p "$INSTALL_DIR"
    
    cat > "$COMPOSE_FILE" << EOL
version: '3'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ${OLLAMA_CONTAINER_NAME}
    volumes:
      - ollama:/root/.ollama
    restart: unless-stopped
    tty: true
    pull_policy: always

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${CONTAINER_NAME}
    volumes:
      - open-webui:/app/backend/data
    depends_on:
      - ollama
    ports:
      - "${WEBUI_PORT}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
EOL

    # Add selected features to the docker-compose file
    if [ "$ENABLE_OPENAI" = true ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - OPENAI_API_BASE_URL=${OPENAI_API_BASE_URL}
EOL
    fi
    
    if [ "$ENABLE_WEBSEARCH" = true ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - ENABLE_RAG_WEB_SEARCH=True
EOL
    fi
    
    if [ "$ENABLE_RAG" = true ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - RAG_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
EOL
    fi
    
    if [ "$ENABLE_STT" = true ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - WHISPER_MODEL=base
EOL
    fi
    
    if [ "$ENABLE_CHANNELS" = true ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - ENABLE_CHANNELS=True
EOL
    fi
    
    if [ "$ENABLE_AUTHENTICATION" = false ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - WEBUI_AUTH=False
EOL
    fi
    
    if [ "$ENABLE_ALL_MODELS_ACCESS" = true ]; then
        cat >> "$COMPOSE_FILE" << EOL
      - BYPASS_MODEL_ACCESS_CONTROL=True
EOL
    fi
    
    cat >> "$COMPOSE_FILE" << EOL
    extra_hosts:
      - host.docker.internal:host-gateway
    restart: unless-stopped

volumes:
  ollama: {}
  open-webui: {}
EOL
    
    log "SUCCESS" "docker-compose.yml generated at $COMPOSE_FILE"
    return 0
}

# Function to generate .env file
generate_env_file() {
    log "INFO" "Generating .env file..."
    
    cat > "$ENV_FILE" << EOL
# OpenWebUI configuration
WEBUI_PORT=${WEBUI_PORT}

# Ollama configuration
OLLAMA_BASE_URL=http://ollama:11434
EOL

    if [ "$ENABLE_OPENAI" = true ]; then
        cat >> "$ENV_FILE" << EOL

# OpenAI configuration
OPENAI_API_KEY=${OPENAI_API_KEY}
OPENAI_API_BASE_URL=${OPENAI_API_BASE_URL}
EOL
    fi
    
    log "SUCCESS" ".env file generated at $ENV_FILE"
    return 0
}

# Function to start OpenWebUI
start_openwebui() {
    log "INFO" "Starting OpenWebUI..."
    
    cd "$INSTALL_DIR"
    
    # Check if containers are already running
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log "WARNING" "OpenWebUI container is already running."
        if confirm "Do you want to stop and remove existing containers?"; then
            docker-compose down
        else
            log "ERROR" "Cannot start new containers while existing ones are running."
            return 1
        fi
    fi
    
    # Start containers
    log "INFO" "Starting Docker containers..."
    docker-compose up -d
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to start Docker containers."
        return 1
    fi
    
    log "SUCCESS" "OpenWebUI started successfully."
    log "INFO" "OpenWebUI is now running at http://localhost:$WEBUI_PORT"
    log "INFO" "First user to register will be the admin user"
    
    return 0
}

# Main script execution
main() {
    # Create log directory
    mkdir -p "$INSTALL_DIR"
    touch "$LOG_FILE"
    
    log "INFO" "Starting OpenWebUI installation..."
    
    # Display banner
    cat << EOF
${BLUE}
#########################################################
#                                                       #
#                OpenWebUI Installer                    #
#                                                       #
#########################################################
${NC}
This script will help you install and configure OpenWebUI.
Installation directory: ${INSTALL_DIR}
Log file: ${LOG_FILE}

EOF
    
    # Check requirements
    if ! check_requirements; then
        log "ERROR" "System requirements check failed. Please fix the issues and try again."
        exit 1
    fi
    
    # Configure OpenWebUI
    if ! configure_openwebui; then
        log "ERROR" "Configuration failed."
        exit 1
    fi
    
    # Generate configuration files
    if ! generate_docker_compose; then
        log "ERROR" "Failed to generate docker-compose.yml."
        exit 1
    fi
    
    if ! generate_env_file; then
        log "ERROR" "Failed to generate .env file."
        exit 1
    fi
    
    # Ask to start OpenWebUI
    if confirm "Do you want to start OpenWebUI now?"; then
        if ! start_openwebui; then
            log "ERROR" "Failed to start OpenWebUI."
            exit 1
        fi
    else
        log "INFO" "You can start OpenWebUI later by running the following command:"
        log "INFO" "cd $INSTALL_DIR && docker-compose up -d"
    fi
    
    log "SUCCESS" "Installation completed successfully."
    
    # Final instructions
    cat << EOF
${GREEN}
#########################################################
#                                                       #
#         OpenWebUI Installation Complete!              #
#                                                       #
#########################################################
${NC}

OpenWebUI can be accessed at: http://localhost:${WEBUI_PORT}

Important notes:
- The first user to register will be the admin user
- Installation directory: ${INSTALL_DIR}
- Configuration files:
  - Docker Compose: ${COMPOSE_FILE}
  - Environment file: ${ENV_FILE}
  - Log file: ${LOG_FILE}

To start/stop OpenWebUI:
  cd ${INSTALL_DIR}
  docker-compose up -d    # Start in background
  docker-compose down     # Stop containers
  
To view logs:
  cd ${INSTALL_DIR}
  docker-compose logs -f  # Follow logs
  
Thank you for installing OpenWebUI!

EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        -p|--port)
            WEBUI_PORT="$2"
            shift
            shift
            ;;
        -d|--directory)
            INSTALL_DIR="$2"
            COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
            ENV_FILE="$INSTALL_DIR/.env"
            LOG_FILE="$INSTALL_DIR/install.log"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Execute the main function
main