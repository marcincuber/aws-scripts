#!/usr/bin/env bash

profile_name="cloud-eng"
# Usage aws_account_alias ${profile_name}
aws_account_alias() {
  aws iam list-account-aliases --profile="${1}" --query 'AccountAliases[]' --output text
}

# Usage aws_account_id ${profile_name}
aws_account_id() {
  aws sts get-caller-identity --profile="${1}" --query 'Account' --output text
}

# Usage aws_user_email ${profile_name}
aws_user_email() {
  aws iam get-user --profile="${1}" --query 'User.UserName' --output text
}

# aws_account_alias "${profile_name}"
# aws_account_id "${profile_name}"
# aws_user_email "${profile_name}"

CREDFILE=~/.aws/credentials

declare -a cred_profiles
declare -a cred_allprofiles
declare -a cred_profile_arn
declare -a cred_profile_user
declare -a cred_profile_keys
declare -a key_status
cred_profilecounter=0

TODAY=$(date "+%Y-%m-%d")
OS="$(uname)"

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
        cred_profile_arn[$cred_profilecounter]="DENIED" 
      else
        key_status_array=($(echo "${key_status_array_input}" | grep -A2 ctive | awk -F\" '{print $2}'))
      fi

      # get the actual username (may be different from the arbitrary profile ident)
      s_no=0
      for s in ${key_status_array[@]}; do
        if [[ "${s}" == "Active" || "${s}" == "Denied" || "${s}" == "Inactive" ]]; then

          if [[ "${s}" == "Active" ]]; then
            statusword="  Active"
          elif [[ "${s}" == "Denied" ]]; then
            statusword="INSUFFICIENT PRIVILEGES TO PROCESS THE KEY"
          else
            statusword="Inactive"
          fi

          let "s_no++"
          kcd=$(echo ${key_status_array[${s_no}]} | sed 's/T/ /' | awk '{print $1}')
          let  keypos=${s_no}+1
          if [[ "${s}" != "Denied" ]]; then
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
echo "CONFIGURED AWS PROFILES AND THEIR ASSOCIATED KEYS:"
echo
SELECTR=0
ITER=1
for i in "${cred_profiles[@]}"
do
  if [[ "${cred_profile_arn[${SELECTR}]}" = "INVALID" ]]; then
    echo "X: ${i} (${cred_profile_user[${SELECTR}]})"
  else
    echo "${ITER}: ${i} (${cred_profile_user[${SELECTR}]})"
    printf "${cred_profile_keys[${SELECTR}]}"
  fi
  echo
  let ITER=${ITER}+1
  let SELECTR=${SELECTR}+1
done

# prompt for profile selection
# printf "SELECT THE PROFILE WHOSE KEYS YOU WANT TO ROTATE (or press [ENTER] to abort): "
# read -r selprofile

######################
printf "SELECT THE PROFILE WHOSE KEYS YOU WANT TO ROTATE (or press [ENTER] to abort): "

profiles=()
DONE="false"
while [[ "${DONE}" = "false" ]]; do
  read -r selprofile
  if [[ "${selprofile}" != "" ]]; then
    profiles+=(${selprofile})
    printf "SELECT ANOTHER PROFILE (or press [ENTER] to abort): "
  else
    DONE="true"
  fi
done

echo "You selected ${#profiles[@]} profiles."

for profile_numer in "${profiles[@]}"; do 
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
      echo "There is no profile "${selprofile}"."
      echo "Skipping non-existing profile."
      continue
    fi

    if [[ ${selprofile} =~ ^[[:digit:]]+$ ]]; then 
      if [[ "${cred_profile_arn[$actual_selprofile]}" = "INVALID" ]]; then
        echo
        echo "PROFILE: \"${cred_profiles[${actual_selprofile}]}\" HAS INVALID ACCESS KEYS."
        echo "Cannot proceed. Skipping profile."
        continue
      elif [[ "${cred_profile_arn[${actual_selprofile}]}" = "DENIED" ]]; then
        echo
        echo "PROFILE: \"${cred_profiles[${actual_selprofile}]}\" HAS INSUFFICIENT PRIVILEGES (restrictive policy in effect)."
        echo "Cannot proceed. Skipping profile."
        continue
      else
        echo
        echo "SELECTED PROFILE: ${cred_profiles[${actual_selprofile}]}"
        final_selection="${cred_profiles[${actual_selprofile}]}"
        final_selection_name="${cred_profile_user[${actual_selprofile}]}"
        echo "SELECTED USER: ${final_selection_name}"
      fi
    else
      # non-acceptable characters were present in the selection
      echo
      echo "There is no profile "${selprofile}"."
      echo "Skipping non-existing profile."
      continue             
    fi
	else 
	  # empty selection; exit
	  echo
	  echo "Aborting. No changes were made."
	  echo
	  exit 1
	fi
done