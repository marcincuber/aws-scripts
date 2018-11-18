#!/usr/bin/env bash
# ================================================================
# === DESCRIPTION
# ================================================================
# 
# File name: deactivate.sh
# 
# Summary: Script to deactivate iam keys that are older than specified number of days.
#     
# 
# Author: marcincuber@hotmail.com

# Set variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================================================================
# === FUNCTIONS
# ================================================================

# Get email address of our current user who is executing this script
current_user_email() {
  aws iam get-user |jq .User.UserName -r
}

# List all users and add it to users file
get_all_users() {
  aws iam list-users > users
}

# Get all keys for the user and add it to existing-keys file
get_access_keys() {
  aws iam list-access-keys --user-name "${1}" > existing-keys
}

# Usage: deactivate_access_key ${username} ${key_id}
deactivate_access_key() {
  aws iam update-access-key --user-name "${1}" --access-key-id "${2}" --status Inactive 
}

# Usage: deactivate_keys_for_news ${keys} ${max_key_age_days}
deactivate_keys_for_news() {
  keys=${1}
  max_key_age=${2}
  
  current_account_email=$(current_user_email)

  jq -c '.AccessKeyMetadata[]' ${keys} | while read key_entry; do
  date_created=$(echo ${key_entry} |jq .CreateDate -r)
  key_id=$(echo ${key_entry} |jq .AccessKeyId -r)
  user_id=$(echo ${key_entry} |jq .UserName -r)
  key_status=$(echo ${key_entry} |jq .Status -r)
  
  # Calculate key age in days
  key_age_days=$(. "$__dir/date.sh" "${date_created}")

  if [[ "${key_age_days}" -gt "${max_key_age}" ]] && [[ ${user_id} == *@news.co.uk ]] && ! [[ "${user_id}" == "${current_account_email}" ]] ; then
    echo "Key with ID: ${key_id} for user ${user_id} is older than ${max_key_age_days} days with status: ${key_status}."
    if [[ "${key_status}" = "Active"  ]] ; then
      echo "Deactivating key with id ${key_id}"
      deactivate_access_key ${user_id} ${key_id}
    fi
  fi
  done
}

# Usage: deactivate_keys_for_all_users ${keys} ${max_key_age_days}
deactivate_keys_for_all_users() {
  keys=${1}
  max_key_age=${2}
  
  current_account_email=$(current_user_email)

  jq -c '.AccessKeyMetadata[]' ${keys} | while read key_entry; do
  date_created=$(echo ${key_entry} |jq .CreateDate -r)
  key_id=$(echo ${key_entry} |jq .AccessKeyId -r)
  user_id=$(echo ${key_entry} |jq .UserName -r)
  key_status=$(echo ${key_entry} |jq .Status -r)
  
  # Calculate key age in days
  key_age_days=$(. "$__dir/date.sh" "${date_created}")

  if [[ "${key_age_days}" -gt "${max_key_age}" ]] && ! [[ "${user_id}" == "${current_account_email}" ]] ; then
    echo "Key with ID: ${key_id} for user ${user_id} is older than ${max_key_age_days} days with status: ${key_status}."
    if [[ "${key_status}" = "Active"  ]] ; then
      echo "Deactivating key with id ${key_id}"
      deactivate_access_key ${user_id} ${key_id}
    fi
  fi
  done
}

iterate_remove() {
  remove_func=${1}

  get_all_users
  users_file=${__dir}/users
  
  jq -cr '.Users[].UserName' ${users_file} | while read username; do
    get_access_keys ${username}
    keys_file=${__dir}/existing-keys
    ${remove_func} ${keys_file} ${max_key_age_days}
  done

  rm users existing-keys
}

# ======================================================
# === MAIN SCRIPT WITH INPUTS
# ======================================================

# Exit if there is an error in the script. Get last error for piped commands
set -o errexit
set -o pipefail

# Prompt for age of keys and verify input
echo "Enter the max age of your key in days:"
read max_key_age_days
if ! [[ "${max_key_age_days}" =~ ^[+]?[0-9]+$ ]]
  then
    echo "Invalid input, exiting."
    exit 0
fi

echo "Deactivate keys for: "
options=("All users" "NewsUK users" "Exit")
select opt in "${options[@]}"
do
  case ${opt} in
    "All users")
      echo "You chose to deactivate keys for all users"
      iterate_remove deactivate_keys_for_all_users
      exit 0
      ;;
    "NewsUK users")
      echo "You chose to deactivate keys for users with email ending @news.co.uk"
      iterate_remove deactivate_keys_for_news
      exit 0
      ;;
    "Exit")
      exit 0
      ;;
    *) echo invalid option;;
  esac
done
