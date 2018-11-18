#!/usr/bin/env bash
# ================================================================
# === DESCRIPTION
# ================================================================
# 
# File name: delete.sh
# 
# Summary: Script to remove IAM keys that are older than specified number of days.
#          You can specify whether to remove Active or Inactive keys or Both.
# 
# Author: marcincuber@hotmail.com

# Set dir variables
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

# Usage: remove_access_key ${username} ${key_id}
remove_access_key() {
  aws iam delete-access-key --user-name "${1}" --access-key-id "${2}"
}

# Usage: remove_keys_for_news ${keys} ${max_key_age_days}
remove_keys_for_news() {
  keys=${1}
  max_key_age=${2}
  key_status_to_remove=${3}
  
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
    if [[ "${key_status}" = "Active" ]] && [[ "${key_status_to_remove}" = "Active" ]] ; then
      echo "Removing key with id ${key_id} with key_status: ${key_status} and keys_status_to_remove ${key_status_to_remove}"
      remove_access_key ${user_id} ${key_id}
    elif [[ "${key_status}" = "Inactive" ]] && [[ "${key_status_to_remove}" = "Inactive" ]] ; then
      echo "Removing key with id ${key_id} with key_status: ${key_status} and keys_status_to_remove ${key_status_to_remove}"
      remove_access_key ${user_id} ${key_id}
    elif [[ "${key_status_to_remove}" = "Both" ]] ; then
      echo "Removing all keys because keys_status_to_remove is ${key_status_to_remove} Active and InActive"
      remove_access_key ${user_id} ${key_id}
    fi
  fi
  done
}

# Usage: remove_keys_for_all_users ${keys} ${max_key_age_days}
remove_keys_for_all_users() {
  keys=${1}
  max_key_age=${2}
  key_status_to_remove=${3}
  
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
    if [[ "${key_status}" = "Active" ]] && [[ "${key_status_to_remove}" = "Active" ]] ; then
      echo "Removing key with id ${key_id} with key_status: ${key_status} and keys_status_to_remove ${key_status_to_remove}"
      remove_access_key ${user_id} ${key_id}
    elif [[ "${key_status}" = "Inactive" ]] && [[ "${key_status_to_remove}" = "Inactive" ]] ; then
      echo "Removing key with id ${key_id} with key_status: ${key_status} and keys_status_to_remove ${key_status_to_remove}"
      remove_access_key ${user_id} ${key_id}
    elif [[ "${key_status_to_remove}" = "Both" ]] ; then
      echo "Removing all keys because keys_status_to_remove is ${key_status_to_remove} Active and InActive"
      remove_access_key ${user_id} ${key_id}
    fi
  fi
  done
}

iterate_remove() {
  remove_func=${1}
  opt_status=${2}

  get_all_users
  users_file=${__dir}/users
  
  jq -cr '.Users[].UserName' ${users_file} | while read username; do
    get_access_keys ${username}
    keys_file=${__dir}/existing-keys
    ${remove_func} ${keys_file} ${max_key_age_days} ${opt_status}
  done

  rm users existing-keys
}

promp_remove() {
  opt_status=${1}
  echo "Remove keys for: "
  options=("All users" "NewsUK users" "Exit")
  select opt in "${options[@]}"
  do
    case ${opt} in
      "All users")
        echo "You chose to delete keys for all users"
        iterate_remove remove_keys_for_all_users ${opt_status}
        ;;
      "NewsUK users")
        echo "You chose to delete keys for users with email ending @news.co.uk"
        iterate_remove remove_keys_for_news ${opt_status}
        ;;
      "Exit")
        break
        ;;
      *) echo invalid option;;
    esac
  done
}

# ======================================================
# === MAIN SCRIPT WITH INPUTS
# ======================================================

# Exit on error
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

echo "Remove keys older than ${max_key_age_days} days that are: "
options_status=("Inactive" "Active" "Both" "Exit")
select opt_stat in "${options_status[@]}"
do
  case ${opt_stat} in
    "Inactive")
      echo "You chose to remove keys that are Inactive and older than ${max_key_age_days} days."
      promp_remove ${opt_stat}
      ;;
    "Active")
      echo "You chose to remove keys that are Active and older than ${max_key_age_days} days."
      promp_remove ${opt_stat}
      ;;
    "Both")
      echo "You chose to remove keys Active and Inactive which are older than ${max_key_age_days} days."
      promp_remove ${opt_stat}
      ;;
    "Exit")
      break
      ;;
    *) echo invalid option;;
  esac
done
