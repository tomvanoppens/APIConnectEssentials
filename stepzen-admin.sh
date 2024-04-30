#!/bin/bash
# Copyright IBM Corp. 2020, 2024

CR_INDEX=0

# These for the operator based cloud deployment
# User can choose the Stepzen Graph Server CR.
# If no Stepzen Graph Server found will throw an error.
# Only one Stepzen Graph Server found will not show the options.
# More than one Stepzen Graph Server found the user will get a choice.

if [ -z "$SZA_PULL_SECRET_NAME" ] || [ -z "$SZA_MDB_SECRET_NAME" ]; then
  SZA_AVAILABLE_CRS=$(kubectl get StepZenGraphServer -o jsonpath='{.items[*].metadata.name}')
  #Hack to get array length. The SZA_AVAILABLE_CRS is space separated string the code will split the string into SZA_AVAILABLE_CRS_ARRAY 
  IFS=' ' read -ra SZA_AVAILABLE_CRS_ARRAY <<< "$SZA_AVAILABLE_CRS"
  if [ ${#SZA_AVAILABLE_CRS_ARRAY[@]} -gt 1 ]; then
        echo "These are the Stepzen Graph Servers:"
        for ((i=0; i<${#SZA_AVAILABLE_CRS_ARRAY[@]}; i++)); do
            echo "$((i+1)). ${SZA_AVAILABLE_CRS_ARRAY[i]}"
        done
        read -p "Enter your choice: " choice
        CR_INDEX=$(expr $choice - 1)
  elif [ ${#SZA_AVAILABLE_CRS_ARRAY[@]} -eq 1 ]; then
    CR_INDEX=0    
  else 
    echo "No Stepzen Graph Server found."
    exit 1
  fi
fi

# Default account
ACCOUNT_NAME=${2:-"graphql"}

# Assume operator-installed StepZenGraphServer by default
EXPRESSION_IPS="{.items[$CR_INDEX].spec.imagePullSecrets[0]}"
EXPRESSION_CDS="{.items[$CR_INDEX].spec.controlDatabaseSecret}"
SZA_PULL_SECRET_NAME=${SZA_PULL_SECRET_NAME:-$(kubectl get StepZenGraphServer -o jsonpath="$EXPRESSION_IPS")}
SZA_MDB_SECRET_NAME=${SZA_MDB_SECRET_NAME:-$(kubectl get StepZenGraphServer -o jsonpath="$EXPRESSION_CDS")}
SZA_ZEN_URL_BASE=${SZA_ZEN_URL_BASE:-"http://apic-graph-server.$(kubectl config view --minify -o jsonpath='{..namespace}').svc"}

# TODO: update to ICR on release
SZA_IMAGE=${SZA_IMAGE:-"cp.icr.io/cp/stepzen/stepzen-admin-jobs@sha256:12f030b6c80e715c7139bcac80fe3782cace96ae8d5f47577edeb914cd0e1dbb"}

APP_NAME="stepzen-admin-jobs"
SPINNER="/|\\-"
DELAY=0.1
ZENCTL_URL=$SZA_ZEN_URL_BASE/api/zenctl/graphql

function format_and_print_command() {
  screen_width=$(tput cols)
  plus_signs=$(printf '+%.0s' $(seq 1 $screen_width))

  echo "+ $1"
  echo "$plus_signs"
  eval $1
  echo "$plus_signs"

}

# Run the specified commands with the desired format
function printAllLogs() {
    lines="10000"  # Change this to the desired number of lines

    format_and_print_command "kubectl get StepZenGraphServer -o yaml"
    format_and_print_command "kubectl get stepzen-introspection -o yaml"

    pod_list=$(kubectl get pods --no-headers -o custom-columns=":metadata.name")

    for pod in $pod_list; do
        format_and_print_command "kubectl logs $pod --tail $lines"
    done

    format_and_print_command "kubectl get CustomResourceDefinition stepzengraphservers.apic-graph.ibm.com -o yaml"

    format_and_print_command "kubectl get ingress"
    format_and_print_command "kubectl get route"
}

if [ -z "$SZA_ARGS" ]; then
  if [ "$1" == "add-account" ]; then
    SZA_ARGS="[\"-add-account=$ACCOUNT_NAME\", \"-zenctl=$ZENCTL_URL\"]"
  elif [ "$1" == "remove-account" ]; then
    if [ -z "$2" ]; then
      echo "Please provide an <account-name> parameter."
      exit 1
    fi
    SZA_ARGS="[\"-remove-account=$ACCOUNT_NAME\", \"-zenctl=$ZENCTL_URL\"]"
  elif [ "$1" == "get-adminkey" ]; then
    SZA_ARGS="[\"-get-adminkey=$ACCOUNT_NAME\"]"
  elif [ "$1" == "get-apikey" ]; then
    SZA_ARGS="[\"-get-apikey=$ACCOUNT_NAME\"]"
  elif [ "$1" == "generate-apikey" ]; then
    SZA_ARGS="[\"-generate-apikey=$ACCOUNT_NAME\", \"-zenctl=$ZENCTL_URL\"]"
  elif [ "$1" == "generate-adminkey" ]; then
    SZA_ARGS="[\"-generate-adminkey=$ACCOUNT_NAME\", \"-zenctl=$ZENCTL_URL\"]"
  elif [ "$1" == "get-logs" ]; then
    printAllLogs
    exit 0
  elif [ "$1" == "remove-key" ]; then
    if [ -z "$2" ]; then
      echo "Please provide an <account-name> parameter."
      exit 1
    fi
    if [ -z "$3" ]; then
      echo "Please provide the key value to be removed."
      exit 1
    fi
    SZA_ARGS="[\"-remove-key-account=$2\", \"-remove-key-value=$3\", \"-zenctl=$ZENCTL_URL\"]"
  elif [ "$1" == "request" ]; then
    if [ -z "$2" ]; then
      echo "Please provide an <account-name> parameter."
      exit 1
    fi
    if [ -z "$3" ]; then
      echo "Please provide a GraphQL request (e.g. 'query { version { version_tag } }') to be executed."
      exit 1
    fi
    SZA_ARGS="[\"-request-account=$2\", \"-request-value=$3\", \"-zenctl=$ZENCTL_URL\"]"
  else
    echo "Usage: $0 add-account|remove-account|get-apikey|get-adminkey|generate-apikey|generate-adminkey <account-name>"
    echo "       $0 remove-key <account-name> <key>"
    echo "       $0 get-logs"
    echo "       $0 request <account-name> <graphql>"
    exit 1
  fi
fi



if [ -z "$SZA_CONTAINER_ENV" ]; then
  SZA_CONTAINER_ENV="[{
        \"name\": \"STEPZEN_CONTROL_DB_DSN\",
        \"valueFrom\": {
          \"secretKeyRef\": {
            \"name\": \"$SZA_MDB_SECRET_NAME\",
            \"key\": \"DSN\"
          }
        }
      }]"
fi

# Function to display the loading animation
function loading_animation() {
    local i=0
    while true; do
        printf "\r[%c] Waiting for pod to complete... " "${SPINNER:$i:1}"
        sleep "$DELAY"
        i=$(((i + 1) % 4))
    done
}

# Start the loading animation in the background
{ loading_animation & } 2>/dev/null
trap 'kill $!; exit' INT

kubectl get secret "$SZA_PULL_SECRET_NAME" 1>/dev/null || {
    echo "no access to secrets with name $SZA_PULL_SECRET_NAME - did you run kubectl login?" >&2
    # Kill loading animation
    kill %1
    exit 1
}

kubectl get secret "$SZA_MDB_SECRET_NAME" 1>/dev/null || {
    echo "no access to secrets with name $SZA_MDB_SECRET_NAME - did you run kubectl login?" >&2
    # Kill loading animation
    kill %1
    exit 1
}

# If pod exists delete it
kubectl delete pod $APP_NAME >/dev/null 2>&1

function cleanup() {
    # Kill loading animation
    { kill $! && wait; } 2>/dev/null
    echo

    # Print Pod logs
    kubectl logs -f "$APP_NAME"

    # Delete existing pod
    kubectl delete pod "$APP_NAME" >/dev/null
}

OVERRIDES="
{
  \"spec\": {
    \"containers\":[{
      \"name\": \"$APP_NAME\",
      \"image\": \"$SZA_IMAGE\",
      \"args\": $SZA_ARGS,
      \"env\": $SZA_CONTAINER_ENV
    }],
    \"imagePullSecrets\": [{\"name\": \"$SZA_PULL_SECRET_NAME\"}]
  }
}"

# Create a Pod
kubectl run "$APP_NAME" --image="$SZA_IMAGE" --image-pull-policy=Always --restart=Never --overrides="$OVERRIDES" >/dev/null

# Loop until the container is in "Completed" state or Error
while true; do
    status=$(kubectl get pod "$APP_NAME" -o jsonpath="{.status.containerStatuses[?(@.name=='$APP_NAME')].state.terminated.reason}" 2>/dev/null)
    if [[ "$status" == "Completed" ]]; then
        cleanup
        exit 0
    elif [[ "$status" == "Error" ]]; then
        cleanup
        exit 1
    else
        sleep 5
    fi
done
