#!/bin/bash

# Ask for the path of the folder containing test_suites_info.json
read -p "Enter the path of the folder containing test_suites_info.json: " folder_path

# Check if the JSON file exists
json_file="$folder_path/test_suites_info.json"
if [[ ! -f "$json_file" ]]; then
    echo "The file $json_file does not exist."
    exit 1
fi

# Ask the user if they want to process all dictionaries
read -p "Do you want to generate files for all dictionaries? (yes/no): " process_all

# Create the output directory if it doesn't exist
output_dir="pipelines"
mkdir -p "$output_dir"

# Template for the pipeline
pipeline_template() {
    cat <<EOL
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: sds-pipeline
spec:
  params:
    - name: gitrepourl
      type: string
      default: 'https://github.com/Tekton-Automation.git'
    - name: branch
      type: string
      default: 'master'
    - name: path
      type: string
      default: config/config.ini
    - name: contents
      type: string
      default: |
        [*oc_info]
        ocp_console_url = 
        user_name = 
        password = 
        api_url = 
        ocp_console_ip =
  workspaces:
    - name: shared-workspace
  tasks:
EOL
}

# Function to process a single dictionary
process_dictionary() {
    local dict_name=$1
    local dict_content=$(jq -r ".$dict_name" "$json_file")
    if [[ "$dict_content" == "null" ]]; then
        echo "The dictionary $dict_name does not exist in test_suites_info.json."
        return 1
    fi

    # Create a new pipeline file for the dictionary
    local pipeline_file="$output_dir/$dict_name.yaml"
    pipeline_template > "$pipeline_file"

    # Iterate over each key-value pair in the dictionary
    local keys=$(jq -r "keys[]" <<< "$dict_content")
    local first_task=true

    for key in $keys; do
        # Create task names
        local task_name=$(echo "$key-task" | tr '[:upper:]_' '[:lower:]-')
        local task_ref_name=$(echo "$key" | tr '[:upper:]_' '[:lower:]-')

        # Append task to the pipeline file
        echo "    - name: $task_name" >> "$pipeline_file"
        echo "      taskRef:" >> "$pipeline_file"
        echo "        name: $task_ref_name" >> "$pipeline_file"
        if ! $first_task; then
            echo "      runAfter:" >> "$pipeline_file"
            echo "        - $(echo "$prev_task_name-task" | tr '[:upper:]_' '[:lower:]-')" >> "$pipeline_file"
        fi
        echo "      params:" >> "$pipeline_file"
        echo "        - name: gitrepourl" >> "$pipeline_file"
        echo "          value: \$(params.gitrepourl)" >> "$pipeline_file"
        echo "        - name: branch" >> "$pipeline_file"
        echo "          value: \$(params.branch)" >> "$pipeline_file"
        echo "        - name: path" >> "$pipeline_file"
        echo "          value: \$(params.path)" >> "$pipeline_file"
        echo "        - name: contents" >> "$pipeline_file"
        echo "          value: \$(params.contents)" >> "$pipeline_file"
        echo "      workspaces:" >> "$pipeline_file"
        echo "        - name: source" >> "$pipeline_file"
        echo "          workspace: shared-workspace" >> "$pipeline_file"
        echo "        - name: output" >> "$pipeline_file"
        echo "          workspace: shared-workspace" >> "$pipeline_file"

        prev_task_name=$key
        first_task=false
    done

    echo "Created pipeline file: $pipeline_file"
}

if [[ "$process_all" == "yes" ]]; then
    # Get all dictionary names
    dict_names=$(jq -r 'keys[]' "$json_file")
    for dict_name in $dict_names; do
        process_dictionary "$dict_name"
    done
else
    # Ask for the dictionary name in test_suites_info.json
    read -p "Enter the dictionary name in test_suites_info.json: " dict_name
    process_dictionary "$dict_name"
fi

echo "All pipeline files created successfully in the directory: $output_dir."
