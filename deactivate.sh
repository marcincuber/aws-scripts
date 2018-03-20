#!/bin/bash
#
max_key_age_days=500

get_all_users() {
  aws iam list-users > users
}

get_access_keys() {
  aws iam list-access-keys --user-name "${1}" > existing-keys
}

# Usage: rotate_keys ${username} ${key_id}
deactivate_access_key() {
  aws iam update-access-key --user-name "${1}" --access-key-id "${2}" --status Inactive 
}

# Usage: rotate_keys ${keys} ${max_key_age_days}
rotate_keys() {
  jq -c '.AccessKeyMetadata[]' ${1} | while read key_entry; do
  date_created=$(echo ${key_entry} |jq .CreateDate -r)
  key_id=$(echo ${key_entry} |jq .AccessKeyId -r)
  user_id=$(echo ${key_entry} |jq .UserName -r)
  key_status=$(echo ${key_entry} |jq .Status -r)

  key_age_days=$(bash ./date.sh "${date_created}")

  if [ "${key_age_days}" -gt "${2}" ] ; then
    echo "Key with ID: ${key_id} for user ${user_id} is older than ${max_key_age_days} days with status: ${key_status}."
    if [ "${key_status}" = "Active"  ] ; then
      echo "Deactivating key with id ${key_id}"
      deactivate_access_key ${user_id} ${key_id}
    fi
  fi
  done
}

##### Main #####
get_all_users
users_file=$(pwd)/users

jq -cr '.Users[].UserName' ${users_file} | while read username; do
  get_access_keys ${username}
  keys_file=$(pwd)/existing-keys
  rotate_keys ${keys_file} ${max_key_age_days}
done

rm users existing-keys
