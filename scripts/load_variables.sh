#!/bin/bash

# Load the .env file and set the environment variables
set -a

current_directory="$(dirname "$(readlink -f "$0")")"
IFS="/" read -ra dir_array <<< "${current_directory#/}"  # Remove leading slash
if [ ${#dir_array[@]} -eq 3 ] && [ "${dir_array[2]}" != "scripts" ]; then
    parsed_dir="/${dir_array[0]}/${dir_array[1]}/${dir_array[2]}"
else
    parsed_dir="/${dir_array[0]}/${dir_array[1]}"
fi
source "${parsed_dir}/.env"

set +a

# Set default values for optional variables if not set or empty
: ${NODE_CLIENT:=reth}
: ${SNAPSHOT:=false}
: ${SYNC_FROM:=chain}
: ${BASE_DIR:=chain}
: ${RETH_VERSION:=0.1.0}
: ${LIGHTHOUSE_VERSION:=4.2.0}
: ${PROMETHEUS_VERSION:=2.45.0}
: ${S3_PROVIDER:=wasabi}
: ${S3_BUCKET_NAME:=rpc-backups}
: ${AWS_ACCESS_KEY:=}
: ${AWS_SECRET_KEY:=}
: ${AWS_REGION:=}

# Generate a secure password if NGINX_USER or NGINX_PASS is not set
if [[ -z $NGINX_USER ]]; then
    NGINX_USER="user"
fi

if [[ -z $NGINX_PASS ]]; then
  nginx_auth_file="${parsed_dir}/nginx_auth.txt"
  # check for nginx_auth.txt file to avoid generating new credentials on every run
  if [[ -f nginx_auth_file ]]; then
      echo "Loading autogenerated nginx credentials from ${nginx_auth_file}"
      NGINX_USER=$(awk -F':' '{print $1}' nginx_auth_file)
      NGINX_PASS=$(awk -F':' '{print $2}' nginx_auth_file)
  else
      NGINX_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 12)
      # Save the nginx user and password to nginx_auth.txt
      echo -e "$NGINX_USER:$NGINX_PASS" > ${nginx_auth_file}
      echo "NGINX_USER and NGINX_PASS not set. NGINX_USER has been set to $NGINX_USER, NGINX_PASS has been set to $NGINX_PASS"
      echo "Generated credentials saved to ${nginx_auth_file}"
  fi
fi

# Check if SNAPSHOT is set to a valid value
if [[ "$SNAPSHOT" != "true" && "$SNAPSHOT" != "false" ]]; then
    SNAPSHOT="false"  # Set default value
    echo "Invalid SNAPSHOT set, defaulting to: false"
fi

# Check if SYNC_FROM is set to a valid value
if [[ "$SYNC_FROM" != "public" && "$SYNC_FROM" != "personal" && "$SYNC_FROM" != "chain" ]]; then
    SYNC_FROM="chain"  # Set default value
    echo "Invalid SYNC_FROM set, defaulting to: chain"
fi

# Check if S3_PROVIDER is set to a valid value
if [[ "$S3_PROVIDER" != "wasabi" && "$S3_PROVIDER" != "aws" ]]; then
    echo "S3_PROVIDER must be set to either 'wasabi' or 'aws'. Exiting."
    exit 1
fi

# Check if SNAPSHOT is true and necessary snapshot-related variables are empty
if [[ $SNAPSHOT == "true" && ( -z $S3_PROVIDER || -z $S3_BUCKET_NAME || -z $AWS_ACCESS_KEY || -z $AWS_SECRET_KEY || -z $AWS_REGION ) ]]; then
    echo "When SNAPSHOT is set to true, S3_PROVIDER, S3_BUCKET_NAME, AWS_ACCESS_KEY, AWS_SECRET_KEY, and AWS_REGION must be set."
    exit 1
fi

# Check if SYNC_FROM is private and necessary snapshot-related variables are empty
if [[ $SYNC_FROM == "private" && ( -z $S3_PROVIDER || -z $S3_BUCKET_NAME || -z $AWS_ACCESS_KEY || -z $AWS_SECRET_KEY || -z $AWS_REGION ) ]]; then
    echo "When SYNC_FROM is set to private, S3_PROVIDER, S3_BUCKET_NAME, AWS_ACCESS_KEY, AWS_SECRET_KEY, and AWS_REGION must be set."
    exit 1
fi

# Set SYNC_FROM_BUCKET based on SYNC_FROM value
if [[ $SYNC_FROM == "private" ]]; then
    SYNC_FROM_BUCKET=$S3_BUCKET_NAME
elif [[ $SYNC_FROM == "public" ]]; then
    SYNC_FROM_BUCKET="rpc-backups"
else
    SYNC_FROM_BUCKET=""
fi

