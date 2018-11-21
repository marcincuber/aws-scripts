#!/usr/bin/env bash

bold=$(tput bold)
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
cyan=$(tput setaf 6)
reset=$(tput sgr0)

Help() {
    echo "usage: ${__dir}/rotate_keys_profiles.sh [options...] "
    echo "options:"
    echo " -d  --debug    Enable debug mode. Optional."
    echo " -h  --help     Prints this help message."
}

aws_account_alias() {
  aws iam list-account-aliases --profile="${1}" --query 'AccountAliases[]' --output text
}

aws_account_id() {
  aws sts get-caller-identity --profile="${1}" --query 'Account' --output text
}

aws_user_email() {
  aws iam get-user --profile="${1}" --query 'User.UserName' --output text
}

aws_list_key_ids() {
  aws iam list-access-keys --profile="${1}" --query 'AccessKeyMetadata[].AccessKeyId' --output text
}

aws_list_key_create_date() {
  aws iam list-access-keys --profile="${1}" --query 'AccessKeyMetadata[].CreateDate' --output text
}

Exists() {
  command -v "${1}" >/dev/null 2>&1
}

print_array() {
  # run through array and print each entry:
  local array
  array=("$@")
  for i in "${array[@]}" ; do
      printf '%s ' "${i}"
  done
  # print a new line
  printf '\n'
}

# ================================================================
# === PRE-CHECKS
# ================================================================

# AWS CLI installed?
if ! Exists aws ; then
  printf "\n******************************************************************************************************************************\n\
This script requires the AWS CLI. See the details here: http://docs.aws.amazon.com/cli/latest/userguide/cli-install-macos.html\n\
******************************************************************************************************************************\n\n"
  exit 1
fi

# ================================================================
# === INITIALIZATION
# ================================================================

# Exit on error
set -o pipefail

# Set dir variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ======================================================
# === PARSE COMMAND-LINE OPTIONS
# ======================================================
DEBUG=

# Assign options to variables
while [[ "${1}" != "" ]]; do
  case "${1}" in
    -d | --debug) 
      shift
      DEBUG="${1}"
      ;;
    -h | --help)
      Help
      exit 1
      ;;
    *)            
      >&2 echo "error: invalid option: ${1}"
      Help
      exit 1
  esac
  shift
done

CREDFILE=~/.aws/credentials
CONFIGFILE=~/.aws/config
TODAY=$(date "+%Y-%m-%d")
OS="$(uname)"

# check for ~/.aws directory, and ~/.aws/{config|credentials} files
if [[ ! -d ~/.aws ]]; then
  echo -e "'~/.aws' directory not present.\nMake sure it exists, and that you have at least one profile configured\nusing the 'config' and 'credentials' files within that directory."
  exit 1
fi
if [[ ! -f ${CONFIGFILE} && ! -f ${CREDFILE} ]]; then
  echo -e "'~/.aws/config' and '~/.aws/credentials' files not present.\nMake sure they exist. See http://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html for details on how to set them up."
  exit 1
elif [[ ! -f ${CONFIGFILE} ]]; then
  echo -e "'~/.aws/config' file not present.\nMake sure it and '~/.aws/credentials' files exists. See http://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html for details on how to set them up."
  exit 1
elif [[ ! -f ${CREDFILE} ]]; then
  echo -e "'~/.aws/credentials' file not present.\nMake sure it and '~/.aws/config' files exists. See http://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html for details on how to set them up."
  exit 1
fi

ONEPROFILE="false"

while IFS='' read -r line || [[ -n "${line}" ]]; do
  [[ "${line}" =~ ^\[(.*)\].* ]] 
  profile_ident=${BASH_REMATCH[1]}

  if [[ ${profile_ident} != "" ]]; then
    ONEPROFILE="true"
  fi 
done < ${CREDFILE}

if [[ "${ONEPROFILE}" = "false" ]]; then
  echo
  echo -e "NO CONFIGURED AWS PROFILES FOUND.\nPlease make sure you have '~/.aws/config' (profile configurations),\nand '~/.aws/credentials' (profile credentials) files, and at least\none configured profile. For more info, see AWS CLI documentation at:\nhttp://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html"
  exit 1
fi

declare -a cred_profiles
declare -a cred_allprofiles
declare -a cred_profile_arn
declare -a cred_profile_user
declare -a cred_profile_keys
declare -a key_status
cred_profilecounter=0

echo -n "Please wait"
# get profiles, keys (and their ages) for selection
while IFS='' read -r line || [[ -n "${line}" ]]; do
  [[ "${line}" =~ ^\[(.*)\].* ]]
  profile_ident=${BASH_REMATCH[1]}

  # only process if profile identifier is present,
  # and if it's not a mfasession profile
  if [[ "${profile_ident}" != "" ]] && ! [[ "${profile_ident}" =~ -mfasession$ ]]; then
    
    cred_profiles[${cred_profilecounter}]=${profile_ident}

    # get user ARN; this should be always available if the access_key_id is valid
    user_arn="$(aws sts get-caller-identity --profile "${profile_ident}" --output text --query "Arn" 2>&1)"
   
    if [[ "${user_arn}" =~ ^arn:aws ]]; then
      cred_profile_arn[${cred_profilecounter}]=${user_arn}
    elif [[ "${user_arn}" =~ InvalidClientTokenId ]]; then
      cred_profile_arn[${cred_profilecounter}]="INVALID"
    else
      cred_profile_arn[${cred_profilecounter}]=""
    fi

    # get the actual username (may be different from the arbitrary profile ident)
    if [[ "${cred_profile_arn[${cred_profilecounter}]}" =~ ^arn:aws ]]; then
      [[ "${user_arn}" =~ ([^/]+)$ ]] && cred_profile_user[${cred_profilecounter}]="${BASH_REMATCH[1]}"
    elif [[ "${cred_profile_arn[$cred_profilecounter]}" = "INVALID" ]]; then
      cred_profile_user[${cred_profilecounter}]="CHECK CREDENTIALS!"
    else
      cred_profile_user[${cred_profilecounter}]=""
    fi

    # get access keys & their ages for the profile
    key_status_accumulator=""

    if [ ${cred_profile_arn[${cred_profilecounter}]} != "INVALID" ]; then

      key_status_array_input=$(aws iam list-access-keys --profile "${profile_ident}" --output json --query AccessKeyMetadata[*].[Status,CreateDate,AccessKeyId] 2>&1)
      if [[ "${key_status_array_input}" =~ .*explicit[[:space:]]deny.* ]]; then
        key_status_array[0]="Denied"
        key_status_array[1]=""
        key_status_array[2]=$(aws --profile "${profile_ident}" configure get aws_access_key_id)
        cred_profile_arn[${cred_profilecounter}]="DENIED" 
      else
        key_status_array=($(echo "${key_status_array_input}" | grep -A2 ctive | awk -F\" '{print $2}'))
      fi

      # get the actual username (may be different from the arbitrary profile ident)
      s_no=0
      for status in ${key_status_array[@]}; do
        if [[ "${status}" == "Active" || "${status}" == "Denied" || "${status}" == "Inactive" ]]; then

          if [[ "${status}" == "Active" ]]; then
            statusword="  Active"
          elif [[ "${status}" == "Denied" ]]; then
            statusword="INSUFFICIENT PRIVILEGES TO PROCESS THE KEY"
          else
            statusword="Inactive"
          fi

          let "s_no++"
          kcd=$(echo ${key_status_array[${s_no}]} | sed 's/T/ /' | awk '{print $1}')
          let  keypos=${s_no}+1
          if [[ "${status}" != "Denied" ]]; then
            if [[ "${OS}" = "Darwin" ]]; then
              key_status_accumulator="   ${statusword} key ${key_status_array[${keypos}]} is $((($(date -jf %Y-%m-%d ${TODAY} +%s) - $(date -jf %Y-%m-%d ${kcd} +%s))/86400)) days old\n${key_status_accumulator}"
            fi
          else
            key_status_accumulator="   ${statusword} ${key_status_array[${keypos}]}\n   Restrictive policy in effect.\n"
          fi
        else
          let "s_no++"
        fi
      done
    fi

    cred_profile_keys[${cred_profilecounter}]=${key_status_accumulator}

    ## DEBUG (enable with DEBUG="true" on top of the file)
    if [[ "${DEBUG}" == "true" ]]; then
      echo
      echo "PROFILE NAME: ${profile_ident}"
      echo "USER ARN: ${cred_profile_arn[${cred_profilecounter}]}"
      echo "USER NAME: ${cred_profile_user[${cred_profilecounter}]}"
      echo "MFA ARN: ${mfa_arns[${cred_profilecounter}]}"
    ## END DEBUG
    else
      echo -n "."
    fi

    user_arn=""
    profile_ident=""
    profile_username=""
    cred_profilecounter=$((${cred_profilecounter}+1))
  fi
done < ${CREDFILE}

# create profile selections for key rotation
echo
echo
echo "CONFIGURED AWS PROFILES AND THEIR ASSOCIATED KEYS:"
echo
SELECTR=0
ITER=1
for i in "${cred_profiles[@]}"
do
  if [[ "${cred_profile_arn[${SELECTR}]}" = "INVALID" ]]; then
    echo "${red}X${reset}: ${i} (${cred_profile_user[${SELECTR}]})"
  else
    echo "${green}${ITER}${reset}: ${i} (${cred_profile_user[${SELECTR}]})"
    printf "${cred_profile_keys[${SELECTR}]}"
  fi
  echo
  let ITER=${ITER}+1
  let SELECTR=${SELECTR}+1
done

# does mfasession profile exist for the chosen profile?
mfa_profile_verify() {
  mfaprofile_exists="false"
  ITERATR=0
  while IFS='' read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^\[(.*)\].* ]] &&
      all_profile_ident=${BASH_REMATCH[1]}
    if [[ ${all_profile_ident} != "" &&
      "${all_profile_ident}" =~ ${final_selection}-mfasession ]]; then
      mfaprofile_exists="true"
      break
      let "ITERATR++"
    fi 
    all_profile_ident=""
  done < ${CREDFILE}

  # mfasession exists -- use it?
  use_mfaprofile="false"
  if [[ "${mfaprofile_exists}" = "true" ]]; then

    echo "-----------------------------------------------------------------"
    echo 
    echo -e "An MFA profile ('${final_selection}-mfasession') exists\nfor the profile whose keys you have chosen to rotate."
    echo -e "Do you want to use it to execute the key rotation for\nthe profile you selected? If MFA is being enforced\nfor the profile selected for rotation, it may not be\nauthorized to carry out its own key rotation and the MFA\nprofile may need to be used instead."
    echo -e "Note that the MFA profile session MUST BE ACTIVE for it\nto work. Select Abort below if you need to activate\nthe MFA session before proceeding."
    echo

    while true; do
      read -p "Use the MFA profile to authorize the key rotation? Yes/No/Abort " ync
      case ${ync} in
        [Yy]* ) use_mfaprofile="true"; break;;
        [Nn]* ) break;;
        [Aa]* ) echo; exit;;
          * ) echo "Please answer (y)es, (n)o, or (a)bort.";;
      esac
    done
  fi

  if [[ "${use_mfaprofile}" = "false" ]]; then
    selected_authprofile=${final_selection}
  else
    selected_authprofile=${final_selection}-mfasession

    echo "Please wait..."

    # check for expired MFA session
    EXISTING_KEYS_CREATEDATES=$(aws_list_key_create_date "${selected_authprofile}" 2>&1)
    if [[ "${EXISTING_KEYS_CREATEDATES}" =~ ExpiredToken ]]; then
      echo -e "\nYour MFA token has expired. Refresh your MFA session\nfor the profile '${final_selection}', and try again.\n\nAborting.\n"
      exit 1
    fi  
  fi
}

rotate_key_profile() {
  echo
  echo "Verifying that AWS CLI has configured credentials ..."
  ORIGINAL_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile "${final_selection}")
  ORIGINAL_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile "${final_selection}")
  if [[ -z "${ORIGINAL_ACCESS_KEY_ID}" ]]; then
    >&2 echo "ERROR: No aws_access_key_id/aws_secret_access_key configured for AWS CLI. Run 'aws configure' with your current keys."
    continue
  fi

  EXISTING_KEYS_CREATEDATES=0
  EXISTING_KEYS_CREATEDATES=($(aws_list_key_create_date "${selected_authprofile}"))
  NUM_EXISTING_KEYS=${#EXISTING_KEYS_CREATEDATES[@]}
  if [[ ${NUM_EXISTING_KEYS} -lt 2 ]]; then
    echo "You have only one existing key. Now proceeding with new key creation."
  else
    echo 
    echo "You have two keys (maximum number). You must remove one of them in order to continue..."
    echo

    IFS=$'\n' sorted_createdates=($(sort <<<"${EXISTING_KEYS_CREATEDATES[*]}"))
    unset IFS

    echo "Acquiring data for existing keys..."
    OLDER_KEY_CREATEDATE="${sorted_createdates[0]}"
    OLDER_KEY_ID=$(aws iam list-access-keys --query "AccessKeyMetadata[?CreateDate=='${OLDER_KEY_CREATEDATE}'].AccessKeyId" --output text --profile "${selected_authprofile}")
    OLDER_KEY_STATUS=$(aws iam list-access-keys --query "AccessKeyMetadata[?CreateDate=='${OLDER_KEY_CREATEDATE}'].Status" --output text --profile "${selected_authprofile}")

    NEWER_KEY_CREATEDATE="${sorted_createdates[1]}"
    NEWER_KEY_ID=$(aws iam list-access-keys --query "AccessKeyMetadata[?CreateDate=='${NEWER_KEY_CREATEDATE}'].AccessKeyId" --output text --profile "${selected_authprofile}")
    NEWER_KEY_STATUS=$(aws iam list-access-keys --query "AccessKeyMetadata[?CreateDate=='${NEWER_KEY_CREATEDATE}'].Status" --output text --profile "${selected_authprofile}")

    key_in_use=""
    allow_older_key_delete="false"
    allow_newer_key_delete="false"
    if [[ ${OLDER_KEY_STATUS} = "Active" ]] &&
      [[ ${NEWER_KEY_STATUS} = "Active" ]] &&
      [[ "${NEWER_KEY_ID}" = "${ORIGINAL_ACCESS_KEY_ID}" ]]; then
      # both keys are active, newer key is in use
      key_in_use="newer"
      allow_older_key_delete="true"
      key_id_can_delete=${OLDER_KEY_ID}
      key_id_remaining=${NEWER_KEY_ID}
    elif [[ ${OLDER_KEY_STATUS} = "Active" ]] &&
      [[ ${NEWER_KEY_STATUS} = "Active" ]] &&
      [[ "${OLDER_KEY_ID}" = "${ORIGINAL_ACCESS_KEY_ID}" ]]; then
      # both keys are active, older key is in use 
      key_in_use="older"
      allow_newer_key_delete="true"
      key_id_can_delete=${NEWER_KEY_ID}
      key_id_remaining=${OLDER_KEY_ID}
    elif [[ ${OLDER_KEY_STATUS} = "Inactive" ]] &&
      [[ ${NEWER_KEY_STATUS} = "Active" ]]; then
      # newer key is active and in use
      key_in_use="newer"
      allow_older_key_delete="true"
      key_id_can_delete=${OLDER_KEY_ID}
      key_id_remaining=${NEWER_KEY_ID}
    elif [[ ${OLDER_KEY_STATUS} = "Active" ]] &&
      [[ ${NEWER_KEY_STATUS} = "Inactive" ]]; then
      # older key is active and in use
      key_in_use="older"
      allow_newer_key_delete="true"
      key_id_can_delete=${NEWER_KEY_ID}
    else
      echo "You don't have keys that can be deleted. Please delete a key manually and then try again."
      echo "Details:"
      echo "AWS account ID: $(aws_account_id "${selected_authprofile}")"
      echo "AWS account alias: $(aws_account_alias "${selected_authprofile}")"
      echo "Key IDs to review: $(aws_list_key_ids "${selected_authprofile}")"
      echo "Keys belong to: $(aws_user_email "${selected_authprofile}")"
      continue
    fi
  fi

  if [[ "${allow_older_key_delete}" = "true" ]] || [[ "${allow_newer_key_delete}" = "true" ]]; then
    echo "To proceed you must delete one of your two existing keys; they are listed below:"
    echo
    echo "${green}OLDER KEY (${OLDER_KEY_STATUS}, created on ${OLDER_KEY_CREATEDATE})${reset}:"
    echo -n "Key ID: ${red}${OLDER_KEY_ID}${reset} "
    if [[ "${allow_older_key_delete}" = "true" ]]; then 
      echo "(this key can be deleted)" 
    elif [[ "${key_in_use}" = "older" ]]; then
      echo "(this key is currently your active key)"
    fi
    echo
    echo "${green}NEWER KEY (${NEWER_KEY_STATUS}, created on ${NEWER_KEY_CREATEDATE})${reset}:"
    echo -n "Key ID: ${red}${NEWER_KEY_ID}${reset} "
    if [[ "${allow_newer_key_delete}" = "true" ]]; then 
      echo "(this key can be deleted)"
    elif [[ "${key_in_use}" = "newer" ]]; then
      echo "(this key is currently your active key)"
    fi
    echo
    echo "Enter the Key ID of the key to delete, or leave empty to cancel, then press enter." 
    read key_in

    if [[ "${key_in}" = "${key_id_can_delete}" ]]; then
      echo "Now deleting the key ${key_id_can_delete}"
      aws iam delete-access-key --access-key-id "${key_id_can_delete}" --profile "${selected_authprofile}"
      if [[ $? -ne 0 ]]; then
        echo
        echo "Could not delete the access keyID ${key_id_can_delete}. Cannot proceed."
        if [[ "${use_mfaprofile}" = "true" ]]; then
          echo -e "\nNOTE: If you see access denied/not authorized error above,\nyour MFA session may have expired.\n"
        else
          echo -e "\nNOTE: If you see access denied/not authorized error above, you may need\nto use MFA session to authorize the key rotation.\n"
        fi
        echo "Aborting."
        continue
      fi
    elif [[ "${key_in}" = "" ]]; then
      echo "You didn't provide Key ID. Remove key manually."
      continue
    else
      echo "The input did not match the Access Key ID of the key that can be deleted. Run the script again to retry or remove manually."
      continue
    fi
  fi

  echo
  echo "Creating a new access key for the current IAM user..."
  NEW_KEY_RAW_OUTPUT=$(aws iam create-access-key --output text --profile "${selected_authprofile}")
  NEW_KEY_DATA=($(printf '%s' "${NEW_KEY_RAW_OUTPUT}" | awk {'printf ("%5s\t%s", $2, $4)'}))
  NEW_AWS_ACCESS_KEY_ID="${NEW_KEY_DATA[0]}"
  NEW_AWS_SECRET_ACCESS_KEY="${NEW_KEY_DATA[1]}"

  echo "Pausing to wait for the IAM changes to propagate..."
  COUNT=0
  MAX_COUNT=10
  SUCCESS="false"
  while [[ "${SUCCESS}" = "false" ]] && [[ "${COUNT}" -lt "${MAX_COUNT}" ]]; do
    sleep 5
    EXISTING_KEYS_ACCESS_IDS=($(aws_list_key_ids "${selected_authprofile}"))
    NUM_EXISTING_KEYS=${#EXISTING_KEYS_ACCESS_IDS[@]}

    aws iam list-access-keys --profile "${selected_authprofile}" > /dev/null && RETURN_CODE=$? || RETURN_CODE=$?
    if [[ "${RETURN_CODE}" -eq 0 && ${NUM_EXISTING_KEYS} -eq 2 ]]; then
      SUCCESS="true"
    elif [[ ${NUM_EXISTING_KEYS} -lt 2 ]]; then
      echo "The new key was not created yet. Waiting..."
      COUNT=$((COUNT+1))
    else
      COUNT=$((COUNT+1))
      echo "(Still waiting for the key propagation to complete...)"
    fi
  done

  if [[ "${SUCCESS}" = "true" ]]; then

    echo "${green}Key propagation complete.${reset} Configuring new access key for profile: ${cyan}${final_selection}${reset}."
    aws configure set aws_access_key_id "${NEW_AWS_ACCESS_KEY_ID}" --profile "${final_selection}"
    aws configure set aws_secret_access_key "${NEW_AWS_SECRET_ACCESS_KEY}" --profile "${final_selection}"

    echo "Verifying the new key is in place, and that IAM access still works ..."
    revert="false"
    CONFIGURED_ACCESS_KEY=$(aws configure get aws_access_key_id --profile "${final_selection}")
    if [[ "${CONFIGURED_ACCESS_KEY}" != "${NEW_AWS_ACCESS_KEY_ID}" ]]; then
      >&2 echo "Something went wrong; the new key could not be taken into use; the local 'aws configure' failed."
      revert="true"
    fi

    # final test
    COUNT=0
    MAX_COUNT=10
    SUCCESS_TEST="false"
    while [[ "${SUCCESS_TEST}" = "false" ]] && [[ "${COUNT}" -lt "${MAX_COUNT}" ]]; do
      sleep 5
      EXISTING_KEYS_ACCESS_IDS=($(aws_list_key_ids "${selected_authprofile}"))
      NUM_EXISTING_KEYS=${#EXISTING_KEYS_ACCESS_IDS[@]}

      if [[ ${NUM_EXISTING_KEYS} -eq 2 ]]; then
        SUCCESS_TEST="true"
      else
        COUNT=$((COUNT+1))
      fi
    done

    if [[ ${SUCCESS_TEST} = "false" ]]; then
      >&2 echo "Something went wrong; the new key could not access AWS CLI."
      revert="true"
    fi

    if [[ "${revert}" = "true" ]]; then
      echo "Reverting configuration to use the old keys."
      aws configure set aws_access_key_id "${ORIGINAL_ACCESS_KEY_ID}" --profile "${final_selection}"
      aws configure set aws_secret_access_key "${ORIGINAL_SECRET_ACCESS_KEY}" --profile "${final_selection}"

      echo "Original configuration restored."
      continue
    fi

    echo "Deleting the previously active access key: ${ORIGINAL_ACCESS_KEY_ID}."
    aws iam delete-access-key --access-key-id "${ORIGINAL_ACCESS_KEY_ID}" --profile "${selected_authprofile}"

    echo "Verifying old access key got deleted ..."
    # this is just to test access via AWS CLI; the content here doesn't matter (other than that we get a result)
    COUNT=0
    MAX_COUNT=10
    SUCCESS_DEL="false"
    while [[ "${SUCCESS_DEL}" = "false" ]] && [[ "${COUNT}" -lt "${MAX_COUNT}" ]]; do
      sleep 5
      EXISTING_KEYS_ACCESS_IDS=($(aws_list_key_ids "${selected_authprofile}"))
      NUM_EXISTING_KEYS=${#EXISTING_KEYS_ACCESS_IDS[@]}

      if [[ ${NUM_EXISTING_KEYS} -eq 1 ]]; then
        SUCCESS_DEL="true"
      else
        COUNT=$((COUNT+1))
        echo "(Still waiting for the key to be deleted...)"
      fi
    done

    if [[ ${SUCCESS_DEL} = "false" ]]; then
      echo
      >&2 echo "Something went wrong deleting the old key, however, YOUR NEW KEY IS NOW IN USE."
      if [[ "${use_mfaprofile}" = "true" ]]; then
        echo -e "\nNOTE: If you see access denied/not authorized error above,\nyour MFA session may have expired.\n"
      else
        echo -e "\nNOTE: If you see access denied/not authorized error above, you may need\nto use MFA session to authorize the key rotation.\n"
      fi
    fi
    echo
    echo "${green}The key for the profile ${cyan}'${final_selection}'${green} (IAM user ${cyan}'${final_selection_name}'${green}) has been rotated."
    echo "Successfully switched from the old access key ${red}${ORIGINAL_ACCESS_KEY_ID}${reset} to ${green}${NEW_AWS_ACCESS_KEY_ID}${reset}"
    continue

  else

    echo "Key propagation did not complete within the allotted time. This delay is caused by AWS, and does \
  not necessarily indicate an error. However, the newly generated key cannot be safely taken into use before \
  the propagation has completed. Please wait for some time, and try to temporarily replace the Access Key ID \
  and the Secret Access Key in your ~/.aws/credentials file with the new key details (below). Keep the old keys safe \
  until you have confirmed that the new key works."
    echo
    echo "PLEASE MAKE NOTE OF THE NEW KEY DETAILS BELOW; THEY HAVE NOT BEEN SAVED ELSEWHERE!"
    echo "New AWS Access Key ID: ${NEW_AWS_ACCESS_KEY_ID}"
    echo "New AWS Secret Access Key: ${NEW_AWS_SECRET_ACCESS_KEY}"
    continue

  fi
}

main_profile_selection() {
  # prompt for profile selection
  printf "SELECT THE PROFILE NUMBER(${green}green${reset}) WHOSE KEYS YOU WANT TO ROTATE (press [ENTER] to continue): "

  profiles=()
  DONE="false"
  while [[ "${DONE}" = "false" ]]; do
    read -r selprofile
    if [[ "${selprofile}" != "" ]] && [[ "${selprofile}" = "EDIT" ]]; then
      printf "SELECT PROFILE NUMBER TO REMOVE (press [ENTER] to continue): "
      read -r delprofile
      for item in ${!profiles[@]};do
        if [ "${profiles[${item}]}" == "${delprofile}" ]; then
          unset profiles[${item}]
        fi 
      done
      printf "Current selection: $(print_array "${profiles[@]}")\n"
      printf "SELECT ANOTHER PROFILE (press [ENTER] to continue, type EDIT to edit selection): "
    elif [[ "${selprofile}" != "" ]]; then
      profiles+=(${selprofile})
      profiles=($(tr ' ' '\n' <<< "${profiles[@]}" | sort -u | tr '\n' ' '))
      printf "Current selection: $(print_array "${profiles[@]}")\n"
      printf "SELECT ANOTHER PROFILE (press [ENTER] to continue, type EDIT to edit selection): "
    else
      DONE="true"
    fi
  done

  if [[ ${#profiles[@]} = 0 ]]; then
    echo "${cyan}You haven't selected any profiles. Therefore there are no keys to rotate. Exiting...${reset}"
    exit 0
  fi

  # Remove duplicated entries from provided selection
  unique_profiles=($(tr ' ' '\n' <<< "${profiles[@]}" | sort -u | tr '\n' ' '))

  echo "You selected ${#unique_profiles[@]} profiles."
  for profile_numer in "${unique_profiles[@]}"; do 
    selprofile=${profile_numer}

    # capture the numeric part of the selection
    [[ ${selprofile} =~ ^([[:digit:]]+) ]] &&
      selprofile_check="${BASH_REMATCH[1]}"
    
    if [[ "${selprofile_check}" != "" ]]; then

      # if the numeric selection was found, 
      # translate it to the array index and validate
      let actual_selprofile=${selprofile_check}-1

      profilecount=${#cred_profiles[@]}
      if [[ ${actual_selprofile} -ge ${profilecount} ||
        ${actual_selprofile} -lt 0 ]]; then
        # a selection outside of the existing range was specified
        echo
        echo "There is no profile "${selprofile}". Skipping non-existing profile."
        continue
      fi

      if [[ ${selprofile} =~ ^[[:digit:]]+$ ]]; then 
        if [[ "${cred_profile_arn[$actual_selprofile]}" = "INVALID" ]]; then
          echo
          echo "${bold}PROFILE${reset}: ${cyan}\"${cred_profiles[${actual_selprofile}]}\" ${red}HAS INVALID ACCESS KEYS.${reset} Cannot proceed. Skipping profile."
          continue
        elif [[ "${cred_profile_arn[${actual_selprofile}]}" = "DENIED" ]]; then
          echo
          echo "${bold}PROFILE${reset}: ${cyan}\"${cred_profiles[${actual_selprofile}]}\" ${red}HAS INSUFFICIENT PRIVILEGES (restrictive policy in effect).${reset} Cannot proceed. Skipping profile."
          continue
        else
          echo
          echo "${bold}SELECTED PROFILE${reset}: ${cyan}${cred_profiles[${actual_selprofile}]}${reset}"
          final_selection="${cred_profiles[${actual_selprofile}]}"
          final_selection_name="${cred_profile_user[${actual_selprofile}]}"
          echo "${bold}SELECTED USER${reset}: ${final_selection_name}"
          mfa_profile_verify
          rotate_key_profile
        fi
      else
        # non-acceptable characters were present in the selection
        echo
        echo "There is no profile "${selprofile}". Skipping non-existing profile."
        continue             
      fi
    else 
      # empty selection; exit
      echo
      echo "Aborting. No changes were made."
      exit 1
    fi
  done
}

main_profile_selection
