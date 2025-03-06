#!/bin/bash

# OpenWebUI Automated Deployment Script
# This script automates the deployment of OpenWebUI with a user-friendly TUI interface

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")
VERBOSE=false
CONFIG_ONLY=false
REPO_URL="https://github.com/open-webui/open-webui.git"
REPO_DIR="open-webui"
ENV_FILE=".env"
DOCKER_COMPOSE_FILE="docker-compose.yml"
LOG_FILE="openwebui-deploy.log"

# Function to display help message
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Automated deployment script for OpenWebUI on cloud servers.

Options:
  -h, --help         Show this help message and exit
  -v, --verbose      Enable verbose output
  -c, --config-only  Only generate configuration files without starting services
  --version          Show version information

Example:
  $SCRIPT_NAME --verbose

This script will:
1. Check for prerequisites (Docker, Docker Compose, Dialog, Git, etc.)
2. Clone the OpenWebUI repository
3. Guide you through configuration using a TUI
4. Create necessary configuration files
5. Deploy OpenWebUI using Docker Compose

EOF
}

# Function to show version
show_version() {
    echo "$SCRIPT_NAME version $VERSION"
}

# Function to log messages
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$VERBOSE" == "true" || "$level" != "DEBUG" ]]; then
        case "$level" in
            "ERROR")   echo -e "\e[31m[$level] $message\e[0m" ;;
            "WARNING") echo -e "\e[33m[$level] $message\e[0m" ;;
            "INFO")    echo -e "\e[32m[$level] $message\e[0m" ;;
            "DEBUG")   echo -e "\e[36m[$level] $message\e[0m" ;;
            *)         echo "[$level] $message" ;;
        esac
    fi
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help) show_help; exit 0 ;;
            -v|--verbose) VERBOSE=true ;;
            -c|--config-only) CONFIG_ONLY=true ;;
            --version) show_version; exit 0 ;;
            *) log "ERROR" "Unknown parameter: $1"; show_help; exit 1 ;;
        esac
        shift
    done
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install a package based on the detected OS
install_package() {
    local package=$1
    
    if command_exists apt-get; then
        log "INFO" "Installing $package using apt-get..."
        sudo apt-get update
        sudo apt-get install -y "$package"
    elif command_exists yum; then
        log "INFO" "Installing $package using yum..."
        sudo yum install -y "$package"
    elif command_exists dnf; then
        log "INFO" "Installing $package using dnf..."
        sudo dnf install -y "$package"
    elif command_exists apk; then
        log "INFO" "Installing $package using apk..."
        sudo apk add --no-cache "$package"
    elif command_exists pacman; then
        log "INFO" "Installing $package using pacman..."
        sudo pacman -S --noconfirm "$package"
    else
        log "ERROR" "Could not determine package manager. Please install $package manually."
        return 1
    fi
    
    return $?
}

# Check for prerequisites and install if missing
check_prerequisites() {
    local missing_prereqs=()
    
    log "INFO" "Checking prerequisites..."
    
    # Check for dialog
    if ! command_exists dialog; then
        log "WARNING" "Dialog is not installed. Required for TUI."
        missing_prereqs+=("dialog")
    fi
    
    # Check for git
    if ! command_exists git; then
        log "WARNING" "Git is not installed. Required for cloning repository."
        missing_prereqs+=("git")
    fi
    
    # Check for docker
    if ! command_exists docker; then
        log "WARNING" "Docker is not installed. Required for containerization."
        missing_prereqs+=("docker")
    fi
    
    # Check for docker compose
    if ! command_exists docker-compose && ! command_exists "docker" compose; then
        log "WARNING" "Docker Compose is not installed. Required for service orchestration."
        missing_prereqs+=("docker-compose")
    fi
    
    # Check for curl
    if ! command_exists curl; then
        log "WARNING" "Curl is not installed. Required for API requests."
        missing_prereqs+=("curl")
    fi
    
    # Install missing prerequisites
    if [[ ${#missing_prereqs[@]} -gt 0 ]]; then
        log "INFO" "Installing missing prerequisites: ${missing_prereqs[*]}"
        
        for package in "${missing_prereqs[@]}"; do
            if [[ "$package" == "docker" ]]; then
                # Docker requires special installation
                log "INFO" "Docker requires special installation. Please refer to the Docker documentation."
                log "INFO" "You can try running: curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh"
                read -p "Would you like to automatically install Docker? (y/n): " install_docker
                if [[ "$install_docker" == "y" || "$install_docker" == "Y" ]]; then
                    curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
                    sudo usermod -aG docker $USER
                    log "INFO" "Docker installed. You may need to log out and back in for group changes to take effect."
                else
                    log "ERROR" "Docker is required. Please install it manually."
                    exit 1
                fi
            elif [[ "$package" == "docker-compose" ]]; then
                # Check if Docker Compose plugin is available
                if command_exists docker && docker compose version >/dev/null 2>&1; then
                    log "INFO" "Docker Compose plugin is available."
                else
                    log "INFO" "Installing Docker Compose..."
                    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                    sudo chmod +x /usr/local/bin/docker-compose
                fi
            else
                install_package "$package" || {
                    log "ERROR" "Failed to install $package. Please install it manually."
                    exit 1
                }
            fi
        done
    else
        log "INFO" "All prerequisites are installed."
    fi
}

# Clone the OpenWebUI repository
clone_repository() {
    if [[ -d "$REPO_DIR" ]]; then
        log "INFO" "Repository directory already exists. Checking if it's a git repository..."
        
        if [[ -d "$REPO_DIR/.git" ]]; then
            log "INFO" "Updating existing repository..."
            (cd "$REPO_DIR" && git pull)
        else
            log "WARNING" "Directory exists but is not a git repository. Backing up and cloning fresh..."
            mv "$REPO_DIR" "${REPO_DIR}_backup_$(date +%s)"
            git clone "$REPO_URL" "$REPO_DIR"
        fi
    else
        log "INFO" "Cloning OpenWebUI repository..."
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    
    # Check if clone was successful
    if [[ $? -ne 0 || ! -d "$REPO_DIR" ]]; then
        log "ERROR" "Failed to clone repository."
        exit 1
    fi
    
    log "INFO" "Repository cloned/updated successfully."
}

# Configuration using dialog TUI
configure_openwebui() {
    # Check if dialog is available
    if ! command_exists dialog; then
        log "ERROR" "Dialog is required for configuration. Please install it and try again."
        exit 1
    }
    
    # Initialize configuration variables with defaults
    local open_ai_api_enabled="off"
    local claude_api_enabled="off"
    local openrouter_api_enabled="off"
    local open_ai_api_key=""
    local claude_api_key=""
    local openrouter_api_key=""
    local web_search_enabled="off"
    local rag_enabled="off"
    local speech_to_text_enabled="off"
    local authentication_enabled="on"
    local all_models_access="off"
    local server_port="3000"
    local enable_websocket="off"
    local enable_channels="off"
    local enable_functions="off"
    local enable_image_generation="off"
    
    # Welcome screen
    dialog --backtitle "OpenWebUI Deployment" \
           --title "Welcome" \
           --msgbox "Welcome to the OpenWebUI Deployment Script!\n\nThis wizard will guide you through the configuration of your OpenWebUI instance.\n\nUse TAB or arrow keys to navigate, SPACE to select options, and ENTER to confirm." \
           15 60
    
    # Main configuration screen with checklist for features
    features=$(dialog --backtitle "OpenWebUI Deployment" \
                      --title "Feature Selection" \
                      --checklist "Select the features you want to enable:" \
                      20 70 12 \
                      "web_search" "Enable Web Search" "$web_search_enabled" \
                      "rag" "Enable RAG (Retrieval Augmented Generation)" "$rag_enabled" \
                      "speech_to_text" "Enable Speech-to-Text" "$speech_to_text_enabled" \
                      "authentication" "Enable Authentication" "$authentication_enabled" \
                      "all_models_access" "Allow All Users to Access All Models" "$all_models_access" \
                      "websocket" "Enable WebSocket Support" "$enable_websocket" \
                      "channels" "Enable Channels Feature" "$enable_channels" \
                      "functions" "Enable Functions Support" "$enable_functions" \
                      "image_generation" "Enable Image Generation" "$enable_image_generation" \
                      2>&1 >/dev/tty)
    
    # Check for cancel
    if [[ $? -ne 0 ]]; then
        log "INFO" "Configuration cancelled by user."
        exit 0
    fi
    
    # Update feature flags based on selection
    web_search_enabled=$(echo "$features" | grep -q "web_search" && echo "on" || echo "off")
    rag_enabled=$(echo "$features" | grep -q "rag" && echo "on" || echo "off")
    speech_to_text_enabled=$(echo "$features" | grep -q "speech_to_text" && echo "on" || echo "off")
    authentication_enabled=$(echo "$features" | grep -q "authentication" && echo "on" || echo "off")
    all_models_access=$(echo "$features" | grep -q "all_models_access" && echo "on" || echo "off")
    enable_websocket=$(echo "$features" | grep -q "websocket" && echo "on" || echo "off")
    enable_channels=$(echo "$features" | grep -q "channels" && echo "on" || echo "off")
    enable_functions=$(echo "$features" | grep -q "functions" && echo "on" || echo "off")
    enable_image_generation=$(echo "$features" | grep -q "image_generation" && echo "on" || echo "off")
    
    # API Selection
    apis=$(dialog --backtitle "OpenWebUI Deployment" \
                   --title "API Selection" \
                   --checklist "Select the APIs you want to enable:" \
                   15 60 3 \
                   "openai" "OpenAI API" "$open_ai_api_enabled" \
                   "claude" "Claude API" "$claude_api_enabled" \
                   "openrouter" "OpenRouter API" "$openrouter_api_enabled" \
                   2>&1 >/dev/tty)
    
    # Check for cancel
    if [[ $? -ne 0 ]]; then
        log "INFO" "Configuration cancelled by user."
        exit 0
    fi
    
    # Update API flags based on selection
    open_ai_api_enabled=$(echo "$apis" | grep -q "openai" && echo "on" || echo "off")
    claude_api_enabled=$(echo "$apis" | grep -q "claude" && echo "on" || echo "off")
    openrouter_api_enabled=$(echo "$apis" | grep -q "openrouter" && echo "on" || echo "off")
    
    # Collect API keys if enabled
    if [[ "$open_ai_api_enabled" == "on" ]]; then
        open_ai_api_key=$(dialog --backtitle "OpenWebUI Deployment" \
                                 --title "OpenAI API Key" \
                                 --inputbox "Enter your OpenAI API Key:" \
                                 8 60 \
                                 2>&1 >/dev/tty)
        
        # Check for cancel
        if [[ $? -ne 0 ]]; then
            log "INFO" "Configuration cancelled by user."
            exit 0
        fi
    fi
    
    if [[ "$claude_api_enabled" == "on" ]]; then
        claude_api_key=$(dialog --backtitle "OpenWebUI Deployment" \
                                --title "Claude API Key" \
                                --inputbox "Enter your Claude API Key:" \
                                8 60 \
                                2>&1 >/dev/tty)
        
        # Check for cancel
        if [[ $? -ne 0 ]]; then
            log "INFO" "Configuration cancelled by user."
            exit 0
        fi
    fi
    
    if [[ "$openrouter_api_enabled" == "on" ]]; then
        openrouter_api_key=$(dialog --backtitle "OpenWebUI Deployment" \
                                    --title "OpenRouter API Key" \
                                    --inputbox "Enter your OpenRouter API Key:" \
                                    8 60 \
                                    2>&1 >/dev/tty)
        
        # Check for cancel
        if [[ $? -ne 0 ]]; then
            log "INFO" "Configuration cancelled by user."
            exit 0
        fi
    fi
    
    # Server configuration
    server_port=$(dialog --backtitle "OpenWebUI Deployment" \
                         --title "Server Configuration" \
                         --inputbox "Enter the port to run OpenWebUI on:" \
                         8 60 \
                         "$server_port" \
                         2>&1 >/dev/tty)
    
    # Check for cancel
    if [[ $? -ne 0 ]]; then
        log "INFO" "Configuration cancelled by user."
        exit 0
    fi
    
    # Confirm configuration
    dialog --backtitle "OpenWebUI Deployment" \
           --title "Confirm Configuration" \
           --yesno "Please confirm your configuration:\n\n\
Features:\n\
- Web Search: $web_search_enabled\n\
- RAG: $rag_enabled\n\
- Speech-to-Text: $speech_to_text_enabled\n\
- Authentication: $authentication_enabled\n\
- All Models Access: $all_models_access\n\
- WebSocket Support: $enable_websocket\n\
- Channels Feature: $enable_channels\n\
- Functions Support: $enable_functions\n\
- Image Generation: $enable_image_generation\n\n\
APIs:\n\
- OpenAI API: $open_ai_api_enabled\n\
- Claude API: $claude_api_enabled\n\
- OpenRouter API: $openrouter_api_enabled\n\n\
Server:\n\
- Port: $server_port\n\n\
Proceed with this configuration?" \
           20 70
    
    # Check for cancel or no
    if [[ $? -ne 0 ]]; then
        log "INFO" "Configuration cancelled by user."
        exit 0
    fi
    
    # Create configuration files
    cd "$REPO_DIR" || {
        log "ERROR" "Failed to navigate to repository directory."
        exit 1
    }
    
    # Create .env file
    log "INFO" "Creating .env file..."
    cat > "$ENV_FILE" << EOF
# OpenWebUI Configuration
# Generated by OpenWebUI Deployment Script

# Server configuration
OPEN_WEBUI_PORT=$server_port

# API configuration
EOF
    
    if [[ "$open_ai_api_enabled" == "on" ]]; then
        cat >> "$ENV_FILE" << EOF
OPENAI_API_KEY=$open_ai_api_key
OPENAI_API_BASE_URL=https://api.openai.com/v1
EOF
    fi
    
    if [[ "$claude_api_enabled" == "on" ]]; then
        cat >> "$ENV_FILE" << EOF
# Claude API configuration - To be configured in the Admin Panel
# CLAUDE_API_KEY=$claude_api_key
EOF
    fi
    
    if [[ "$openrouter_api_enabled" == "on" ]]; then
        cat >> "$ENV_FILE" << EOF
# OpenRouter API configuration - To be configured in the Admin Panel
# OPENROUTER_API_KEY=$openrouter_api_key
EOF
    fi
    
    # Feature configuration
    cat >> "$ENV_FILE" << EOF

# Feature configuration
ENABLE_RAG_WEB_SEARCH=$([ "$web_search_enabled" == "on" ] && echo "True" || echo "False")
RAG_EMBEDDING_ENGINE=$([ "$rag_enabled" == "on" ] && echo "ollama" || echo "")
WEBUI_AUTH=$([ "$authentication_enabled" == "on" ] && echo "True" || echo "False")
BYPASS_MODEL_ACCESS_CONTROL=$([ "$all_models_access" == "on" ] && echo "True" || echo "False")
ENABLE_WEBSOCKET_SUPPORT=$([ "$enable_websocket" == "on" ] && echo "True" || echo "False")
ENABLE_CHANNELS=$([ "$enable_channels" == "on" ] && echo "True" || echo "False")
ENABLE_IMAGE_GENERATION=$([ "$enable_image_generation" == "on" ] && echo "True" || echo "False")

# Generate a random secret key for security
WEBUI_SECRET_KEY=$(openssl rand -hex 32)

# Privacy settings
SCARF_NO_ANALYTICS=true
DO_NOT_TRACK=true
ANONYMIZED_TELEMETRY=false
EOF
    
    # Create or update docker-compose.yml
    log "INFO" "Creating docker-compose.yml file..."
    
    # Handle the Redis service template separately
    redis_service=""
    if [ "$enable_websocket" == "on" ]; then
        redis_service=$(cat << 'REDIS_SERVICE'
  redis:
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
REDIS_SERVICE
)
    fi
    
    # Handle volume configuration
    redis_volume=""
    if [ "$enable_websocket" == "on" ]; then
        redis_volume="  redis-data: {}"
    fi
    
    # Create the docker-compose.yml file
    cat > "$DOCKER_COMPOSE_FILE" << EOF
services:
  ollama:
    volumes:
      - ollama:/root/.ollama
    container_name: ollama
    pull_policy: always
    tty: true
    restart: unless-stopped
    image: ollama/ollama:latest

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    volumes:
      - open-webui:/app/backend/data
    depends_on:
      - ollama
    ports:
      - \${OPEN_WEBUI_PORT-3000}:8080
    environment:
      - 'OLLAMA_BASE_URL=http://ollama:11434'
$([ "$open_ai_api_enabled" == "on" ] && echo "      - 'OPENAI_API_KEY=\${OPENAI_API_KEY}'")
$([ "$open_ai_api_enabled" == "on" ] && echo "      - 'OPENAI_API_BASE_URL=\${OPENAI_API_BASE_URL}'")
$([ "$web_search_enabled" == "on" ] && echo "      - 'ENABLE_RAG_WEB_SEARCH=\${ENABLE_RAG_WEB_SEARCH}'")
$([ "$rag_enabled" == "on" ] && echo "      - 'RAG_EMBEDDING_ENGINE=\${RAG_EMBEDDING_ENGINE}'")
$([ "$authentication_enabled" == "off" ] && echo "      - 'WEBUI_AUTH=\${WEBUI_AUTH}'")
$([ "$all_models_access" == "on" ] && echo "      - 'BYPASS_MODEL_ACCESS_CONTROL=\${BYPASS_MODEL_ACCESS_CONTROL}'")
$([ "$enable_websocket" == "on" ] && echo "      - 'ENABLE_WEBSOCKET_SUPPORT=\${ENABLE_WEBSOCKET_SUPPORT}'")
$([ "$enable_channels" == "on" ] && echo "      - 'ENABLE_CHANNELS=\${ENABLE_CHANNELS}'")
$([ "$enable_image_generation" == "on" ] && echo "      - 'ENABLE_IMAGE_GENERATION=\${ENABLE_IMAGE_GENERATION}'")
      - 'WEBUI_SECRET_KEY=\${WEBUI_SECRET_KEY}'
      - 'SCARF_NO_ANALYTICS=\${SCARF_NO_ANALYTICS}'
      - 'DO_NOT_TRACK=\${DO_NOT_TRACK}'
      - 'ANONYMIZED_TELEMETRY=\${ANONYMIZED_TELEMETRY}'
    extra_hosts:
      - host.docker.internal:host-gateway
    restart: unless-stopped
$redis_service

volumes:
  ollama: {}
  open-webui: {}
$redis_volume
EOF
    
    log "INFO" "Configuration files created successfully."
    
    # Show completion message
    dialog --backtitle "OpenWebUI Deployment" \
           --title "Configuration Complete" \
           --msgbox "Configuration completed successfully!\n\nYou can now start OpenWebUI using Docker Compose.\n\nCommand: docker-compose up -d\n\nOpenWebUI will be available at: http://localhost:$server_port" \
           12 60
}

# Start OpenWebUI using docker-compose
start_openwebui() {
    cd "$REPO_DIR" || {
        log "ERROR" "Failed to navigate to repository directory."
        exit 1
    }
    
    log "INFO" "Starting OpenWebUI services..."
    
    # Check if we should use docker compose or docker-compose
    if command_exists "docker" && docker compose version >/dev/null 2>&1; then
        docker compose up -d
    elif command_exists docker-compose; then
        docker-compose up -d
    else
        log "ERROR" "Docker Compose not found. Please install it and try again."
        exit 1
    fi
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to start OpenWebUI services."
        exit 1
    fi
    
    log "INFO" "OpenWebUI services started successfully."
    
    # Get server port from .env file
    local port
    if [[ -f "$ENV_FILE" ]]; then
        port=$(grep OPEN_WEBUI_PORT "$ENV_FILE" | cut -d= -f2)
    else
        port="3000"
    fi
    
    log "INFO" "OpenWebUI is now available at: http://localhost:$port"
    log "INFO" "Initial login will create an admin account."
    
    # Attempt to get the server's public IP
    public_ip=$(curl -s ifconfig.me)
    if [[ -n "$public_ip" ]]; then
        log "INFO" "If this is a cloud server, you can also access OpenWebUI at: http://$public_ip:$port"
    fi
}

# Main function
main() {
    # Parse command line arguments
    parse_args "$@"
    
    log "INFO" "Starting OpenWebUI deployment script v$VERSION"
    
    # Check and install prerequisites
    check_prerequisites
    
    # Clone repository
    clone_repository
    
    # Configure OpenWebUI
    configure_openwebui
    
    # Start OpenWebUI if not config-only mode
    if [[ "$CONFIG_ONLY" != "true" ]]; then
        # Ask user if they want to start OpenWebUI now
        dialog --backtitle "OpenWebUI Deployment" \
               --title "Start OpenWebUI" \
               --yesno "Would you like to start OpenWebUI now?" \
               7 60
        
        if [[ $? -eq 0 ]]; then
            start_openwebui
        else
            log "INFO" "OpenWebUI not started. You can start it manually later with: cd $REPO_DIR && docker-compose up -d"
        fi
    else
        log "INFO" "Config-only mode. OpenWebUI not started."
        log "INFO" "You can start OpenWebUI manually with: cd $REPO_DIR && docker-compose up -d"
    fi
    
    log "INFO" "OpenWebUI deployment script completed successfully."
}

# Execute main function with all arguments
main "$@"