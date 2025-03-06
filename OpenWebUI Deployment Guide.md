# Open WebUI Setup Implementation Guide

This guide provides technical details for implementing the `openwebui-setup.sh` script, including component structure, dialog library usage, configuration handling, and core functionality.

## Script Structure

The setup script should follow a modular architecture:

```
openwebui-setup.sh                  # Main script
├── lib/                            # Library functions
│   ├── ui.sh                       # Dialog UI functions
│   ├── config.sh                   # Configuration handling
│   ├── system.sh                   # System checks and operations
│   ├── docker.sh                   # Docker operations
│   └── templates.sh                # Template files
└── templates/                      # Template files
    ├── docker-compose.yml.template # Docker Compose template
    └── env.template                # Environment file template
```

### Core Components

1. **Main Script**: Handles argument parsing, script flow, and component coordination
2. **UI Library**: Manages dialog-based user interface
3. **Configuration Library**: Handles settings storage and retrieval
4. **System Library**: Performs system checks and operations
5. **Docker Library**: Manages Docker-related operations
6. **Templates**: Contains templates for generated files

## Dialog UI Implementation

The script uses the `dialog` utility to create a Text User Interface (TUI). Here's a sample implementation of key UI functions:

```bash
# Display message box
show_message() {
    local title="$1"
    local message="$2"
    dialog --backtitle "Open WebUI Setup" --title "$title" --msgbox "$message" 10 60
}

# Display yes/no dialog
confirm_dialog() {
    local title="$1"
    local message="$2"
    dialog --backtitle "Open WebUI Setup" --title "$title" --yesno "$message" 10 60
    return $?
}

# Display input dialog
input_dialog() {
    local title="$1"
    local message="$2"
    local default="$3"
    local result
    result=$(dialog --backtitle "Open WebUI Setup" --title "$title" --inputbox "$message" 10 60 "$default" 3>&1 1>&2 2>&3)
    echo "$result"
}

# Display password dialog (masked input)
password_dialog() {
    local title="$1"
    local message="$2"
    local result
    result=$(dialog --backtitle "Open WebUI Setup" --title "$title" --passwordbox "$message" 10 60 3>&1 1>&2 2>&3)
    echo "$result"
}

# Display checklist dialog
checklist_dialog() {
    local title="$1"
    local message="$2"
    shift 2
    local options=("$@")
    local result
    result=$(dialog --backtitle "Open WebUI Setup" --title "$title" --checklist "$message" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)
    echo "$result"
}

# Display radiolist dialog
radiolist_dialog() {
    local title="$1"
    local message="$2"
    shift 2
    local options=("$@")
    local result
    result=$(dialog --backtitle "Open WebUI Setup" --title "$title" --radiolist "$message" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)
    echo "$result"
}

# Display progress bar
progress_dialog() {
    local title="$1"
    local message="$2"
    local total="$3"
    exec 3>&1
    dialog --backtitle "Open WebUI Setup" --title "$title" --gauge "$message" 10 60 0 0 >&3
}

# Update progress bar
update_progress() {
    local percent="$1"
    local message="$2"
    echo "XXX"
    echo "$percent"
    echo "$message"
    echo "XXX"
}
```

## Configuration Handling

Configuration options should be stored in a structured way:

```bash
# Initialize config with defaults
init_config() {
    # Basic settings
    CONFIG["webui_port"]="3000"
    CONFIG["enable_auth"]="true"
    CONFIG["enable_signup"]="false"
    CONFIG["allow_all_models"]="false"
    
    # API settings
    CONFIG["enable_ollama"]="true"
    CONFIG["enable_openai"]="false"
    CONFIG["openai_api_key"]=""
    
    # Feature settings
    CONFIG["enable_web_search"]="true"
    CONFIG["enable_speech_to_text"]="true"
    CONFIG["enable_text_to_speech"]="true"
    CONFIG["enable_pipelines"]="true"
    CONFIG["enable_image_generation"]="false"
    CONFIG["enable_rag"]="true"
    CONFIG["enable_channels"]="true"
    
    # And so on...
}

# Save configuration to file
save_config() {
    local config_file="$1"
    
    echo "# Open WebUI Configuration" > "$config_file"
    echo "# Generated on $(date)" >> "$config_file"
    echo "" >> "$config_file"
    
    echo "[Basic]" >> "$config_file"
    echo "webui_port=${CONFIG["webui_port"]}" >> "$config_file"
    echo "enable_auth=${CONFIG["enable_auth"]}" >> "$config_file"
    echo "enable_signup=${CONFIG["enable_signup"]}" >> "$config_file"
    echo "allow_all_models=${CONFIG["allow_all_models"]}" >> "$config_file"
    
    echo "" >> "$config_file"
    echo "[API]" >> "$config_file"
    echo "enable_ollama=${CONFIG["enable_ollama"]}" >> "$config_file"
    echo "enable_openai=${CONFIG["enable_openai"]}" >> "$config_file"
    echo "openai_api_key=${CONFIG["openai_api_key"]}" >> "$config_file"
    
    # And so on...
}

# Load configuration from file
load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        echo "Configuration file not found: $config_file"
        return 1
    fi
    
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key == \#* ]] || [[ -z "$key" ]] && continue
        
        # Remove section headers
        [[ $key == \[*\] ]] && continue
        
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # Store in config array
        CONFIG["$key"]="$value"
    done < "$config_file"
}
```

## Docker Compose Generation

Generate the Docker Compose file based on user configuration:

```bash
generate_docker_compose() {
    local output_file="$1"
    local template_file="templates/docker-compose.yml.template"
    
    # Start with basic services
    cat > "$output_file" <<EOL
version: '3'

services:
EOL
    
    # Add Ollama if enabled
    if [[ "${CONFIG["enable_ollama"]}" == "true" ]]; then
        cat >> "$output_file" <<EOL
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    volumes:
      - ollama:/root/.ollama
    restart: unless-stopped
EOL
    fi
    
    # Add Open WebUI
    cat >> "$output_file" <<EOL
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
EOL
    
    # Add dependencies
    if [[ "${CONFIG["enable_ollama"]}" == "true" ]]; then
        echo "    depends_on:" >> "$output_file"
        echo "      - ollama" >> "$output_file"
    fi
    
    # Add Pipelines if enabled
    if [[ "${CONFIG["enable_pipelines"]}" == "true" ]]; then
        echo "      - redis" >> "$output_file"
    fi
    
    # Add port mapping
    cat >> "$output_file" <<EOL
    ports:
      - "\${OPEN_WEBUI_PORT:-${CONFIG["webui_port"]}}:8080"
    volumes:
      - open-webui:/app/backend/data
    env_file:
      - .env
EOL
    
    # Add Ollama URL if Ollama is enabled
    if [[ "${CONFIG["enable_ollama"]}" == "true" ]]; then
        cat >> "$output_file" <<EOL
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
EOL
    fi
    
    # Add resource limits
    if [[ -n "${CONFIG["memory_limit"]}" ]]; then
        echo "    mem_limit: ${CONFIG["memory_limit"]}" >> "$output_file"
    fi
    
    if [[ -n "${CONFIG["cpu_limit"]}" ]]; then
        echo "    cpus: ${CONFIG["cpu_limit"]}" >> "$output_file"
    fi
    
    echo "    restart: unless-stopped" >> "$output_file"
    
    # Add Pipelines if enabled
    if [[ "${CONFIG["enable_pipelines"]}" == "true" ]]; then
        cat >> "$output_file" <<EOL
    
  pipelines:
    image: ghcr.io/open-webui/pipelines:main
    container_name: pipelines
    ports:
      - "${CONFIG["pipelines_port"]}:9099"
    volumes:
      - pipelines:/app/pipelines
    restart: unless-stopped
    depends_on:
      - open-webui
      
  redis:
    image: redis:alpine
    container_name: redis
    volumes:
      - redis-data:/data
    restart: unless-stopped
EOL
    fi
    
    # Add volumes
    cat >> "$output_file" <<EOL

volumes:
EOL
    
    if [[ "${CONFIG["enable_ollama"]}" == "true" ]]; then
        echo "  ollama:" >> "$output_file"
    fi
    
    echo "  open-webui:" >> "$output_file"
    
    if [[ "${CONFIG["enable_pipelines"]}" == "true" ]]; then
        echo "  pipelines:" >> "$output_file"
        echo "  redis-data:" >> "$output_file"
    fi
}
```

## Environment File Generation

Generate the `.env` file based on user configuration:

```bash
generate_env_file() {
    local output_file="$1"
    
    cat > "$output_file" <<EOL
# Open WebUI Environment Configuration
# Generated by openwebui-setup.sh

# Basic Configuration
OPEN_WEBUI_PORT=${CONFIG["webui_port"]}
WEBUI_AUTH=${CONFIG["enable_auth"]}
ENABLE_SIGNUP=${CONFIG["enable_signup"]}
BYPASS_MODEL_ACCESS_CONTROL=${CONFIG["allow_all_models"]}
EOL

    # Add API configuration
    cat >> "$output_file" <<EOL

# API Configuration
EOL

    if [[ "${CONFIG["enable_ollama"]}" == "true" ]]; then
        echo "OLLAMA_BASE_URL=http://ollama:11434" >> "$output_file"
    fi
    
    if [[ "${CONFIG["enable_openai"]}" == "true" ]]; then
        echo "OPENAI_API_BASE_URL=https://api.openai.com/v1" >> "$output_file"
        echo "OPENAI_API_KEY=${CONFIG["openai_api_key"]}" >> "$output_file"
    fi
    
    # Add feature configuration
    cat >> "$output_file" <<EOL

# Feature Configuration
EOL

    if [[ "${CONFIG["enable_web_search"]}" == "true" ]]; then
        echo "ENABLE_RAG_WEB_SEARCH=true" >> "$output_file"
        echo "RAG_WEB_SEARCH_ENGINE=${CONFIG["web_search_engine"]}" >> "$output_file"
        echo "RAG_WEB_SEARCH_RESULT_COUNT=${CONFIG["search_result_count"]}" >> "$output_file"
    fi
    
    # Add STT configuration
    if [[ "${CONFIG["enable_speech_to_text"]}" == "true" ]]; then
        cat >> "$output_file" <<EOL

# Speech-to-Text Configuration
EOL
        if [[ "${CONFIG["stt_engine"]}" == "local_whisper" ]]; then
            echo "WHISPER_MODEL=${CONFIG["whisper_model"]}" >> "$output_file"
        elif [[ "${CONFIG["stt_engine"]}" == "openai" ]]; then
            echo "AUDIO_STT_ENGINE=openai" >> "$output_file"
            echo "AUDIO_STT_MODEL=${CONFIG["stt_model"]}" >> "$output_file"
        fi
    fi
    
    # Add TTS configuration
    if [[ "${CONFIG["enable_text_to_speech"]}" == "true" ]]; then
        cat >> "$output_file" <<EOL

# Text-to-Speech Configuration
EOL
        echo "AUDIO_TTS_ENGINE=${CONFIG["tts_engine"]}" >> "$output_file"
        echo "AUDIO_TTS_MODEL=${CONFIG["tts_model"]}" >> "$output_file"
        echo "AUDIO_TTS_VOICE=${CONFIG["tts_voice"]}" >> "$output_file"
    fi
    
    # Add Pipeline configuration
    if [[ "${CONFIG["enable_pipelines"]}" == "true" ]]; then
        cat >> "$output_file" <<EOL

# Pipeline Configuration
ENABLE_WEBSOCKET_SUPPORT=true
WEBSOCKET_MANAGER=redis
WEBSOCKET_REDIS_URL=redis://redis:6379/0
EOL
    fi
}
```

## System Checks

Perform prerequisite checks:

```bash
check_prerequisites() {
    local missing=()
    
    # Check for dialog
    if ! command -v dialog &> /dev/null; then
        missing+=("dialog")
    fi
    
    # Check for git
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    else
        # Check if Docker daemon is running
        if ! docker info &> /dev/null; then
            show_message "Error" "Docker is installed but the Docker daemon is not running. Please start Docker and try again."
            return 1
        fi
    fi
    
    # Check for Docker Compose
    if ! docker compose version &> /dev/null; then
        if ! docker-compose --version &> /dev/null; then
            missing+=("docker-compose")
        fi
    fi
    
    # If any dependencies are missing, show message
    if [[ ${#missing[@]} -gt 0 ]]; then
        local message="The following required dependencies are missing:\n\n"
        for dep in "${missing[@]}"; do
            message+="- $dep\n"
        done
        message+="\nWould you like to install them now?"
        
        confirm_dialog "Missing Dependencies" "$message"
        if [[ $? -eq 0 ]]; then
            install_missing_dependencies "${missing[@]}"
        else
            show_message "Error" "Cannot continue without required dependencies."
            return 1
        fi
    fi
    
    return 0
}

install_missing_dependencies() {
    local deps=("$@")
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_INSTALL="apt-get install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        show_message "Error" "Unsupported package manager. Please install dependencies manually."
        return 1
    fi
    
    # Update package lists
    eval "sudo $PKG_MANAGER update"
    
    # Install each dependency
    for dep in "${deps[@]}"; do
        case $dep in
            docker)
                install_docker
                ;;
            docker-compose)
                install_docker_compose
                ;;
            *)
                eval "sudo $PKG_INSTALL $dep"
                ;;
        esac
    done
}

install_docker() {
    show_message "Installing Docker" "Installing Docker. This may take a few minutes..."
    
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        # Install prerequisites
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        
        # Add Docker repository
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        
        # Update package lists
        sudo apt-get update
        
        # Install Docker
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        # Add Docker repository
        sudo $PKG_MANAGER -y install yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        
        # Install Docker
        sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
        # Install Docker
        sudo pacman -S --noconfirm docker
    fi
    
    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to Docker group
    sudo usermod -aG docker "$(whoami)"
    
    show_message "Docker Installed" "Docker has been installed. You may need to log out and log back in for group changes to take effect."
}

install_docker_compose() {
    show_message "Installing Docker Compose" "Installing Docker Compose. This may take a few minutes..."
    
    # Download Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.18.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Apply executable permissions
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    show_message "Docker Compose Installed" "Docker Compose has been installed successfully."
}
```

## Deployment Logic

Deploy Open WebUI:

```bash
deploy_open_webui() {
    # Create Docker Compose file
    generate_docker_compose "docker-compose.yml"
    
    # Create .env file
    generate_env_file ".env"
    
    # Show deployment progress
    show_message "Deployment" "Starting Open WebUI deployment.\n\nThis may take a few minutes as Docker images are pulled and containers are started."
    
    # Pull images
    (
        exec 3>&1
        progress=$(dialog --backtitle "Open WebUI Setup" --title "Deployment" --gauge "Pulling Docker images..." 10 60 0 >&3)
        
        # Pull images
        docker-compose pull 2>&1 | while read -r line; do
            # Update progress
            progress=$((progress + 5))
            if [[ $progress -gt 100 ]]; then
                progress=100
            fi
            
            # Update progress bar
            echo "XXX"
            echo "$progress"
            echo "Pulling Docker images...\n\n$line"
            echo "XXX"
        done > >(cat >&3)
    )
    
    # Start containers
    show_message "Starting Containers" "Starting Docker containers..."
    docker-compose up -d
    
    # Check if deployment was successful
    if [[ $? -eq 0 ]]; then
        local server_ip
        server_ip=$(hostname -I | awk '{print $1}')
        
        show_message "Deployment Complete" "Open WebUI has been successfully deployed!\n\nAccess your Open WebUI installation at:\n\nhttp://$server_ip:${CONFIG["webui_port"]}\n\nThe first account you create will be the administrator."
    else
        show_message "Deployment Failed" "There was an error deploying Open WebUI. Please check the logs for more information."
    fi
}
```

## Main Script

The main script brings everything together:

```bash
#!/bin/bash

# Version information
VERSION="1.0.0"

# Initialize global variables
declare -A CONFIG

# Source library files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/docker