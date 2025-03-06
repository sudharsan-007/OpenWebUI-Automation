#!/bin/bash
#
# Open WebUI Deployment Script
# Version: 1.0.0
#
# This script automates the deployment of Open WebUI with Docker Compose,
# including configuration setup, dependency checks, and environment generation.
# 
# Usage: ./openwebui-deploy.sh [OPTIONS]
# Options:
#   --non-interactive       Run without interactive prompts (uses defaults or config file)
#   --config FILE           Specify a configuration file to use
#   --port PORT             Specify the web UI port (default: 3000)
#   --ollama-url URL        Specify Ollama URL (default: http://ollama:11434)
#   --no-ollama             Deploy without Ollama (use external Ollama instance)
#   --help                  Display this help message

# Strict mode
set -eo pipefail

# Script information
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration values
declare -A CONFIG
CONFIG_FILE="${SCRIPT_DIR}/openwebui-config.ini"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
NON_INTERACTIVE=false
SHOW_HELP=false

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Utility Functions
#######################################

# Log message to console with timestamp
log() {
    local level="$1"
    local message="$2"
    local color=""
    
    case "$level" in
        "INFO")
            color="$BLUE"
            ;;
        "SUCCESS")
            color="$GREEN"
            ;;
        "WARNING")
            color="$YELLOW"
            ;;
        "ERROR")
            color="$RED"
            ;;
        *)
            color="$NC"
            ;;
    esac
    
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${color}${level}${NC}: $message"
}

# Print error message and exit
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Print help message
show_help() {
    cat << EOF
Open WebUI Deployment Script v${SCRIPT_VERSION}

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --non-interactive       Run without interactive prompts (uses defaults or config file)
  --config FILE           Specify a configuration file to use
  --port PORT             Specify the web UI port (default: 3000)
  --ollama-url URL        Specify Ollama URL (default: http://ollama:11434)
  --no-ollama             Deploy without Ollama (use external Ollama instance)
  --help                  Display this help message

Examples:
  ${SCRIPT_NAME}                             Run interactive setup
  ${SCRIPT_NAME} --non-interactive           Deploy with default settings
  ${SCRIPT_NAME} --config my-config.ini      Use custom configuration file
  ${SCRIPT_NAME} --port 8080                 Deploy with port 8080

EOF
}

# Confirm prompt with yes/no
confirm() {
    local message="$1"
    local default="${2:-y}"
    
    if [ "$NON_INTERACTIVE" = true ]; then
        case "$default" in
            [Yy]* ) return 0 ;;
            * ) return 1 ;;
        esac
    fi
    
    local prompt
    
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    while true; do
        read -p "$message $prompt " response
        
        # Default if empty
        if [ -z "$response" ]; then
            response="$default"
        fi
        
        case "$response" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# Get user input with default value
get_input() {
    local message="$1"
    local default="$2"
    local variable="$3"
    local hide_input="${4:-false}"
    local result=""
    
    if [ "$NON_INTERACTIVE" = true ]; then
        # Use the current value or default
        result="${CONFIG[$variable]:-$default}"
    else
        local prompt
        
        if [ -n "$default" ]; then
            prompt="$message [$default]: "
        else
            prompt="$message: "
        fi
        
        if [ "$hide_input" = true ]; then
            read -s -p "$prompt" result
            echo "" # Add a newline after hidden input
        else
            read -p "$prompt" result
        fi
        
        # Use default if input is empty
        if [ -z "$result" ]; then
            result="$default"
        fi
    fi
    
    # Store result in configuration
    CONFIG["$variable"]="$result"
}

# Get yes/no input and convert to true/false
get_boolean_input() {
    local message="$1"
    local default="$2"
    local variable="$3"
    
    if [ "$NON_INTERACTIVE" = true ]; then
        return
    fi
    
    local default_text=""
    if [ "$default" = true ] || [ "$default" = "true" ]; then
        default_text="Y/n"
    else
        default_text="y/N"
    fi
    
    while true; do
        read -p "$message [$default_text]: " result
        
        # Use default if input is empty
        if [ -z "$result" ]; then
            if [ "$default" = true ] || [ "$default" = "true" ]; then
                CONFIG["$variable"]=true
            else
                CONFIG["$variable"]=false
            fi
            return
        fi
        
        case "$result" in
            [Yy]* )
                CONFIG["$variable"]=true
                return
                ;;
            [Nn]* )
                CONFIG["$variable"]=false
                return
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Display a spinner for commands that take time
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    # Return if running in non-interactive mode
    if [ "$NON_INTERACTIVE" = true ]; then
        wait $pid
        return $?
    fi
    
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    
    wait $pid
    return $?
}

# Run a command with a spinner
run_with_spinner() {
    local message="$1"
    shift
    
    echo -ne "$message... "
    
    # Run the command
    "$@" > /dev/null 2>&1 &
    
    # Display spinner
    spinner $!
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}Done${NC}"
    else
        echo -e "${RED}Failed${NC}"
        return $status
    fi
}

#######################################
# System Check Functions
#######################################

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check system requirements
check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check for Docker
    if ! command_exists docker; then
        log "ERROR" "Docker is not installed. Please install Docker before continuing."
        
        if confirm "Would you like to install Docker now?"; then
            install_docker
        else
            error_exit "Docker is required to continue."
        fi
    else
        log "INFO" "Docker is installed."
        
        # Check if Docker daemon is running
        if ! docker info > /dev/null 2>&1; then
            log "ERROR" "Docker daemon is not running."
            error_exit "Please start Docker daemon before continuing."
        fi
    fi
    
    # Check for Docker Compose
    if ! docker compose version > /dev/null 2>&1; then
        if ! command_exists docker-compose; then
            log "ERROR" "Docker Compose is not installed."
            
            if confirm "Would you like to install Docker Compose now?"; then
                install_docker_compose
            else
                error_exit "Docker Compose is required to continue."
            fi
        else
            log "INFO" "Using legacy docker-compose."
        fi
    else
        log "INFO" "Docker Compose is installed."
    fi
    
    # Check system resources
    check_system_resources
    
    log "SUCCESS" "System requirements met."
}

# Install Docker
install_docker() {
    log "INFO" "Installing Docker..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error_exit "Unsupported OS. Please install Docker manually and run this script again."
    fi
    
    case "$OS" in
        ubuntu|debian)
            run_with_spinner "Updating package lists" sudo apt-get update
            run_with_spinner "Installing prerequisites" sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Set up the stable repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            run_with_spinner "Updating package lists" sudo apt-get update
            run_with_spinner "Installing Docker" sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
            
        centos|rhel|fedora)
            run_with_spinner "Installing prerequisites" sudo yum install -y yum-utils
            run_with_spinner "Adding Docker repository" sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            run_with_spinner "Installing Docker" sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
            
        *)
            error_exit "Unsupported OS. Please install Docker manually and run this script again."
            ;;
    esac
    
    # Start and enable Docker service
    run_with_spinner "Starting Docker service" sudo systemctl start docker
    run_with_spinner "Enabling Docker service" sudo systemctl enable docker
    
    # Add current user to Docker group
    if ! groups | grep -q docker; then
        run_with_spinner "Adding user to Docker group" sudo usermod -aG docker "$USER"
        log "WARNING" "Please log out and log back in for Docker group changes to take effect."
    fi
    
    log "SUCCESS" "Docker installed successfully."
}

# Install Docker Compose
install_docker_compose() {
    log "INFO" "Installing Docker Compose..."
    
    # Get latest Docker Compose version
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    
    if [ -z "$COMPOSE_VERSION" ]; then
        COMPOSE_VERSION="v2.18.1"  # Fallback version
        log "WARNING" "Could not determine latest Docker Compose version. Using $COMPOSE_VERSION."
    fi
    
    # Download and install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Check if installation was successful
    if command_exists docker-compose; then
        log "SUCCESS" "Docker Compose installed successfully."
    else
        error_exit "Failed to install Docker Compose."
    fi
}

# Check system resources
check_system_resources() {
    log "INFO" "Checking system resources..."
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        log "WARNING" "Only $CPU_CORES CPU core(s) detected. Performance may be affected."
    else
        log "INFO" "CPU: $CPU_CORES cores (OK)"
    fi
    
    # Check available memory
    if command_exists free; then
        TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
        if [ "$TOTAL_MEM" -lt 2048 ]; then
            log "WARNING" "Only $TOTAL_MEM MB of RAM detected. Performance may be affected."
        else
            log "INFO" "Memory: $TOTAL_MEM MB (OK)"
        fi
    else
        log "WARNING" "Could not determine available memory."
    fi
    
    # Check available disk space
    DISK_SPACE=$(df -h . | awk 'NR==2 {print $4}')
    log "INFO" "Available disk space: $DISK_SPACE"
}

#######################################
# Configuration Functions
#######################################

# Initialize configuration with default values
init_config() {
    log "INFO" "Initializing configuration with defaults..."
    
    # Basic settings
    CONFIG["webui_port"]="3000"
    CONFIG["enable_auth"]="true"
    CONFIG["enable_signup"]="false"
    CONFIG["allow_all_models"]="false"
    CONFIG["secret_key"]=$(openssl rand -hex 32)
    
    # API settings
    CONFIG["enable_ollama"]="true"
    CONFIG["ollama_url"]="http://ollama:11434"
    
    # OpenAI API
    CONFIG["enable_openai"]="false"
    CONFIG["openai_api_key"]=""
    CONFIG["openai_base_url"]="https://api.openai.com/v1"
    
    # Claude API
    CONFIG["enable_claude"]="false"
    CONFIG["claude_api_key"]=""
    
    # OpenRouter API
    CONFIG["enable_openrouter"]="false"
    CONFIG["openrouter_api_key"]=""
    CONFIG["openrouter_base_url"]="https://openrouter.ai/api/v1"
    
    # Google Gemini API
    CONFIG["enable_gemini"]="false"
    CONFIG["gemini_api_key"]=""
    
    # Azure OpenAI API
    CONFIG["enable_azure_openai"]="false"
    CONFIG["azure_openai_api_key"]=""
    CONFIG["azure_openai_endpoint"]=""
    CONFIG["azure_deployment_name"]=""
    
    # Groq API
    CONFIG["enable_groq"]="false"
    CONFIG["groq_api_key"]=""
    
    # Custom API Endpoint
    CONFIG["enable_custom_api"]="false"
    CONFIG["custom_api_url"]=""
    
    # Feature settings
    CONFIG["enable_web_search"]="true"
    CONFIG["web_search_engine"]="duckduckgo"
    CONFIG["search_result_count"]="3"
    
    CONFIG["enable_speech_to_text"]="true"
    CONFIG["stt_engine"]="local_whisper"
    CONFIG["whisper_model"]="base"
    
    CONFIG["enable_text_to_speech"]="true"
    CONFIG["tts_engine"]="web_api"
    CONFIG["tts_voice"]="alloy"
    CONFIG["tts_model"]="tts-1"
    
    CONFIG["enable_pipelines"]="true"
    CONFIG["pipelines_port"]="9099"
    CONFIG["install_function_calling"]="true"
    CONFIG["install_rate_limiting"]="true"
    CONFIG["install_toxic_filter"]="true"
    CONFIG["install_libretranslate"]="false"
    CONFIG["install_langfuse"]="false"
    
    CONFIG["enable_image_generation"]="false"
    CONFIG["image_generation_engine"]="openai"
    CONFIG["image_model"]=""
    CONFIG["image_size"]="512x512"
    
    CONFIG["enable_rag"]="true"
    CONFIG["enable_channels"]="true"
    
    # System resources
    CONFIG["memory_limit"]="4G"
    CONFIG["cpu_limit"]="2"
    
    # Security settings
    CONFIG["enable_api_key"]="true"
    CONFIG["enable_api_key_restrictions"]="false"
    CONFIG["cors_allow_origin"]="*"
    
    # Telemetry settings
    CONFIG["disable_telemetry"]="true"
    
    log "SUCCESS" "Configuration initialized with defaults."
}

# Load configuration from file
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log "WARNING" "Configuration file not found: $config_file"
        return 1
    fi
    
    log "INFO" "Loading configuration from: $config_file"
    
    local section=""
    
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip comments and empty lines
        [[ $key == \#* ]] || [[ -z "$key" ]] && continue
        
        # Handle section headers
        if [[ $key =~ ^\[(.*)\]$ ]]; then
            section=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
            continue
        fi
        
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # Store in config array
        CONFIG["$key"]="$value"
    done < "$config_file"
    
    log "SUCCESS" "Configuration loaded successfully."
    return 0
}

# Save configuration to file
save_config() {
    local config_file="$1"
    
    log "INFO" "Saving configuration to: $config_file"
    
    # Create backup if file exists
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak"
        log "INFO" "Created backup: ${config_file}.bak"
    fi
    
    # Write config file
    cat > "$config_file" << EOL
# Open WebUI Configuration
# Generated on $(date)
# This file is used by the Open WebUI deployment script

[Basic]
webui_port=${CONFIG["webui_port"]}
enable_auth=${CONFIG["enable_auth"]}
enable_signup=${CONFIG["enable_signup"]}
allow_all_models=${CONFIG["allow_all_models"]}

[API]
enable_ollama=${CONFIG["enable_ollama"]}
ollama_url=${CONFIG["ollama_url"]}

# OpenAI API
enable_openai=${CONFIG["enable_openai"]}
openai_api_key=${CONFIG["openai_api_key"]}
openai_base_url=${CONFIG["openai_base_url"]}

# Claude API (Anthropic)
enable_claude=${CONFIG["enable_claude"]}
claude_api_key=${CONFIG["claude_api_key"]}

# OpenRouter API
enable_openrouter=${CONFIG["enable_openrouter"]}
openrouter_api_key=${CONFIG["openrouter_api_key"]}
openrouter_base_url=${CONFIG["openrouter_base_url"]}

# Google Gemini API
enable_gemini=${CONFIG["enable_gemini"]}
gemini_api_key=${CONFIG["gemini_api_key"]}

# Azure OpenAI API
enable_azure_openai=${CONFIG["enable_azure_openai"]}
azure_openai_api_key=${CONFIG["azure_openai_api_key"]}
azure_openai_endpoint=${CONFIG["azure_openai_endpoint"]}
azure_deployment_name=${CONFIG["azure_deployment_name"]}

# Groq API
enable_groq=${CONFIG["enable_groq"]}
groq_api_key=${CONFIG["groq_api_key"]}

# Custom API
enable_custom_api=${CONFIG["enable_custom_api"]}
custom_api_url=${CONFIG["custom_api_url"]}

[Features]
enable_web_search=${CONFIG["enable_web_search"]}
web_search_engine=${CONFIG["web_search_engine"]}
search_result_count=${CONFIG["search_result_count"]}
enable_speech_to_text=${CONFIG["enable_speech_to_text"]}
stt_engine=${CONFIG["stt_engine"]}
whisper_model=${CONFIG["whisper_model"]}
enable_text_to_speech=${CONFIG["enable_text_to_speech"]}
tts_engine=${CONFIG["tts_engine"]}
tts_voice=${CONFIG["tts_voice"]}
tts_model=${CONFIG["tts_model"]}
enable_pipelines=${CONFIG["enable_pipelines"]}
pipelines_port=${CONFIG["pipelines_port"]}
install_function_calling=${CONFIG["install_function_calling"]}
install_rate_limiting=${CONFIG["install_rate_limiting"]}
install_toxic_filter=${CONFIG["install_toxic_filter"]}
install_libretranslate=${CONFIG["install_libretranslate"]}
install_langfuse=${CONFIG["install_langfuse"]}
enable_image_generation=${CONFIG["enable_image_generation"]}
image_generation_engine=${CONFIG["image_generation_engine"]}
image_model=${CONFIG["image_model"]}
image_size=${CONFIG["image_size"]}
enable_rag=${CONFIG["enable_rag"]}
enable_channels=${CONFIG["enable_channels"]}

[Resources]
memory_limit=${CONFIG["memory_limit"]}
cpu_limit=${CONFIG["cpu_limit"]}

[Security]
secret_key=${CONFIG["secret_key"]}
enable_api_key=${CONFIG["enable_api_key"]}
enable_api_key_restrictions=${CONFIG["enable_api_key_restrictions"]}
cors_allow_origin=${CONFIG["cors_allow_origin"]}

[Telemetry]
disable_telemetry=${CONFIG["disable_telemetry"]}
EOL
    
    log "SUCCESS" "Configuration saved successfully."
}

# Interactive configuration setup
configure_interactively() {
    log "INFO" "Starting interactive configuration..."
    
    echo -e "\n${BLUE}=== Basic Configuration ===${NC}"
    get_input "Enter the port for Open WebUI" "${CONFIG["webui_port"]}" "webui_port"
    get_boolean_input "Enable authentication" "${CONFIG["enable_auth"]}" "enable_auth"
    
    if [ "${CONFIG["enable_auth"]}" = true ]; then
        get_boolean_input "Enable user registration" "${CONFIG["enable_signup"]}" "enable_signup"
        get_boolean_input "Allow all users to access all models" "${CONFIG["allow_all_models"]}" "allow_all_models"
    fi
    
    echo -e "\n${BLUE}=== API Integration ===${NC}"
    get_boolean_input "Enable Ollama (local LLM hosting)" "${CONFIG["enable_ollama"]}" "enable_ollama"
    
    if [ "${CONFIG["enable_ollama"]}" = true ]; then
        get_input "Ollama URL" "${CONFIG["ollama_url"]}" "ollama_url"
    fi
    
    # OpenAI API
    get_boolean_input "Enable OpenAI API" "${CONFIG["enable_openai"]}" "enable_openai"
    if [ "${CONFIG["enable_openai"]}" = true ]; then
        get_input "OpenAI API Key" "${CONFIG["openai_api_key"]}" "openai_api_key" true
        get_input "OpenAI Base URL (for API proxies)" "${CONFIG["openai_base_url"]}" "openai_base_url"
    fi
    
    # Claude API
    get_boolean_input "Enable Claude API (Anthropic)" "${CONFIG["enable_claude"]}" "enable_claude"
    if [ "${CONFIG["enable_claude"]}" = true ]; then
        get_input "Claude API Key" "${CONFIG["claude_api_key"]}" "claude_api_key" true
    fi
    
    # OpenRouter API
    get_boolean_input "Enable OpenRouter API (unified API for multiple providers)" "${CONFIG["enable_openrouter"]}" "enable_openrouter"
    if [ "${CONFIG["enable_openrouter"]}" = true ]; then
        get_input "OpenRouter API Key" "${CONFIG["openrouter_api_key"]}" "openrouter_api_key" true
        get_input "OpenRouter Base URL" "${CONFIG["openrouter_base_url"]}" "openrouter_base_url"
    fi
    
    # Google Gemini API
    get_boolean_input "Enable Google Gemini API" "${CONFIG["enable_gemini"]}" "enable_gemini"
    if [ "${CONFIG["enable_gemini"]}" = true ]; then
        get_input "Google Gemini API Key" "${CONFIG["gemini_api_key"]}" "gemini_api_key" true
    fi
    
    # Azure OpenAI API
    get_boolean_input "Enable Azure OpenAI API" "${CONFIG["enable_azure_openai"]}" "enable_azure_openai"
    if [ "${CONFIG["enable_azure_openai"]}" = true ]; then
        get_input "Azure OpenAI API Key" "${CONFIG["azure_openai_api_key"]}" "azure_openai_api_key" true
        get_input "Azure OpenAI Endpoint" "${CONFIG["azure_openai_endpoint"]}" "azure_openai_endpoint"
        get_input "Azure Deployment Name" "${CONFIG["azure_deployment_name"]}" "azure_deployment_name"
    fi
    
    # Groq API
    get_boolean_input "Enable Groq API" "${CONFIG["enable_groq"]}" "enable_groq"
    if [ "${CONFIG["enable_groq"]}" = true ]; then
        get_input "Groq API Key" "${CONFIG["groq_api_key"]}" "groq_api_key" true
    fi
    
    # Custom API
    get_boolean_input "Enable Custom API Endpoint" "${CONFIG["enable_custom_api"]}" "enable_custom_api"
    if [ "${CONFIG["enable_custom_api"]}" = true ]; then
        get_input "Custom API URL" "${CONFIG["custom_api_url"]}" "custom_api_url"
    fi
    
    echo -e "\n${BLUE}=== Feature Configuration ===${NC}"
    get_boolean_input "Enable Web Search (RAG)" "${CONFIG["enable_web_search"]}" "enable_web_search"
    
    if [ "${CONFIG["enable_web_search"]}" = true ]; then
        get_input "Web Search Engine (duckduckgo, google, bing, searxng, brave, tavily)" "${CONFIG["web_search_engine"]}" "web_search_engine"
        get_input "Number of search results" "${CONFIG["search_result_count"]}" "search_result_count"
        
        # Additional settings based on search engine
        case "${CONFIG["web_search_engine"]}" in
            google)
                get_input "Google PSE API Key" "" "google_pse_api_key" true
                get_input "Google PSE Engine ID" "" "google_pse_engine_id"
                ;;
            bing)
                get_input "Bing Search API Key" "" "bing_search_api_key" true
                ;;
            searxng)
                get_input "SearXNG Query URL" "" "searxng_query_url"
                ;;
            brave)
                get_input "Brave Search API Key" "" "brave_search_api_key" true
                ;;
            tavily)
                get_input "Tavily API Key" "" "tavily_api_key" true
                ;;
        esac
    fi
    
    get_boolean_input "Enable Speech-to-Text" "${CONFIG["enable_speech_to_text"]}" "enable_speech_to_text"
    
    if [ "${CONFIG["enable_speech_to_text"]}" = true ]; then
        get_input "STT Engine (local_whisper, openai, web_api)" "${CONFIG["stt_engine"]}" "stt_engine"
        
        if [ "${CONFIG["stt_engine"]}" = "local_whisper" ]; then
            get_input "Whisper Model Size (base, small, medium, large)" "${CONFIG["whisper_model"]}" "whisper_model"
        fi
    fi
    
    get_boolean_input "Enable Text-to-Speech" "${CONFIG["enable_text_to_speech"]}" "enable_text_to_speech"
    
    if [ "${CONFIG["enable_text_to_speech"]}" = true ]; then
        get_input "TTS Engine (web_api, openai, azure, elevenlabs)" "${CONFIG["tts_engine"]}" "tts_engine"
        
        if [ "${CONFIG["tts_engine"]}" = "openai" ]; then
            get_input "TTS Voice (alloy, echo, fable, onyx, nova, shimmer)" "${CONFIG["tts_voice"]}" "tts_voice"
            get_input "TTS Model (tts-1, tts-1-hd)" "${CONFIG["tts_model"]}" "tts_model"
        elif [ "${CONFIG["tts_engine"]}" = "elevenlabs" ]; then
            get_input "ElevenLabs API Key" "" "elevenlabs_api_key" true
            get_input "ElevenLabs Voice ID" "premade/Adam" "elevenlabs_voice_id"
        fi
    fi
    
    get_boolean_input "Enable Pipelines (Functions)" "${CONFIG["enable_pipelines"]}" "enable_pipelines"
    
    if [ "${CONFIG["enable_pipelines"]}" = true ]; then
        get_input "Pipelines Port" "${CONFIG["pipelines_port"]}" "pipelines_port"
        get_boolean_input "Install Function Calling Pipeline" "${CONFIG["install_function_calling"]}" "install_function_calling"
        get_boolean_input "Install Rate Limiting Pipeline" "${CONFIG["install_rate_limiting"]}" "install_rate_limiting"
        get_boolean_input "Install Toxic Message Filtering Pipeline" "${CONFIG["install_toxic_filter"]}" "install_toxic_filter"
        get_boolean_input "Install LibreTranslate Pipeline" "${CONFIG["install_libretranslate"]}" "install_libretranslate"
        get_boolean_input "Install Langfuse Monitoring Pipeline" "${CONFIG["install_langfuse"]}" "install_langfuse"
    fi
    
    get_boolean_input "Enable Image Generation" "${CONFIG["enable_image_generation"]}" "enable_image_generation"
    
    if [ "${CONFIG["enable_image_generation"]}" = true ]; then
        get_input "Image Generation Engine (openai, automatic1111, comfyui)" "${CONFIG["image_generation_engine"]}" "image_generation_engine"
        get_input "Image Size (512x512, 1024x1024)" "${CONFIG["image_size"]}" "image_size"
        
        if [ "${CONFIG["image_generation_engine"]}" = "automatic1111" ]; then
            get_input "AUTOMATIC1111 URL" "http://automatic1111:7860" "automatic1111_url"
        elif [ "${CONFIG["image_generation_engine"]}" = "comfyui" ]; then
            get_input "ComfyUI URL" "http://comfyui:8188" "comfyui_url"
        fi
    fi
    
    get_boolean_input "Enable RAG Document Processing" "${CONFIG["enable_rag"]}" "enable_rag"
    get_boolean_input "Enable Channel Support" "${CONFIG["enable_channels"]}" "enable_channels"
    
    echo -e "\n${BLUE}=== System Resource Configuration ===${NC}"
    get_input "Memory Limit (e.g., 4G, 8G)" "${CONFIG["memory_limit"]}" "memory_limit"
    get_input "CPU Limit (number of cores)" "${CONFIG["cpu_limit"]}" "cpu_limit"
    
    if confirm "Would you like to save this configuration for future use?"; then
        save_config "$CONFIG_FILE"
    fi
    
    log "SUCCESS" "Configuration completed."
}

#######################################
# Docker Compose Functions
#######################################

# Generate Docker Compose file
generate_docker_compose() {
    local output_file="$1"
    
    log "INFO" "Generating Docker Compose file: $output_file"
    
    # Start with version and services
    cat > "$output_file" << EOL
version: '3'

services:
EOL
    
    # Add Ollama if enabled
    if [ "${CONFIG["enable_ollama"]}" = true ]; then
        cat >> "$output_file" << EOL
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    volumes:
      - ollama:/root/.ollama
    restart: unless-stopped

EOL
    fi
    
    # Add Open WebUI
    cat >> "$output_file" << EOL
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
EOL
    
    # Add dependencies
    if [ "${CONFIG["enable_ollama"]}" = true ] || [ "${CONFIG["enable_pipelines"]}" = true ]; then
        echo "    depends_on:" >> "$output_file"
        
        if [ "${CONFIG["enable_ollama"]}" = true ]; then
            echo "      - ollama" >> "$output_file"
        fi
        
        if [ "${CONFIG["enable_pipelines"]}" = true ]; then
            echo "      - redis" >> "$output_file"
        fi
    fi
    
    # Add port mapping
    cat >> "$output_file" << EOL
    ports:
      - "${CONFIG["webui_port"]}:8080"
    volumes:
      - open-webui:/app/backend/data
    env_file:
      - .env
EOL
    
    # Add Ollama URL if Ollama is enabled
    if [ "${CONFIG["enable_ollama"]}" = true ]; then
        cat >> "$output_file" << EOL
    environment:
      - "OLLAMA_BASE_URL=${CONFIG["ollama_url"]}"
EOL
    fi
    
    # Add resource limits
    cat >> "$output_file" << EOL
    mem_limit: ${CONFIG["memory_limit"]}
    cpus: ${CONFIG["cpu_limit"]}
    restart: unless-stopped
EOL
    
    # Add Pipelines if enabled
    if [ "${CONFIG["enable_pipelines"]}" = true ]; then
        cat >> "$output_file" << EOL

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
      - redis
      
  redis:
    image: redis:alpine
    container_name: redis
    volumes:
      - redis-data:/data
    restart: unless-stopped
EOL
    fi
    
    # Add volumes
    cat >> "$output_file" << EOL

volumes:
EOL
    
    if [ "${CONFIG["enable_ollama"]}" = true ]; then
        echo "  ollama: {}" >> "$output_file"
    fi
    
    echo "  open-webui: {}" >> "$output_file"
    
    if [ "${CONFIG["enable_pipelines"]}" = true ]; then
        echo "  pipelines: {}" >> "$output_file"
        echo "  redis-data: {}" >> "$output_file"
    fi
    
    log "SUCCESS" "Docker Compose file generated successfully."
}

# Generate environment file
generate_env_file() {
    local output_file="$1"
    
    log "INFO" "Generating environment file: $output_file"
    
    # Start with basic configuration
    cat > "$output_file" << EOL
# Open WebUI Environment Configuration
# Generated by ${SCRIPT_NAME} on $(date)

# Basic Configuration
OPEN_WEBUI_PORT=${CONFIG["webui_port"]}
WEBUI_AUTH=${CONFIG["enable_auth"]}
ENABLE_SIGNUP=${CONFIG["enable_signup"]}
BYPASS_MODEL_ACCESS_CONTROL=${CONFIG["allow_all_models"]}
WEBUI_SECRET_KEY=${CONFIG["secret_key"]}

# API Configuration
EOL
    
    # Add Ollama configuration
    if [ "${CONFIG["enable_ollama"]}" = true ]; then
        echo "OLLAMA_BASE_URL=${CONFIG["ollama_url"]}" >> "$output_file"
    fi
    
    # Add OpenAI configuration
    if [ "${CONFIG["enable_openai"]}" = true ]; then
        echo "OPENAI_API_BASE_URL=${CONFIG["openai_base_url"]}" >> "$output_file"
        echo "OPENAI_API_KEY=${CONFIG["openai_api_key"]}" >> "$output_file"
    fi
    
    # Add Claude configuration
    if [ "${CONFIG["enable_claude"]}" = true ]; then
        echo "ANTHROPIC_API_KEY=${CONFIG["claude_api_key"]}" >> "$output_file"
    fi
    
    # Add OpenRouter configuration
    if [ "${CONFIG["enable_openrouter"]}" = true ]; then
        echo "OPENROUTER_API_KEY=${CONFIG["openrouter_api_key"]}" >> "$output_file"
        echo "OPENROUTER_API_BASE_URL=${CONFIG["openrouter_base_url"]}" >> "$output_file"
    fi
    
    # Add Gemini configuration
    if [ "${CONFIG["enable_gemini"]}" = true ]; then
        echo "GEMINI_API_KEY=${CONFIG["gemini_api_key"]}" >> "$output_file"
    fi
    
    # Add Azure OpenAI configuration
    if [ "${CONFIG["enable_azure_openai"]}" = true ]; then
        echo "AZURE_OPENAI_API_KEY=${CONFIG["azure_openai_api_key"]}" >> "$output_file"
        echo "AZURE_OPENAI_ENDPOINT=${CONFIG["azure_openai_endpoint"]}" >> "$output_file"
        echo "AZURE_DEPLOYMENT_NAME=${CONFIG["azure_deployment_name"]}" >> "$output_file"
    fi
    
    # Add Groq configuration
    if [ "${CONFIG["enable_groq"]}" = true ]; then
        echo "GROQ_API_KEY=${CONFIG["groq_api_key"]}" >> "$output_file"
    fi
    
    # Add Custom API configuration
    if [ "${CONFIG["enable_custom_api"]}" = true ]; then
        echo "CUSTOM_API_URL=${CONFIG["custom_api_url"]}" >> "$output_file"
    fi
    
    # Add feature configuration
    cat >> "$output_file" << EOL

# Feature Configuration
EOL
    
    # Add Web Search configuration
    if [ "${CONFIG["enable_web_search"]}" = true ]; then
        echo "ENABLE_RAG_WEB_SEARCH=true" >> "$output_file"
        echo "RAG_WEB_SEARCH_ENGINE=${CONFIG["web_search_engine"]}" >> "$output_file"
        echo "RAG_WEB_SEARCH_RESULT_COUNT=${CONFIG["search_result_count"]}" >> "$output_file"
        
        # Add engine-specific settings
        case "${CONFIG["web_search_engine"]}" in
            google)
                if [ -n "${CONFIG["google_pse_api_key"]}" ]; then
                    echo "GOOGLE_PSE_API_KEY=${CONFIG["google_pse_api_key"]}" >> "$output_file"
                fi
                if [ -n "${CONFIG["google_pse_engine_id"]}" ]; then
                    echo "GOOGLE_PSE_ENGINE_ID=${CONFIG["google_pse_engine_id"]}" >> "$output_file"
                fi
                ;;
            bing)
                if [ -n "${CONFIG["bing_search_api_key"]}" ]; then
                    echo "BING_SEARCH_V7_SUBSCRIPTION_KEY=${CONFIG["bing_search_api_key"]}" >> "$output_file"
                fi
                ;;
            searxng)
                if [ -n "${CONFIG["searxng_query_url"]}" ]; then
                    echo "SEARXNG_QUERY_URL=${CONFIG["searxng_query_url"]}" >> "$output_file"
                fi
                ;;
            brave)
                if [ -n "${CONFIG["brave_search_api_key"]}" ]; then
                    echo "BRAVE_SEARCH_API_KEY=${CONFIG["brave_search_api_key"]}" >> "$output_file"
                fi
                ;;
            tavily)
                if [ -n "${CONFIG["tavily_api_key"]}" ]; then
                    echo "TAVILY_API_KEY=${CONFIG["tavily_api_key"]}" >> "$output_file"
                fi
                ;;
        esac
    fi
    
    # Add Speech-to-Text configuration
    if [ "${CONFIG["enable_speech_to_text"]}" = true ]; then
        cat >> "$output_file" << EOL

# Speech-to-Text Configuration
EOL
        if [ "${CONFIG["stt_engine"]}" = "local_whisper" ]; then
            echo "WHISPER_MODEL=${CONFIG["whisper_model"]}" >> "$output_file"
        elif [ "${CONFIG["stt_engine"]}" = "openai" ]; then
            echo "AUDIO_STT_ENGINE=openai" >> "$output_file"
            echo "AUDIO_STT_MODEL=whisper-1" >> "$output_file"
        fi
    fi
    
    # Add Text-to-Speech configuration
    if [ "${CONFIG["enable_text_to_speech"]}" = true ]; then
        cat >> "$output_file" << EOL

# Text-to-Speech Configuration
EOL
        echo "AUDIO_TTS_ENGINE=${CONFIG["tts_engine"]}" >> "$output_file"
        
        if [ "${CONFIG["tts_engine"]}" = "openai" ]; then
            echo "AUDIO_TTS_MODEL=${CONFIG["tts_model"]}" >> "$output_file"
            echo "AUDIO_TTS_VOICE=${CONFIG["tts_voice"]}" >> "$output_file"
        elif [ "${CONFIG["tts_engine"]}" = "elevenlabs" ]; then
            echo "ELEVENLABS_API_KEY=${CONFIG["elevenlabs_api_key"]}" >> "$output_file"
            echo "ELEVENLABS_VOICE_ID=${CONFIG["elevenlabs_voice_id"]}" >> "$output_file"
        fi
    fi
    
    # Add Pipeline configuration
    if [ "${CONFIG["enable_pipelines"]}" = true ]; then
        cat >> "$output_file" << EOL

# Pipeline Configuration
ENABLE_WEBSOCKET_SUPPORT=true
WEBSOCKET_MANAGER=redis
WEBSOCKET_REDIS_URL=redis://redis:6379/0
EOL

        # Add sample pipelines to install
        local pipelines_to_install=()
        
        if [ "${CONFIG["install_function_calling"]}" = "true" ]; then
            pipelines_to_install+=("https://github.com/open-webui/pipelines/raw/main/samples/function-calling.yaml")
        fi
        
        if [ "${CONFIG["install_rate_limiting"]}" = "true" ]; then
            pipelines_to_install+=("https://github.com/open-webui/pipelines/raw/main/samples/rate-limiter.yaml")
        fi
        
        if [ "${CONFIG["install_toxic_filter"]}" = "true" ]; then
            pipelines_to_install+=("https://github.com/open-webui/pipelines/raw/main/samples/toxicity-filter.yaml")
        fi
        
        if [ "${CONFIG["install_libretranslate"]}" = "true" ]; then
            pipelines_to_install+=("https://github.com/open-webui/pipelines/raw/main/samples/libretranslate.yaml")
        fi
        
        if [ "${CONFIG["install_langfuse"]}" = "true" ]; then
            pipelines_to_install+=("https://github.com/open-webui/pipelines/raw/main/samples/langfuse.yaml")
        fi
        
        if [ ${#pipelines_to_install[@]} -gt 0 ]; then
            echo "PIPELINES_URLS=\"${pipelines_to_install[*]}\"" >> "$output_file"
        fi
    fi
    
    # Add Image Generation configuration
    if [ "${CONFIG["enable_image_generation"]}" = true ]; then
        cat >> "$output_file" << EOL

# Image Generation Configuration
ENABLE_IMAGE_GENERATION=true
IMAGE_GENERATION_ENGINE=${CONFIG["image_generation_engine"]}
IMAGE_SIZE=${CONFIG["image_size"]}
EOL
        
        # Add engine-specific settings
        case "${CONFIG["image_generation_engine"]}" in
            automatic1111)
                echo "AUTOMATIC1111_BASE_URL=${CONFIG["automatic1111_url"]:-http://automatic1111:7860}" >> "$output_file"
                ;;
            comfyui)
                echo "COMFYUI_BASE_URL=${CONFIG["comfyui_url"]:-http://comfyui:8188}" >> "$output_file"
                ;;
        esac
    fi
    
    # Add RAG configuration
    if [ "${CONFIG["enable_rag"]}" = true ]; then
        cat >> "$output_file" << EOL

# RAG Configuration
VECTOR_DB=chroma
EOL
    fi
    
    # Add Channel configuration
    if [ "${CONFIG["enable_channels"]}" = true ]; then
        cat >> "$output_file" << EOL

# Channel Configuration
ENABLE_CHANNELS=true
EOL
    fi
    
    # Add security configuration
    cat >> "$output_file" << EOL

# Security Configuration
ENABLE_API_KEY=${CONFIG["enable_api_key"]}
ENABLE_API_KEY_ENDPOINT_RESTRICTIONS=${CONFIG["enable_api_key_restrictions"]}
CORS_ALLOW_ORIGIN=${CONFIG["cors_allow_origin"]}

# Telemetry Settings (Disabled)
SCARF_NO_ANALYTICS=true
DO_NOT_TRACK=true
ANONYMIZED_TELEMETRY=false
EOL
    
    log "SUCCESS" "Environment file generated successfully."
}

#######################################
# Deployment Functions
#######################################

# Deploy Open WebUI
deploy_open_webui() {
    log "INFO" "Starting Open WebUI deployment..."
    
    # Generate Docker Compose file
    generate_docker_compose "$DOCKER_COMPOSE_FILE"
    
    # Generate environment file
    generate_env_file "$ENV_FILE"
    
    # Pull Docker images
    log "INFO" "Pulling Docker images (this may take a few minutes)..."
    docker compose -f "$DOCKER_COMPOSE_FILE" pull
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to pull Docker images."
        if confirm "Would you like to try again?"; then
            docker compose -f "$DOCKER_COMPOSE_FILE" pull
        else
            error_exit "Deployment failed."
        fi
    fi
    
    # Start containers
    log "INFO" "Starting Docker containers..."
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to start Docker containers."
        
        # Check for common issues
        check_deployment_issues
        
        if confirm "Would you like to try again?"; then
            docker compose -f "$DOCKER_COMPOSE_FILE" up -d
        else
            error_exit "Deployment failed."
        fi
    fi
    
    # Verify deployment
    verify_deployment
    
    # Display success message
    display_success_message
}

# Check for common deployment issues
check_deployment_issues() {
    log "INFO" "Checking for common deployment issues..."
    
    # Check if ports are already in use
    if command_exists netstat && netstat -tuln 2>/dev/null | grep -q ":${CONFIG["webui_port"]}"; then
        log "WARNING" "Port ${CONFIG["webui_port"]} is already in use. Please choose a different port."
    elif command_exists ss && ss -tuln 2>/dev/null | grep -q ":${CONFIG["webui_port"]}"; then
        log "WARNING" "Port ${CONFIG["webui_port"]} is already in use. Please choose a different port."
    fi
    
    if [ "${CONFIG["enable_pipelines"]}" = true ]; then
        if command_exists netstat && netstat -tuln 2>/dev/null | grep -q ":${CONFIG["pipelines_port"]}"; then
            log "WARNING" "Port ${CONFIG["pipelines_port"]} is already in use. Please choose a different port."
        elif command_exists ss && ss -tuln 2>/dev/null | grep -q ":${CONFIG["pipelines_port"]}"; then
            log "WARNING" "Port ${CONFIG["pipelines_port"]} is already in use. Please choose a different port."
        fi
    fi
    
    # Check Docker daemon
    if ! docker info &>/dev/null; then
        log "WARNING" "Docker daemon is not running. Please start Docker."
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -k . | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1000000 ]; then  # Less than 1GB
        log "WARNING" "Low disk space. Deployment may fail."
    fi
}

# Verify deployment
verify_deployment() {
    log "INFO" "Verifying deployment..."
    
    # Give containers some time to start
    sleep 5
    
    # Check if containers are running
    local containers=("open-webui")
    
    if [ "${CONFIG["enable_ollama"]}" = true ]; then
        containers+=("ollama")
    fi
    
    if [ "${CONFIG["enable_pipelines"]}" = true ]; then
        containers+=("pipelines" "redis")
    fi
    
    local all_running=true
    
    for container in "${containers[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^$container$"; then
            log "ERROR" "Container $container is not running."
            all_running=false
        fi
    done
    
    if [ "$all_running" = true ]; then
        # Check if web UI is responding
        local max_attempts=12  # Increased from 6 to 12 attempts
        local attempts=0
        local success=false
        
        log "INFO" "Waiting for Open WebUI to become available..."
        
        while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
            attempts=$((attempts + 1))
            
            # Try to access the health endpoint
            if curl -s "http://localhost:${CONFIG["webui_port"]}/health" | grep -q "status.*true"; then
                success=true
            else
                log "INFO" "Waiting for Open WebUI to start (attempt $attempts/$max_attempts)..."
                sleep 10  # Increased from 5 to 10 seconds
            fi
        done
        
        if [ "$success" = true ]; then
            log "SUCCESS" "Open WebUI is up and running."
        else
            log "WARNING" "Could not verify that Open WebUI is running properly. It might still be starting up."
            log "INFO" "You can check logs with: docker compose -f $DOCKER_COMPOSE_FILE logs -f open-webui"
        fi
    else
        log "WARNING" "Not all containers are running. Deployment may have issues."
        docker ps
    fi
}

# Display success message
display_success_message() {
    local server_ip
    
    # Get the server's public IP if possible, otherwise use localhost
    if command_exists curl; then
        server_ip=$(curl -s https://api.ipify.org 2>/dev/null)
    fi
    
    if [ -z "$server_ip" ]; then
        # Try to get local IP
        if command_exists hostname; then
            server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        fi
        
        # Fallback to localhost
        if [ -z "$server_ip" ]; then
            server_ip="localhost"
        fi
    fi
    
    local web_url="http://$server_ip:${CONFIG["webui_port"]}"
    
    cat << EOL

${GREEN}┌─────────────────────────────────────────────────────┐${NC}
${GREEN}│                                                     │${NC}
${GREEN}│             Open WebUI Deployed Successfully!       │${NC}
${GREEN}│                                                     │${NC}
${GREEN}└─────────────────────────────────────────────────────┘${NC}

Access Open WebUI at: ${BLUE}$web_url${NC}

${YELLOW}Important Notes:${NC}
• The first account you create will be the administrator account.
• If you enabled Ollama, it may take a few minutes to become ready.
• To check logs: ${BLUE}docker compose -f $DOCKER_COMPOSE_FILE logs -f${NC}
• To stop: ${BLUE}docker compose -f $DOCKER_COMPOSE_FILE down${NC}
• To restart: ${BLUE}docker compose -f $DOCKER_COMPOSE_FILE restart${NC}

${YELLOW}Quick commands:${NC}
• Download models: ${BLUE}docker exec -it ollama run llama3${NC}
• List all models: ${BLUE}docker exec -it ollama ls${NC}
• Remove models: ${BLUE}docker exec -it ollama rm llama3${NC}

Your configuration has been saved to: ${BLUE}$CONFIG_FILE${NC}
Docker Compose file: ${BLUE}$DOCKER_COMPOSE_FILE${NC}
Environment file: ${BLUE}$ENV_FILE${NC}

EOL
}

#######################################
# Management Functions
#######################################

# Stop Open WebUI
stop_open_webui() {
    log "INFO" "Stopping Open WebUI..."
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        docker compose -f "$DOCKER_COMPOSE_FILE" down
        log "SUCCESS" "Open WebUI has been stopped."
    else
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
}

# Restart Open WebUI
restart_open_webui() {
    log "INFO" "Restarting Open WebUI..."
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        docker compose -f "$DOCKER_COMPOSE_FILE" restart
        log "SUCCESS" "Open WebUI has been restarted."
    else
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
}

# Update Open WebUI
update_open_webui() {
    log "INFO" "Updating Open WebUI..."
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        docker compose -f "$DOCKER_COMPOSE_FILE" pull
        docker compose -f "$DOCKER_COMPOSE_FILE" up -d
        log "SUCCESS" "Open WebUI has been updated."
    else
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
}

# Show logs
show_logs() {
    log "INFO" "Showing logs for Open WebUI..."
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        docker compose -f "$DOCKER_COMPOSE_FILE" logs -f
    else
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
}

# Clean Open WebUI installation
clean_open_webui() {
    log "INFO" "Cleaning Open WebUI installation..."
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        # Stop containers
        docker compose -f "$DOCKER_COMPOSE_FILE" down
        
        if confirm "Remove Docker volumes? This will delete all data, including models, conversations, and settings."; then
            docker compose -f "$DOCKER_COMPOSE_FILE" down -v
            log "INFO" "Docker volumes removed."
        fi
        
        # Remove files
        if confirm "Remove configuration files?"; then
            rm -f "$DOCKER_COMPOSE_FILE" "$ENV_FILE" "$CONFIG_FILE"
            log "INFO" "Configuration files removed."
        fi
        
        log "SUCCESS" "Open WebUI has been cleaned up."
    else
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
}

#######################################
# Main Script Functions
#######################################

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            --non-interactive)
                NON_INTERACTIVE=true
                ;;
            --config)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    CONFIG_FILE="$2"
                    shift
                else
                    error_exit "Missing argument for $key"
                fi
                ;;
            --port)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    CONFIG["webui_port"]="$2"
                    shift
                else
                    error_exit "Missing argument for $key"
                fi
                ;;
            --ollama-url)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    CONFIG["ollama_url"]="$2"
                    shift
                else
                    error_exit "Missing argument for $key"
                fi
                ;;
            --no-ollama)
                CONFIG["enable_ollama"]=false
                ;;
            --stop)
                ACTION="stop"
                ;;
            --restart)
                ACTION="restart"
                ;;
            --update)
                ACTION="update"
                ;;
            --logs)
                ACTION="logs"
                ;;
            --clean)
                ACTION="clean"
                ;;
            --help)
                SHOW_HELP=true
                ;;
            *)
                echo "Unknown option: $key"
                SHOW_HELP=true
                ;;
        esac
        shift
    done
}

# Main function
main() {
    # Display banner
    cat << "EOF"
 _____                    _    _      _     _   _ ___ 
|  _  |___ ___ ___ ___   | |  | | ___| |_  | | | |_ _|
|     |  _| -_|   | . |  | |  | |/ -_)  _| | |_| || | 
|__|__|_| |___|_|_|___|  |_|__|_|\___|\__|  \___/|___|
                                                       
EOF
    
    echo "Open WebUI Deployment Script v${SCRIPT_VERSION}"
    echo "---------------------------------------------"
    
    # Parse command-line arguments
    parse_arguments "$@"
    
    # Show help and exit if requested
    if [ "$SHOW_HELP" = true ]; then
        show_help
        exit 0
    fi
    
    # Check if any action is specified
    if [ -n "$ACTION" ]; then
        case "$ACTION" in
            stop)
                stop_open_webui
                ;;
            restart)
                restart_open_webui
                ;;
            update)
                update_open_webui
                ;;
            logs)
                show_logs
                ;;
            clean)
                clean_open_webui
                ;;
        esac
        exit 0
    fi
    
    # Initialize configuration with defaults
    init_config
    
    # Load configuration from file if it exists
    if [ -f "$CONFIG_FILE" ]; then
        load_config "$CONFIG_FILE"
    fi
    
    # Check system requirements
    check_system_requirements
    
    # Interactive configuration if not in non-interactive mode
    if [ "$NON_INTERACTIVE" = false ]; then
        configure_interactively
    fi
    
    # Confirm deployment
    if [ "$NON_INTERACTIVE" = false ]; then
        if ! confirm "Ready to deploy Open WebUI with the current configuration. Continue?"; then
            log "INFO" "Deployment cancelled."
            exit 0
        fi
    fi
    
    # Deploy Open WebUI
    deploy_open_webui
    
    return 0
}

# Start script
main "$@"