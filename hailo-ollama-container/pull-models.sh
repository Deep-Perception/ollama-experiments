#!/bin/bash

# Script to pull all available models from the Hailo API

# Note: Not using 'set -e' here to allow the script to continue even if one model fails

echo "Fetching list of available models..."

# Get the list of models from the API
response=$(curl --silent http://localhost:8000/hailo/v1/list)

# Check if the curl command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch model list from API"
    exit 1
fi

# Extract model names using jq (requires jq to be installed)
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    # Use mapfile instead of readarray for better compatibility
    mapfile -t models < <(echo "$response" | jq -r '.models[]')
else
    echo "jq not found, using fallback parsing..."
    # Improved fallback method
    models_string=$(echo "$response" | sed 's/.*"models":\[\([^]]*\)\].*/\1/' | tr ',' '\n' | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
    mapfile -t models <<< "$models_string"
fi

# Debug: Show what we parsed
echo "Debug - Raw models array:"
for i in "${!models[@]}"; do
    echo "  [$i] = '${models[$i]}'"
done

# Remove any empty elements
filtered_models=()
for model in "${models[@]}"; do
    if [[ -n "$model" && "$model" != "" ]]; then
        filtered_models+=("$model")
    fi
done
models=("${filtered_models[@]}")

# Check if we got any models
if [ ${#models[@]} -eq 0 ]; then
    echo "Error: No models found in API response"
    echo "Response was: $response"
    exit 1
fi

echo "Found ${#models[@]} models:"
for model in "${models[@]}"; do
    echo "  - '$model'"
done
echo ""

# Pull each model
success_count=0
fail_count=0

for i in "${!models[@]}"; do
    model="${models[$i]}"
    echo "Pulling model [$((i+1))/${#models[@]}]: '$model'"
    
    # Capture the response and check it
    response=$(curl --silent http://localhost:8000/api/pull \
         -H 'Content-Type: application/json' \
         -d "{ \"model\": \"$model\", \"stream\": true }")
    
    # Check if the response contains success status
    if echo "$response" | grep -q '"status":"success"'; then
        echo "✓ Successfully initiated pull for '$model'"
        ((success_count++))
    else
        echo "✗ Failed to pull '$model'"
        echo "Response: $response"
        ((fail_count++))
    fi
    
    echo ""
done

echo "Summary:"
echo "  Successfully initiated: $success_count models"
echo "  Failed: $fail_count models"

echo "All model pulls initiated."
