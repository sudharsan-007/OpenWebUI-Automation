#!/bin/bash

# OpenWebUI Deployment Script
# Author: DevOps Assistant
# Version: 1.1.0
# Description: Interactive script to deploy OpenWebUI with custom configurations

# Exit on error
set -e

# Set default values
REPO_URL="https://github.com/open-webui/open-webui.git"
INSTALL_DIR="$HOME/open-webui"
DATA_DIR="$HOME/.open-webui"
LOG_DIR="$HOME/.open-webui/logs"
DOCKER_COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
CONFIG_FILE="$HOME/.openwebui_config.json"
HOST_PORT="3000"
CONTAINER_NAME="open-webui"
OLLAMA_CONTAINER_NAME="ollama"
VERBOSE=false
NO_DIALOG=false
SETUP_OLLAMA=true

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to display banner
display_banner() {
  clear
  echo -e "${BLUE}"
  echo -e "╭──────────────────────────────────────────────────────╮"
  echo -e "│                                                      │"
  echo -e "│             ${BOLD}OpenWebUI Deployment Script${BLUE}              │"
  echo -e "│                                                      │"
  echo -e "│  A complete setup for deploying OpenWebUI on VPS     │"
  echo -e "│                                                      │"
  echo -e "╰──────────────────────────────────────────────────────╯"
  echo -e "${NC}"
  echo
}

# Function to display help message
display_help() {
  echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]"
  echo
  echo -e "${BOLD}Options:${NC}"
  echo -e "  -h, --help             Display this help message"
  echo -e "  -v, --verbose          Enable verbose output"
  echo -e "  -d, --dir DIR          Specify installation directory (default: $INSTALL_DIR)"
  echo -e "  -p, --port PORT        Specify host port (default: $HOST_PORT)"
  echo -e "  --no-dialog            Use basic terminal prompts instead of dialog"
  echo -e "  --no-ollama            Don't include Ollama in the setup (use existing Ollama)"
  echo -e "  -y, --yes              Skip all confirmations"
  echo
  echo -e "${BOLD}Example:${NC}"
  echo -e "  $0 --verbose --dir /opt/openwebui --port 8080"
  echo
  exit 0
}

# Function for logging
log() {
  local log_level="$1"
  local message="$2"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  case $log_level in
    "INFO")
      echo -e "${GREEN}[INFO]${NC} $message"
      ;;
    "SUCCESS")
      echo -e "${GREEN}[SUCCESS]${NC} $message"
      ;;
    "WARN")
      echo -e "${YELLOW}[WARN]${NC} $message"
      ;;
    "ERROR")
      echo -e "${RED}[ERROR]${NC} $message"
      ;;
    "DEBUG")
      if [[ "$VERBOSE" == true ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $message"
      fi
      ;;
  esac
  
  # Create log directory if it doesn't exist
  if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
  fi
  
  echo "[$timestamp] [$log_level] $message" >> "$LOG_DIR/deploy.log"
}

# Parse command line arguments
SKIP_CONFIRMATIONS=false
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      display_help
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -d|--dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    -p|--port)
      HOST_PORT="$2"
      shift 2
      ;;
    --no-dialog)
      NO_DIALOG=true
      shift
      ;;
    --no-ollama)
      SETUP_OLLAMA=false
      shift
      ;;
    -y|--yes)
      SKIP_CONFIRMATIONS=true
      shift
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      echo "Use --help to see available options."
      exit 1
      ;;
  esac
done

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to confirm actions with the user
confirm() {
  if [ "$SKIP_CONFIRMATIONS" = true ]; then
    return 0
  fi
  
  local message="$1"
  local default="${2:-n}"
  
  if [ "$default" = "y" ]; then
    prompt="${CYAN}$message${NC} [${BLUE}Y/n${NC}]: "
  else
    prompt="${CYAN}$message${NC} [${BLUE}y/N${NC}]: "
  fi
  
  read -p "$prompt" answer
  
  if [[ -z "$answer" ]]; then
    answer="$default"
  fi
  
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

# Function to check prerequisites
check_prerequisites() {
  log "INFO" "Checking prerequisites..."
  
  # Check system memory
  if command_exists free; then
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_total" -lt 4000 ]; then
      log "WARN" "System has less than 4GB RAM ($mem_total MB). This might affect performance."
    else
      log "INFO" "System memory: $mem_total MB"
    fi
  fi
  
  # Check disk space
  local disk_space=$(df -h . | awk 'NR==2 {print $4}')
  log "INFO" "Available disk space: $disk_space"
  
  local missing_tools=()
  
  # Check for required tools
  for tool in git curl docker jq; do
    if ! command_exists "$tool"; then
      missing_tools+=("$tool")
    fi
  done
  
  # Check Docker Compose
  if ! command_exists "docker-compose" && ! docker compose version >/dev/null 2>&1; then
    missing_tools+=("docker-compose")
  fi
  
  # Check for dialog if not in --no-dialog mode
  if [ "$NO_DIALOG" != true ] && ! command_exists "dialog"; then
    missing_tools+=("dialog")
  fi
  
  # If any tools are missing, provide installation instructions
  if [ ${#missing_tools[@]} -gt 0 ]; then
    log "WARN" "Missing required tools: ${missing_tools[*]}"
    echo -e "${YELLOW}The following tools need to be installed:${NC}"
    
    for tool in "${missing_tools[@]}"; do
      case "$tool" in
        git)
          echo -e "- ${BOLD}git${NC}: ${CYAN}sudo apt-get install -y git${NC}"
          ;;
        curl)
          echo -e "- ${BOLD}curl${NC}: ${CYAN}sudo apt-get install -y curl${NC}"
          ;;
        docker)
          echo -e "- ${BOLD}docker${NC}: ${CYAN}curl -fsSL https://get.docker.com | sh${NC}"
          ;;
        docker-compose)
          echo -e "- ${BOLD}docker-compose${NC}: ${CYAN}sudo apt-get install -y docker-compose-plugin${NC}"
          echo -e "  or for Docker Compose v2: ${CYAN}sudo apt-get install -y docker-compose-v2${NC}"
          ;;
        dialog)
          echo -e "- ${BOLD}dialog${NC}: ${CYAN}sudo apt-get install -y dialog${NC}"
          ;;
        jq)
          echo -e "- ${BOLD}jq${NC}: ${CYAN}sudo apt-get install -y jq${NC}"
          ;;
      esac
    done
    
    echo
    if confirm "Would you like the script to attempt to install these tools?" "y"; then
      log "INFO" "Attempting to install missing tools..."
      
      # Update package lists
      sudo apt-get update
      
      for tool in "${missing_tools[@]}"; do
        case "$tool" in
          git|curl|dialog|jq)
            sudo apt-get install -y "$tool"
            ;;
          docker)
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker "$USER"
            log "WARN" "You may need to log out and back in for docker group changes to take effect."
            ;;
          docker-compose)
            sudo apt-get install -y docker-compose-plugin || sudo apt-get install -y docker-compose
            ;;
        esac
      done
      
      # Check if all tools are now installed
      local still_missing=false
      for tool in "${missing_tools[@]}"; do
        if [[ "$tool" != "docker-compose" ]]; then
          if ! command_exists "$tool"; then
            still_missing=true
            log "ERROR" "Failed to install $tool"
          fi
        else
          # Special check for docker-compose
          if ! command_exists "docker-compose" && ! docker compose version >/dev/null 2>&1; then
            still_missing=true
            log "ERROR" "Failed to install docker-compose"
          fi
        fi
      done
      
      if [ "$still_missing" = true ]; then
        log "ERROR" "Some required tools could not be installed. Please install them manually and run the script again."
        exit 1
      fi
    else
      log "ERROR" "Please install the required tools and run the script again."
      exit 1
    fi
  else
    log "INFO" "All prerequisites satisfied."
  fi
  
  # Check Docker service status
  if command_exists systemctl && systemctl list-unit-files | grep -q docker.service; then
    if ! systemctl is-active --quiet docker; then
      log "WARN" "Docker service is not running."
      if confirm "Do you want to start the Docker service?" "y"; then
        sudo systemctl start docker
        if ! systemctl is-active --quiet docker; then
          log "ERROR" "Failed to start Docker service."
          exit 1
        fi
        log "SUCCESS" "Docker service started."
      else
        log "ERROR" "Docker service is required but not running."
        exit 1
      fi
    else
      log "INFO" "Docker service is running."
    fi
    
    # Check if current user is in the docker group
    if ! groups | grep -q docker; then
      log "WARN" "Current user is not in the docker group."
      if confirm "Do you want to add current user to the docker group?" "y"; then
        sudo usermod -aG docker $USER
        log "WARN" "You may need to log out and log back in for the changes to take effect."
        log "WARN" "Alternatively, you might need to run this script with sudo."
      fi
    else
      log "INFO" "Current user is in the docker group."
    fi
  fi
  
  # Check if dialog is functional
  if [ "$NO_DIALOG" != true ] && command_exists dialog; then
    if ! dialog --version > /dev/null 2>&1; then
      log "WARN" "Dialog is installed but not functioning properly. Switching to basic prompts."
      NO_DIALOG=true
    fi
  fi
}

# Function to create a temporary file
create_temp_file() {
  mktemp 2>/dev/null || mktemp -t 'openwebui-temp'
}

# Function to prompt for configuration using dialog
dialog_prompt() {
  local title="$1"
  local message="$2"
  local default="$3"
  local temp_file=$(create_temp_file)
  
  dialog --backtitle "OpenWebUI Deployment" --title "$title" --inputbox "$message" 8 60 "$default" 2> "$temp_file"
  local retval=$?
  
  if [ $retval -ne 0 ]; then
    rm -f "$temp_file"
    return 1
  fi
  
  local result=$(cat "$temp_file")
  rm -f "$temp_file"
  echo "$result"
  return 0
}

# Function to prompt for configuration using terminal
terminal_prompt() {
  local message="$1"
  local default="$2"
  
  if [ -n "$default" ]; then
    echo -e "${CYAN}$message${NC} [${BLUE}$default${NC}]: "
  else
    echo -e "${CYAN}$message${NC}: "
  fi
  
  read -r input
  echo "${input:-$default}"
}

# Function to prompt for yes/no using dialog
dialog_yesno() {
  local title="$1"
  local message="$2"
  local default="$3"
  
  if [ "$default" = "y" ]; then
    dialog --backtitle "OpenWebUI Deployment" --title "$title" --defaultno --yesno "$message" 8 60
    return $?
  else
    dialog --backtitle "OpenWebUI Deployment" --title "$title" --yesno "$message" 8 60
    return $?
  fi
}

# Function to prompt for yes/no using terminal
terminal_yesno() {
  local message="$1"
  local default="$2"
  
  if [ "$default" = "y" ]; then
    prompt="${CYAN}$message${NC} [${BLUE}Y/n${NC}]: "
  else
    prompt="${CYAN}$message${NC} [${BLUE}y/N${NC}]: "
  fi
  
  read -p "$prompt" answer
  
  if [[ -z "$answer" ]]; then
    answer="$default"
  fi
  
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

# Function to show a checklist using dialog
dialog_checklist() {
  local title="$1"
  local message="$2"
  shift 2
  local items=("$@")
  local temp_file=$(create_temp_file)
  
  dialog --backtitle "OpenWebUI Deployment" --title "$title" --checklist "$message" 20 78 14 "${items[@]}" 2> "$temp_file"
  local retval=$?
  
  if [ $retval -ne 0 ]; then
    rm -f "$temp_file"
    return 1
  fi
  
  local result=$(cat "$temp_file")
  rm -f "$temp_file"
  echo "$result"
  return 0
}

# Function to show a checklist using terminal
terminal_checklist() {
  local message="$1"
  shift
  local items=("$@")
  local selected=()
  
  echo -e "${CYAN}$message${NC}"
  echo -e "${YELLOW}Enter the numbers of options to select (comma or space separated):${NC}"
  
  for ((i=0; i<${#items[@]}; i+=3)); do
    tag="${items[i]}"
    item="${items[i+1]}"
    status="${items[i+2]}"
    
    if [ "$status" = "on" ]; then
      default="[X]"
    else
      default="[ ]"
    fi
    
    echo -e "${BLUE}$((i/3+1))${NC}. $default ${BOLD}$tag${NC} - $item"
  done
  
  echo
  read -r selections
  
  # Convert input to array
  IFS=', ' read -r -a selection_array <<< "$selections"
  
  # Process selections
  for selection in "${selection_array[@]}"; do
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
      continue
    fi
    
    index=$((selection-1))
    if [ "$index" -ge 0 ] && [ "$index" -lt $((${#items[@]}/3)) ]; then
      tag="${items[index*3]}"
      selected+=("$tag")
    fi
  done
  # Add default selected items if no selection made
  if [ ${#selected[@]} -eq 0 ]; then
    for ((i=0; i<${#items[@]}; i+=3)); do
      status="${items[i+2]}"
      if [ "$status" = "on" ]; then
        tag="${items[i]}"
        selected+=("$tag")
      fi
    done
  fi
  
  # Return the selected tags in the format dialog would
  echo "${selected[*]}"
  return 0
}

# Function to prompt for configuration
prompt_config() {
  local config="{}"
  
  display_banner
  log "INFO" "Starting configuration process..."
  
  # Host port configuration
  if [ "$NO_DIALOG" = true ]; then
    host_port=$(terminal_prompt "Enter the host port for OpenWebUI" "$HOST_PORT")
  else
    host_port=$(dialog_prompt "Host Port" "Enter the host port for OpenWebUI (default: $HOST_PORT)" "$HOST_PORT")
    # If dialog was cancelled, use default
    if [ $? -ne 0 ]; then
      host_port="$HOST_PORT"
    fi
  fi
  
  # If empty, use default
  host_port="${host_port:-$HOST_PORT}"
  config=$(echo "$config" | jq --arg port "$host_port" '. + {host_port: $port}')
  log "DEBUG" "Set host port to $host_port"
  
  # Ollama configuration
  if [ "$SETUP_OLLAMA" = true ]; then
    config=$(echo "$config" | jq '. + {setup_ollama: true}')
    
    if [ "$NO_DIALOG" = true ]; then
      ollama_port=$(terminal_prompt "Enter the port for Ollama API" "11434")
    else
      ollama_port=$(dialog_prompt "Ollama Port" "Enter the port for Ollama API (default: 11434)" "11434")
      # If dialog was cancelled, use default
      if [ $? -ne 0 ]; then
        ollama_port="11434"
      fi
    fi
    
    config=$(echo "$config" | jq --arg port "$ollama_port" '. + {ollama_port: $port}')
    log "DEBUG" "Set Ollama port to $ollama_port"
  else
    config=$(echo "$config" | jq '. + {setup_ollama: false}')
    
    if [ "$NO_DIALOG" = true ]; then
      ollama_url=$(terminal_prompt "Enter the URL for external Ollama API" "http://localhost:11434")
    else
      ollama_url=$(dialog_prompt "Ollama URL" "Enter the URL for external Ollama API (default: http://localhost:11434)" "http://localhost:11434")
      # If dialog was cancelled, use default
      if [ $? -ne 0 ]; then
        ollama_url="http://localhost:11434"
      fi
    fi
    
    config=$(echo "$config" | jq --arg url "$ollama_url" '. + {ollama_url: $url}')
    log "DEBUG" "Set external Ollama URL to $ollama_url"
  fi
  
  # API configuration options
  api_items=(
    "openai" "OpenAI API (GPT models)" "off"
    "claude" "Anthropic Claude API" "off"
    "openrouter" "OpenRouter API (multiple models)" "off"
    "azure" "Azure OpenAI API" "off"
    "google" "Google AI / Gemini API" "off"
  )
  
  if [ "$NO_DIALOG" = true ]; then
    echo -e "\n${BOLD}API Configuration${NC}"
    selected_apis=$(terminal_checklist "Select the APIs you want to enable:" "${api_items[@]}")
  else
    selected_apis=$(dialog_checklist "API Configuration" "Select the APIs you want to enable:" "${api_items[@]}")
    if [ $? -ne 0 ]; then
      log "WARN" "API selection cancelled, using default (Ollama only)"
      selected_apis=""
    fi
  fi
  
  # Store selected APIs in config
  api_config="{}"
  # Always enable Ollama
  api_config=$(echo "$api_config" | jq '. + {"ollama": true}')
  
  for api in $selected_apis; do
    api=$(echo "$api" | tr -d '"') # Remove quotes if present
    api_config=$(echo "$api_config" | jq --arg api "$api" '. + {($api): true}')
    
    # Prompt for API keys for selected APIs
    api_name=$(echo "$api" | tr '[:lower:]' '[:upper:]')
    
    if [ "$NO_DIALOG" = true ]; then
      api_key=$(terminal_prompt "Enter your $api_name API key")
    else
      api_key=$(dialog_prompt "$api_name API Key" "Enter your $api_name API key:" "")
      # If dialog was cancelled, set empty key
      if [ $? -ne 0 ]; then
        api_key=""
      fi
    fi
    
    api_config=$(echo "$api_config" | jq --arg api "$api" --arg key "$api_key" '. + {($api + "_key"): $key}')
    log "DEBUG" "Added $api_name API configuration"
  done
  
  # Store API config
  config=$(echo "$config" | jq --argjson api_config "$api_config" '. + {api: $api_config}')
  
  # Feature configuration options
  feature_items=(
    "websearch" "Web search capability" "on"
    "rag" "Retrieval Augmented Generation (RAG)" "on"
    "tts" "Text-to-Speech capability" "on"
    "stt" "Speech-to-Text capability" "on"
    "channels" "Channel feature (chat rooms)" "off"
    "functions" "Custom functions support" "off"
    "tools" "Enable tools integration" "on"
    "image_gen" "Image generation capability" "off"
  )
  
  if [ "$NO_DIALOG" = true ]; then
    echo -e "\n${BOLD}Feature Configuration${NC}"
    selected_features=$(terminal_checklist "Select the features you want to enable:" "${feature_items[@]}")
  else
    selected_features=$(dialog_checklist "Feature Configuration" "Select the features you want to enable:" "${feature_items[@]}")
    if [ $? -ne 0 ]; then
      log "WARN" "Feature selection cancelled, using defaults"
      selected_features="websearch rag tts stt tools"
    fi
  fi
  
  # Store selected features in config
  feature_config="{}"
  for feature in $selected_features; do
    feature=$(echo "$feature" | tr -d '"') # Remove quotes if present
    feature_config=$(echo "$feature_config" | jq --arg feature "$feature" '. + {($feature): true}')
    log "DEBUG" "Enabled feature: $feature"
  done
  
  # Store feature config
  config=$(echo "$config" | jq --argjson feature_config "$feature_config" '. + {features: $feature_config}')
  
  # Security and access configuration
  if [ "$NO_DIALOG" = true ]; then
    if terminal_yesno "Enable authentication (recommended)?" "y"; then
      enable_auth="true"
    else
      enable_auth="false"
    fi
    
    if terminal_yesno "Allow all users to access all models? (By default, only admin can access all models)" "n"; then
      all_models_access="true"
    else
      all_models_access="false"
    fi
  else
    if dialog_yesno "Authentication" "Enable authentication? (Recommended)" "y"; then
      enable_auth="true"
    else
      enable_auth="false"
    fi
    
    if dialog_yesno "Model Access" "Allow all users to access all models? (By default, only admin can access all models)" "n"; then
      all_models_access="true"
    else
      all_models_access="false"
    fi
  fi
  
  # Store security config
  security_config="{}"
  security_config=$(echo "$security_config" | jq --arg auth "$enable_auth" '. + {auth_enabled: $auth}')
  security_config=$(echo "$security_config" | jq --arg access "$all_models_access" '. + {all_models_access: $access}')
  config=$(echo "$config" | jq --argjson security_config "$security_config" '. + {security: $security_config}')
  
  # Save configuration
  echo "$config" > "$CONFIG_FILE"
  log "INFO" "Configuration saved to $CONFIG_FILE"
  
  return 0
}

# Function to generate Docker Compose file
generate_docker_compose() {
  local config=$(cat "$CONFIG_FILE")
  local host_port=$(echo "$config" | jq -r '.host_port')
  local setup_ollama=$(echo "$config" | jq -r '.setup_ollama')
  local ollama_port=$(echo "$config" | jq -r '.ollama_port // "11434"')
  local ollama_url=$(echo "$config" | jq -r '.ollama_url // "http://host.docker.internal:11434"')
  local api_config=$(echo "$config" | jq '.api')
  local feature_config=$(echo "$config" | jq '.features')
  local security_config=$(echo "$config" | jq '.security')
  
  log "INFO" "Generating Docker Compose file..."
  
  # Start with base Docker Compose
  cat > "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
version: '3'

services:
EOF

  # Add Ollama service if needed
  if [ "$setup_ollama" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ${OLLAMA_CONTAINER_NAME}
    volumes:
      - ollama:/root/.ollama
    ports:
      - "${ollama_port}:11434"
    restart: unless-stopped
    tty: true
    pull_policy: always

EOF
    ollama_base_url="http://ollama:11434"
  else
    ollama_base_url="$ollama_url"
  fi

  # Add OpenWebUI service
  cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${host_port}:8080"
    volumes:
      - open-webui:/app/backend/data
EOF

  # Add dependency on Ollama if needed
  if [ "$setup_ollama" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
    depends_on:
      - ollama
EOF
  fi

  # Add environment variables
  cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
    environment:
      - OLLAMA_BASE_URL=${ollama_base_url}
EOF
  
  # Add environment variables based on configuration
  
  # API configurations
  if [ "$(echo "$api_config" | jq -r '.openai // false')" = "true" ]; then
    local openai_key=$(echo "$api_config" | jq -r '.openai_key // ""')
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - OPENAI_API_BASE_URL=https://api.openai.com/v1
      - OPENAI_API_KEY=${openai_key}
EOF
  fi
  
  # Feature configurations
  if [ "$(echo "$feature_config" | jq -r '.websearch // false')" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - ENABLE_RAG_WEB_SEARCH=True
EOF
  fi
  
  if [ "$(echo "$feature_config" | jq -r '.rag // false')" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - RAG_EMBEDDING_ENGINE=ollama
EOF
  fi

  if [ "$(echo "$feature_config" | jq -r '.stt // false')" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - WHISPER_MODEL=base
EOF
  fi
  
  if [ "$(echo "$feature_config" | jq -r '.channels // false')" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - ENABLE_CHANNELS=True
EOF
  fi
  
  if [ "$(echo "$feature_config" | jq -r '.image_gen // false')" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - ENABLE_IMAGE_GENERATION=True
EOF
  fi
  
  # Security configurations
  if [ "$(echo "$security_config" | jq -r '.auth_enabled // "true"')" = "false" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - WEBUI_AUTH=False
EOF
  fi
  
  if [ "$(echo "$security_config" | jq -r '.all_models_access // "false"')" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - BYPASS_MODEL_ACCESS_CONTROL=True
EOF
  fi
  
  # Add common environment variables
  cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
      - HOST=0.0.0.0
    extra_hosts:
      - host.docker.internal:host-gateway

volumes:
EOF

  # Add volumes
  if [ "$setup_ollama" = "true" ]; then
    cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
  ollama:
EOF
  fi

  cat >> "$INSTALL_DIR/$DOCKER_COMPOSE_FILE" <<EOF
  open-webui:
EOF
  
  log "INFO" "Docker Compose file generated at $INSTALL_DIR/$DOCKER_COMPOSE_FILE"
  
  # Create .env file
  cat > "$INSTALL_DIR/$ENV_FILE" <<EOF
# OpenWebUI Environment Configuration
# Generated by OpenWebUI Deployment Script

# General Settings
HOST=0.0.0.0
PORT=8080
WEBUI_NAME="Open WebUI"
EOF
  
  log "INFO" "Environment file generated at $INSTALL_DIR/$ENV_FILE"
  
  return 0
}

# Function to deploy OpenWebUI
deploy_openwebui() {
  log "INFO" "Starting deployment..."
  
  # Create install directory if it doesn't exist
  if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
    log "INFO" "Created installation directory: $INSTALL_DIR"
  fi
  
  # Clone the repository if needed
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "INFO" "Cloning OpenWebUI repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    if [ $? -ne 0 ]; then
      log "ERROR" "Failed to clone repository"
      return 1
    fi
    log "INFO" "Repository cloned successfully"
  else
    log "INFO" "Repository already exists, updating..."
    (cd "$INSTALL_DIR" && git pull)
    if [ $? -ne 0 ]; then
      log "ERROR" "Failed to update repository"
      return 1
    fi
    log "INFO" "Repository updated successfully"
  fi
  
  # Generate Docker Compose and .env files
  generate_docker_compose
  if [ $? -ne 0 ]; then
    log "ERROR" "Failed to generate configuration files"
    return 1
  fi
  
  # Check if containers are already running
  if docker ps | grep -q "$CONTAINER_NAME"; then
    log "WARN" "OpenWebUI container is already running."
    if confirm "Do you want to stop and remove existing containers?" "y"; then
      (cd "$INSTALL_DIR" && docker-compose down || docker compose down)
    else
      log "ERROR" "Cannot start new containers while existing ones are running."
      return 1
    fi
  fi
  
  # Ask user if they want to start the deployment
  if ! confirm "Start the deployment now?" "y"; then
    log "INFO" "Deployment prepared but not started"
    log "INFO" "You can start it later with: cd $INSTALL_DIR && docker-compose up -d"
    return 0
  fi
  
  # Start the deployment
  log "INFO" "Starting Docker containers..."
  (cd "$INSTALL_DIR" && docker-compose up -d || docker compose up -d)
  if [ $? -ne 0 ]; then
    log "ERROR" "Failed to start Docker containers"
    return 1
  fi
  
  log "INFO" "Deployment completed successfully!"
  
  # Get the actual server IP or hostname
  local server_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  
  # Display success message
  echo
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}      OpenWebUI Deployment Complete!     ${NC}"
  echo -e "${GREEN}=========================================${NC}"
  echo
  echo -e "${BOLD}Your OpenWebUI instance is now running!${NC}"
  echo -e "Access it at: ${BLUE}http://$server_ip:$host_port${NC}"
  echo
  echo -e "${YELLOW}Initial Login Information:${NC}"
  echo -e "- The first account you create will be the admin account"
  echo -e "- Be sure to set a strong password"
  echo
  echo -e "${CYAN}Useful commands:${NC}"
  echo -e "- View logs: ${BOLD}docker logs $CONTAINER_NAME${NC}"
  echo -e "- Stop service: ${BOLD}cd $INSTALL_DIR && docker-compose down${NC}"
  echo -e "- Start service: ${BOLD}cd $INSTALL_DIR && docker-compose up -d${NC}"
  echo -e "- Restart service: ${BOLD}docker restart $CONTAINER_NAME${NC}"

  if [ "$SETUP_OLLAMA" = true ]; then
    echo
    echo -e "${YELLOW}Ollama Information:${NC}"
    echo -e "- Ollama is running at: ${BLUE}http://$server_ip:$ollama_port${NC}"
    echo -e "- View logs: ${BOLD}docker logs $OLLAMA_CONTAINER_NAME${NC}"
    echo -e "- To pull models: ${BOLD}curl http://$server_ip:$ollama_port/api/pull -d '{\"model\":\"MODEL_NAME\"}'${NC}"
  fi
  
  echo
  echo -e "${GREEN}Happy using OpenWebUI!${NC}"
  
  return 0
}

# Main function
main() {
  # Display banner
  display_banner
  
  # Check prerequisites
  check_prerequisites
  
  # Check if we're using basic terminal prompts
  if [ "$NO_DIALOG" != true ] && ! command_exists dialog; then
    log "WARN" "Dialog is not installed, using basic terminal prompts"
    NO_DIALOG=true
  fi
  
  # Prompt for configuration
  prompt_config
  
  # Deploy OpenWebUI
  deploy_openwebui
  
  return $?
}

# Run the main function
main
exit $?