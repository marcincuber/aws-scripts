#!/usr/bin/env bash

# ================================================================
# === DESCRIPTION
# ================================================================
#
# Summary: Script to rotate keys for a specific user or 
#          deactivate/delete IAM keys for aws users.
#
# Author: marcincuber@hotmail.com
#
# ================================================================
# === FUNCTIONS
# ================================================================

Help() {
    echo "usage: ${__dir}/aws_iam_keys_main.sh [options...] "
    echo "options:"
    echo " -d  --deactivate    Deactivate IAM keys for all_users or with specific email which are older than provided number of days."
    echo " -rm --remove        Remove IAM keys for all_users or with specific email which are older than provided number of days."
    echo " -a  --key-file      The file for the .csv access key file for an AWS administrator. Optional."
    echo " -u  --user          The IAM user whose key you want to rotate. Required."
    echo " -j  --json          Name of the final to output new credentials. Optional."    
    echo " -r  --reconfigure   Set this to any non-empty value to reconfigure AWS CLI credentials. Optional."
    echo "     --help          Prints this help message"
}

Deactivate_keys() {
  . "$__dir/deactivate.sh"
}

Remove_keys() {
  . "$__dir/delete.sh"
}


# ================================================================
# === INITIALIZATION
# ================================================================

# Exit on error
set -o errexit
set -o pipefail

# Set dir variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ======================================================
# === PARSE COMMAND-LINE OPTIONS
# ======================================================

IAM_USER=
AWS_KEY_FILE=
JSON_OUTPUT_FILE=
RECONFIGURE=

# Check if any arguments were passed. If not, print an error
if [ $# -eq 0 ]; then
    >&2 echo "Please specify arguments when running function."
    Help
    exit 2
fi

# Assign options to variables
while [ "${1}" != "" ]; do
    case "${1}" in
        -d | --deactivate) shift
                      Deactivate_keys
                      ;;
        -rm | --remove) shift
                      Remove_keys
                      ;;
        -u | --user)  shift
                      IAM_USER="${1}"
                      ;;
        -a | --key-file) shift
                      AWS_KEY_FILE="${1}"
                      ;;
        -j | --json)  shift
                      JSON_OUTPUT_FILE="${1}"
                      ;;
        -r | --reconfigure) shift
                      RECONFIGURE="${1}"
                      ;;
        -h | --help)  Help
                      exit 0
                      ;;
        *)            >&2 echo "error: invalid option: ${1}"
                      Help
                      exit 3
    esac
    shift
done

# Make sure that all the required arguments were passed into the script
if [[ -z "${IAM_USER}" ]] ; then
    >&2 echo "error: too few arguments"
    Help
    exit 0
fi

AWS_get_account() {
  aws iam list-account-aliases |jq .AccountAliases[] -r
}

AWS_user_details() {
  aws iam get-user |jq .User -r
}

ConfigureAwsCli() {
# Configure the AWS command-line tool with the proper credentials

    if [[ ! -z "${AWS_KEY_FILE}" ]] ; then
        echo "Using the AWS administrator key file specified."

        AWS_ACCESS_KEY_ID=$(awk -F ',' 'NR==2 {print $2}' "${AWS_KEY_FILE}")
        AWS_SECRET_ACCESS_KEY=$(awk -F ',' 'NR==2 {print $3}' "${AWS_KEY_FILE}")

        # Configure temp profile
        aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
        aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
    else
      echo "Using existing AWS credentials"
      echo "${AWS_account_name}"
      echo "AWS account id: ${Current_user_details}"
    fi
}

# ======================================================
# === KEY ROTATION SCRIPT
# ======================================================

AWS_account_name=$(AWS_get_account)
Current_user_details=$(AWS_user_details)
Temp_role_name=${AWS_account_name}-temp-role

ConfigureAwsCli

# Max 2 IAM keys allowed.
cd "${__dir}"

echo "Verifying number of keys attached to IAM"
aws iam list-access-keys --output json --user-name "${IAM_USER}" > existing-keys
NUM_OF_KEYS=$(grep -c "AccessKeyId" existing-keys)

if [ "${NUM_OF_KEYS}" -gt 1 ] ; then
  echo "There are already two keys in-use for this user (which is the max per IAM user). Unable to rotate keys."
  rm existing-keys
  exit 2
fi

# Get the existing key
EXISTING_KEY_ID=$(awk '/.AccessKeyId./{print substr($2,2,length($2)-2)}' existing-keys)
echo "Existing key Id: ${EXISTING_KEY_ID}"
rm existing-keys

# Create a new access key in AWS for the IAM user
echo "Creating new access key for IAM user..."
aws iam create-access-key --output json --user-name "${IAM_USER}" > temp-key
NEW_AWS_ACCESS_KEY_ID=$(awk '/.AccessKeyId./{print substr($2,2,length($2)-2)}' temp-key)
NEW_AWS_SECRET_ACCESS_KEY=$(awk '/.SecretAccessKey./{print substr($2,2,length($2)-3)}' temp-key)
rm temp-key

#######
#
#  Test access with the freshly generated temp-key
#
######

echo "Testing new key..."
echo "New key Id: ${NEW_AWS_ACCESS_KEY_ID}"

# Configure a temp profile using the new IAM key to test with
aws configure --profile ${Temp_role_name} set aws_access_key_id "${NEW_AWS_ACCESS_KEY_ID}"
aws configure --profile ${Temp_role_name} set aws_secret_access_key "${NEW_AWS_SECRET_ACCESS_KEY}"

# Wait for key to propagate in AWS
echo "Pausing to wait for the IAM changes to propagate..."
COUNT=0
MAX_COUNT=4
SUCCESS=false
while [ "${SUCCESS}" = false ] && [ "${COUNT}" -lt "${MAX_COUNT}" ]; do
    sleep 15
    account_temp_role=$(aws iam --profile ${Temp_role_name} list-account-aliases |jq .AccountAliases[] -r)
    userid_temp_role=$(aws iam --profile ${Temp_role_name} get-user |jq .User.UserId -r)
    userid_current_role=$(echo ${Current_user_details} | jq .UserId -r)
    if [[ "${account_temp_role}" == "${AWS_account_name}" ]] && [[ "${userid_temp_role}" == "${userid_current_role}" ]] ; then
        SUCCESS=true
    else
       COUNT=$((COUNT+1))
    fi
done

#######
#
#  End Key testing
#
#######

# If the test was successful, continue. Otherwise rollback.
if [ "${SUCCESS}" = true ]; then
  echo "Successfully used new key."

  # Disable the old key, and re-try the test.
  aws iam update-access-key  --user-name "${IAM_USER}" --access-key-id "${EXISTING_KEY_ID}" --status Inactive
  
  # Get account and userid values again to test the new keys
  account_temp_role_2=$(aws iam --profile ${Temp_role_name} list-account-aliases |jq .AccountAliases[] -r)
  userid_temp_role_2=$(aws iam --profile ${Temp_role_name} get-user |jq .User.UserId -r)
  if [[ "${account_temp_role_2}" == "${AWS_account_name}" ]] && [[ "${userid_temp_role_2}" == "${userid_current_role}" ]] ; then
    SUCCESS=true
  else
    SUCCESS=false
  fi

  # If the second test was successful, then delete the old key. Otherwise, notify the user and exit.
  if [ "${SUCCESS}" = true ]; then
    if [[ ! -z "${RECONFIGURE}" ]]; then
      echo "Successfully used new key after inactivating the old key. Reconfiguring AWS CLI with new key..."
      aws configure set aws_access_key_id "${NEW_AWS_ACCESS_KEY_ID}"
      aws configure set aws_secret_access_key "${NEW_AWS_SECRET_ACCESS_KEY}"
    fi
    echo "Deleting the old key..."
    aws iam delete-access-key --profile ${Temp_role_name} --user-name "${IAM_USER}" --access-key-id "${EXISTING_KEY_ID}"
  else
    >&2 echo "Test failed after trying deactiving the old key. Reactivating the key and stopping the rotation."
    aws iam update-access-key  --user-name "${IAM_USER}" --access-key-id "${EXISTING_KEY_ID}" --status Active
    exit 6
  fi
else
  >&2 echo "Access test failed for new key. Unable to rotate keys. Rolling back"
  aws iam delete-access-key --user-name "${IAM_USER}" --access-key-id "${NEW_AWS_ACCESS_KEY_ID}"
  exit 7
fi

# Print the JSON file if requested
if [[ ! -z "${JSON_OUTPUT_FILE}" ]]; then
    echo "Outputing JSON..."
    printf '
    {
        "User":"%s",
        "New_Aws_Access_Key_Id":"%s",
        "New_Aws_Secret_Access_Key": "%s"
    }\n' "${IAM_USER}" "${NEW_AWS_ACCESS_KEY_ID}" "${NEW_AWS_SECRET_ACCESS_KEY}" > "${JSON_OUTPUT_FILE}"
fi