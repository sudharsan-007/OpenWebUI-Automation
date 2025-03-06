# Open WebUI Setup Configuration Reference

This document provides detailed information about the configuration options available through the Open WebUI setup script, covering all features and integrations.

## Table of Contents

1. [Basic Configuration](#basic-configuration)
2. [API Integration Options](#api-integration-options)
3. [Feature Configuration](#feature-configuration)
4. [Web Search Configuration](#web-search-configuration)
5. [Speech-to-Text Configuration](#speech-to-text-configuration)
6. [Text-to-Speech Configuration](#text-to-speech-configuration)
7. [Pipeline Configuration](#pipeline-configuration)
8. [Image Generation Configuration](#image-generation-configuration)
9. [Channel and Chat Configuration](#channel-and-chat-configuration)
10. [System Resource Configuration](#system-resource-configuration)
11. [Security Configuration](#security-configuration)

## Basic Configuration

These settings control the fundamental aspects of your Open WebUI deployment:

| Setting | Description | Default |
|---------|-------------|---------|
| Web UI Port | The port Open WebUI will use | 3000 |
| Enable Authentication | Require user login | Enabled |
| Allow User Registration | Allow new users to create accounts | Disabled |
| Allow All Users to Access All Models | Let all users access all configured models | Disabled |

When authentication is enabled, the first account created will automatically become the administrator account. By default, only admin users can access all models and adjust system settings.

## API Integration Options

Open WebUI supports multiple AI model providers:

| Provider | Description | Requirements |
|----------|-------------|-------------|
| Ollama | Local LLM hosting | None (included) |
| OpenAI API | Access to GPT models | API Key |
| Claude API (Anthropic) | Access to Claude models | API Key |
| OpenRouter | Unified API for multiple providers | API Key |
| Google Gemini | Access to Google's Gemini models | API Key |
| Custom API Endpoint | Connect to any OpenAI-compatible API | Endpoint URL |

Each API integration requires its corresponding API key and potentially additional configuration details. For example, custom API endpoints would require the full base URL.

## Feature Configuration

Open WebUI offers various enhanced features:

| Feature | Description | Default |
|---------|-------------|---------|
| Web Search (RAG) | Allows models to search the web | Enabled |
| Speech-to-Text | Convert speech to text for model input | Enabled |
| Text-to-Speech | Convert model responses to speech | Enabled |
| Pipelines (Functions) | Extend functionality with pipelines | Enabled |
| Image Generation | Generate images via model integration | Disabled |
| RAG Document Processing | Upload and query documents | Enabled |
| Channel Support | Chat rooms for collaboration | Enabled |

Enabling each feature will present additional configuration options specific to that feature.

## Web Search Configuration

When Web Search is enabled, the following options become available:

| Setting | Description | Available Options |
|---------|-------------|-------------------|
| Web Search Engine | The search provider | DuckDuckGo, Google PSE, Bing, SearXNG, Brave, Tavily, etc. |
| Search Result Count | Number of results to include | 3 (default) |
| API Key | Required for certain providers | - |
| Engine-specific settings | Varies by provider | - |

### Provider-Specific Settings

| Provider | Required Settings | Description |
|----------|-------------------|-------------|
| DuckDuckGo | None | No API key required |
| Google PSE | API Key, Engine ID | Requires Google Programmable Search Engine |
| Bing | API Key | Requires Microsoft Bing Search API |
| SearXNG | Query URL | Custom SearXNG instance URL |
| Brave | API Key | Requires Brave Search API key |
| Tavily | API Key | Requires Tavily API key |

## Speech-to-Text Configuration

Speech-to-Text settings control how voice input is processed:

| Setting | Description | Options |
|---------|-------------|---------|
| STT Engine | Speech recognition engine | Local Whisper, OpenAI, Web API |
| Whisper Model | Local model size (if using Whisper) | base, small, medium, large |
| STT Model | Remote model identifier | whisper-1 (OpenAI) |

### Engine Comparison

| Engine | Pros | Cons |
|--------|------|------|
| Local Whisper | Privacy, No API costs | Server resource usage |
| OpenAI | High accuracy | API costs, Data leaves server |
| Web API | No server resources | Browser-only, Limited language support |

## Text-to-Speech Configuration

Text-to-Speech settings control how model responses are converted to speech:

| Setting | Description | Options |
|---------|-------------|---------|
| TTS Engine | Speech synthesis engine | Web API, OpenAI, Azure, ElevenLabs |
| TTS Voice | Voice identifier | alloy, echo, fable, onyx, nova, shimmer (OpenAI) |
| TTS Model | Model identifier | tts-1, tts-1-hd (OpenAI) |

### Engine Comparison

| Engine | Pros | Cons |
|--------|------|------|
| Web API | No server resources, No API costs | Browser-only, Limited voices |
| OpenAI | High quality | API costs, Data leaves server |
| Azure | Enterprise support | API costs, Setup complexity |
| ElevenLabs | Voice cloning, High quality | API costs |

## Pipeline Configuration

Pipelines extend Open WebUI functionality:

| Setting | Description | Default |
|---------|-------------|---------|
| Pipelines Port | Port for the Pipelines service | 9099 |
| Sample Pipelines | Pre-configured pipeline examples | Various options |

### Available Sample Pipelines

| Pipeline | Description | Purpose |
|----------|-------------|---------|
| Function Calling | Enable API function calls | Integration with external services |
| Rate Limiting | Control request frequency | Prevent API abuse/overuse |
| Toxic Message Filtering | Filter harmful content | Content moderation |
| LibreTranslate Integration | Translation services | Multi-language support |
| Langfuse Monitoring | LLM observability | Usage analytics and monitoring |

## Image Generation Configuration

When Image Generation is enabled:

| Setting | Description | Options |
|---------|-------------|---------|
| Image Generation Engine | The provider for image creation | OpenAI, AUTOMATIC1111, ComfyUI |
| Image Size | Default image dimensions | 512x512, 1024x1024, etc. |
| Image Model | Model to use for generation | DALL-E, etc. |

## Channel and Chat Configuration

Settings for the chat interface and channels:

| Setting | Description | Default |
|---------|-------------|---------|
| Enable Channels | Allow chat rooms/channels | Enabled |
| Enable Chat Sharing | Allow sharing conversations | Disabled |
| Enable RLHF Annotation | Allow feedback on responses | Enabled |
| Enable Auto-tagging | Auto-categorize conversations | Enabled |

## System Resource Configuration

Control resource allocation:

| Setting | Description | Default |
|---------|-------------|---------|
| Memory Limit | Maximum RAM allocation | 4G |
| CPU Limit | Maximum CPU cores | 2 |

These limits help prevent Open WebUI from consuming excessive server resources.

## Security Configuration

Advanced security settings:

| Setting | Description | Default |
|---------|-------------|---------|
| Secret Key | Used for JWT token signing | Auto-generated |
| API Key Endpoint Restrictions | Limit API key endpoint access | Disabled |
| CORS Allow Origin | Control cross-origin requests | * |
| Session Cookie Settings | Cookie security options | Standard |

## Non-Interactive Configuration Files

For automated deployments, you can create a configuration file to use with the `--non-interactive` and `--config` flags. The file format is INI-style:

```ini
[Basic]
webui_port=3000
enable_auth=true
enable_signup=false
allow_all_models=false

[API]
enable_ollama=true
enable_openai=true
openai_api_key=sk-your-api-key

[Features]
enable_web_search=true
enable_speech_to_text=true
enable_text_to_speech=true
enable_pipelines=true
enable_image_generation=false
enable_rag=true
enable_channels=true

[WebSearch]
engine=duckduckgo
result_count=3

[SpeechToText]
engine=local_whisper
whisper_model=base

[TextToSpeech]
engine=openai
tts_voice=alloy
tts_model=tts-1

[Pipelines]
port=9099
install_function_calling=true
install_rate_limiting=true
install_toxic_filter=true
install_libretranslate=false
install_langfuse=false

[Resources]
memory_limit=4G
cpu_limit=2
```

## Environment Variables Reference

All configuration options set through the TUI are translated into environment variables in the generated `.env` file. This is a comprehensive reference of all supported environment variables:

### Authentication and Access

| Variable | Description | Default |
|----------|-------------|---------|
| `WEBUI_AUTH` | Enable authentication | true |
| `ENABLE_SIGNUP` | Allow user signups | false |
| `DEFAULT_USER_ROLE` | Default role for new users | pending |
| `BYPASS_MODEL_ACCESS_CONTROL` | Allow all users to access all models | false |
| `ADMIN_EMAIL` | Admin email address | - |
| `SHOW_ADMIN_DETAILS` | Show admin user details in the interface | true |
| `JWT_EXPIRES_IN` | JWT token expiration time | -1 (no expiration) |

### API Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_BASE_URL` | Ollama API URL | http://ollama:11434 |
| `OLLAMA_BASE_URLS` | Load-balanced Ollama backends (semicolon-separated) | - |
| `ENABLE_OLLAMA_API` | Enable Ollama API | true |
| `OPENAI_API_BASE_URL` | OpenAI API URL | https://api.openai.com/v1 |
| `OPENAI_API_BASE_URLS` | Load-balanced OpenAI endpoints (semicolon-separated) | - |
| `OPENAI_API_KEY` | OpenAI API key | - |
| `OPENAI_API_KEYS` | Multiple OpenAI API keys (semicolon-separated) | - |
| `ENABLE_OPENAI_API` | Enable OpenAI API | true |

### Web Search Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_RAG_WEB_SEARCH` | Enable web search | false |
| `RAG_WEB_SEARCH_ENGINE` | Web search engine | duckduckgo |
| `RAG_WEB_SEARCH_RESULT_COUNT` | Number of search results | 3 |
| `RAG_WEB_SEARCH_CONCURRENT_REQUESTS` | Maximum concurrent requests | 10 |
| `SEARXNG_QUERY_URL` | SearXNG query URL | - |
| `GOOGLE_PSE_API_KEY` | Google PSE API key | - |
| `GOOGLE_PSE_ENGINE_ID` | Google PSE engine ID | - |
| `BRAVE_SEARCH_API_KEY` | Brave search API key | - |
| `BING_SEARCH_V7_SUBSCRIPTION_KEY` | Bing search API key | - |
| `BING_SEARCH_V7_ENDPOINT` | Bing search endpoint | - |
| `TAVILY_API_KEY` | Tavily API key | - |

### Speech-to-Text Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `WHISPER_MODEL` | Local Whisper model | base |
| `WHISPER_MODEL_DIR` | Directory for Whisper models | /app/backend/data/cache/whisper/models |
| `AUDIO_STT_ENGINE` | Speech-to-Text engine | - |
| `AUDIO_STT_MODEL` | Speech-to-Text model | whisper-1 |
| `AUDIO_STT_OPENAI_API_BASE_URL` | OpenAI API URL for STT | ${OPENAI_API_BASE_URL} |
| `AUDIO_STT_OPENAI_API_KEY` | OpenAI API key for STT | ${OPENAI_API_KEY} |

### Text-to-Speech Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `AUDIO_TTS_ENGINE` | Text-to-Speech engine | - |
| `AUDIO_TTS_MODEL` | Text-to-Speech model | tts-1 |
| `AUDIO_TTS_VOICE` | Text-to-Speech voice | alloy |
| `AUDIO_TTS_OPENAI_API_BASE_URL` | OpenAI API URL for TTS | ${OPENAI_API_BASE_URL} |
| `AUDIO_TTS_OPENAI_API_KEY` | OpenAI API key for TTS | ${OPENAI_API_KEY} |
| `AUDIO_TTS_SPLIT_ON` | Text splitting strategy | punctuation |
| `AUDIO_TTS_AZURE_SPEECH_REGION` | Azure region for TTS | - |
| `AUDIO_TTS_AZURE_SPEECH_OUTPUT_FORMAT` | Azure TTS output format | - |

### RAG Document Processing

| Variable | Description | Default |
|----------|-------------|---------|
| `VECTOR_DB` | Vector database for embeddings | chroma |
| `RAG_EMBEDDING_ENGINE` | Engine for RAG embeddings | - |
| `RAG_EMBEDDING_MODEL` | Model for generating embeddings | sentence-transformers/all-MiniLM-L6-v2 |
| `ENABLE_RAG_HYBRID_SEARCH` | Enable hybrid BM25+embeddings search | false |
| `RAG_TOP_K` | Number of results to consider | 3 |
| `RAG_RELEVANCE_THRESHOLD` | Threshold for inclusion | 0.0 |
| `RAG_TEMPLATE` | Template for RAG prompt | (Default template) |
| `PDF_EXTRACT_IMAGES` | Extract images from PDFs | false |
| `ENABLE_GOOGLE_DRIVE_INTEGRATION` | Enable Google Drive for documents | false |

### Pipeline Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_WEBSOCKET_SUPPORT` | Enable websockets for Pipelines | false |
| `WEBSOCKET_MANAGER` | Websocket manager | redis |
| `WEBSOCKET_REDIS_URL` | Redis URL for websockets | redis://localhost:6379/0 |
| `PIPELINES_URLS` | URLs to sample pipelines to install | - |

### Image Generation

| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_IMAGE_GENERATION` | Enable image generation | false |
| `IMAGE_GENERATION_ENGINE` | Image generation engine | openai |
| `IMAGE_GENERATION_MODEL` | Model to use | - |
| `IMAGE_SIZE` | Default image dimensions | 512x512 |
| `AUTOMATIC1111_BASE_URL` | URL for AUTOMATIC1111 API | - |
| `COMFYUI_BASE_URL` | URL for ComfyUI API | - |
| `IMAGES_OPENAI_API_BASE_URL` | OpenAI API URL for images | ${OPENAI_API_BASE_URL} |
| `IMAGES_OPENAI_API_KEY` | OpenAI API key for images | ${OPENAI_API_KEY} |

### Channel and Chat Features

| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_CHANNELS` | Enable chat channels | false |
| `ENABLE_COMMUNITY_SHARING` | Enable sharing to community | true |
| `ENABLE_MESSAGE_RATING` | Enable feedback on messages | true |
| `ENABLE_TAGS_GENERATION` | Auto-generate tags for chats | true |
| `ENABLE_TITLE_GENERATION` | Auto-generate chat titles | true |
| `ENABLE_AUTOCOMPLETE_GENERATION` | Generate text autocomplete | true |

### Database and Storage

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Database connection URL | sqlite:///app/backend/data/webui.db |
| `STORAGE_PROVIDER` | Storage provider (local, s3, gcs) | - |
| `S3_ACCESS_KEY_ID` | S3 access key | - |
| `S3_SECRET_ACCESS_KEY` | S3 secret key | - |
| `S3_ENDPOINT_URL` | S3 endpoint URL | - |
| `S3_REGION_NAME` | S3 region | - |
| `S3_BUCKET_NAME` | S3 bucket name | - |

### Security and Advanced Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `WEBUI_SECRET_KEY` | Secret key for JWT tokens | Auto-generated |
| `ENABLE_API_KEY` | Enable API key authentication | true |
| `ENABLE_API_KEY_ENDPOINT_RESTRICTIONS` | Restrict API key endpoints | false |
| `API_KEY_ALLOWED_ENDPOINTS` | Allowed endpoints for API keys | - |
| `CORS_ALLOW_ORIGIN` | CORS allow origin setting | * |
| `WEBUI_SESSION_COOKIE_SAME_SITE` | Session cookie SameSite setting | lax |
| `WEBUI_SESSION_COOKIE_SECURE` | Secure flag for session cookies | false |
| `OFFLINE_MODE` | Run in offline mode | false |
| `ENV` | Environment (prod/dev) | prod |
| `HOST` | Host to bind to | 0.0.0.0 |
| `PORT` | Port to bind to | 8080 |

This comprehensive list covers all the environment variables that can be configured for Open WebUI. By using these variables in your `.env` file or Docker environment, you can customize every aspect of your Open WebUI installation.