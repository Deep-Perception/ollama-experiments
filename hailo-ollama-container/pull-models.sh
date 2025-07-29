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
for i in "${!models[@]}"; do
    echo "  $((i+1)). ${models[$i]}"
done
echo "  $((${#models[@]}+1)). All models"
echo ""

# Prompt user for selection
while true; do
    read -p "Which model(s) would you like to pull? (1-$((${#models[@]}+1))): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((${#models[@]}+1)) ]; then
        break
    else
        echo "Invalid selection. Please enter a number between 1 and $((${#models[@]}+1))."
    fi
done

# Determine which models to pull
if [ "$choice" -eq $((${#models[@]}+1)) ]; then
    models_to_pull=("${models[@]}")
    echo "Selected: All models"
else
    models_to_pull=("${models[$((choice-1))]}")
    echo "Selected: ${models[$((choice-1))]}"
fi
echo ""

# Pull selected model(s)
success_count=0
fail_count=0

for i in "${!models_to_pull[@]}"; do
    model="${models_to_pull[$i]}"
    echo "Checking model [$((i+1))/${#models_to_pull[@]}]: '$model'"
    
    # Check if model is already downloaded by trying to get its info
    model_info=$(curl --silent --connect-timeout 5 --max-time 10 http://localhost:8000/api/show \
                 -H 'Content-Type: application/json' \
                 -d "{ \"name\": \"$model\" }" 2>/dev/null)
    
    # If we get model info back, it's already downloaded
    if echo "$model_info" | grep -q '"license"' || echo "$model_info" | grep -q '"parameters"' || echo "$model_info" | grep -q '"details"'; then
        echo "ℹ️  Model '$model' is already downloaded"
        ((success_count++))
        echo ""
        continue
    fi
    
    echo "Downloading model '$model'..."
    
    # Stream the response and show progress in real-time
    echo "Starting pull for '$model'..."
    echo "Progress (press Ctrl+C to cancel):"
    
    # Create a temporary file to capture the final status
    temp_file=$(mktemp)
    
    # Use curl without capturing to show streaming output directly
    curl --connect-timeout 10 --max-time 300 http://localhost:8000/api/pull \
         -H 'Content-Type: application/json' \
         -d "{ \"model\": \"$model\", \"stream\": true }" \
         2>/dev/null | while IFS= read -r line; do
        
        # Parse and display progress
        if echo "$line" | grep -q '"status":"pulling"'; then
            # Extract progress info using basic text processing
            completed=$(echo "$line" | grep -o '"completed":[0-9]*' | cut -d: -f2)
            total=$(echo "$line" | grep -o '"total":[0-9]*' | cut -d: -f2)
            
            if [[ -n "$completed" && -n "$total" && "$total" -gt 0 ]]; then
                percent=$((completed * 100 / total))
                mb_completed=$((completed / 1024 / 1024))
                mb_total=$((total / 1024 / 1024))
                printf "\r  Progress: %d%% (%d MB / %d MB)" "$percent" "$mb_completed" "$mb_total"
            fi
        elif echo "$line" | grep -q '"status":"success"'; then
            echo ""
            echo "✓ Successfully completed pull for '$model'"
            echo "success" > "$temp_file"
            break
        elif echo "$line" | grep -q '"status":"error"'; then
            echo ""
            echo "✗ Error pulling '$model': $line"
            echo "error" > "$temp_file"
            break
        fi
    done
    
    # Get curl exit code
    curl_exit_code=${PIPESTATUS[0]}
    
    # Read the status from temp file
    if [ -f "$temp_file" ]; then
        final_status=$(cat "$temp_file")
        rm "$temp_file"
    else
        final_status=""
    fi
    
    # Count results based on actual status
    if [ "$final_status" = "success" ]; then
        ((success_count++))
    elif [ "$final_status" = "error" ]; then
        ((fail_count++))
    elif [ $curl_exit_code -ne 0 ]; then
        echo ""
        echo "✗ Connection failed for '$model' (curl exit code: $curl_exit_code)"
        ((fail_count++))
    else
        # Stream ended without explicit success/error status
        echo ""
        echo "? Pull for '$model' completed but status unclear"
        ((success_count++))  # Assume success if no explicit error
    fi
    
    echo ""
done

echo "Summary:"
echo "  Successfully initiated: $success_count models"
echo "  Failed: $fail_count models"

echo "All model pulls initiated."
