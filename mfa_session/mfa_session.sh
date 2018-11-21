#!/usr/bin/env bash

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
profiles=()
while IFS='' read -r line || [[ -n "${line}" ]]; do
  [[ "${line}" =~ ^\[(.*)\].* ]] 
  profile_ident=${BASH_REMATCH[1]}
  profiles+=(${profile_ident})
  if [[ ${profile_ident} != "" ]]; then
    ONEPROFILE="true"
  fi 
done < ${CREDFILE}

echo "${profiles[@]}"

aws_account_alias() {
  aws iam list-account-aliases --profile="${1}" --query 'AccountAliases[]' --output text
}

aws_account_id() {
  aws sts get-caller-identity --profile="${1}" --query 'Account' --output text
}

aws_user_email() {
  aws iam get-user --profile="${1}" --query 'User.UserName' --output text
}

unset_aws_env_variables() {
	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SESSION_TOKEN
}

AccessKeyId=""
SecretAccessKey=""
SessionToken=""

get_session_token() {
	profile_name="${1}"
	account_id=$(aws_account_id "${profile_name}")
	user_email=$(aws_user_email "${profile_name}")
	mfa_arn="arn:aws:iam::${account_id}:mfa/${user_email}"

	printf "Enter MFA code:"
	read -r mfa_code

	session_data=$(aws sts get-session-token --duration-seconds="3600" --serial-number="${mfa_arn}" \
		--token-code="${mfa_code}" --profile="${profile_name}" \
		--output=text --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]')
	
	AccessKeyId=$(echo ${session_data} | awk '{print $1}')
	SecretAccessKey=$(echo ${session_data} | awk '{print $2}')
	SessionToken=$(echo ${session_data} | awk '{print $3}')
}	

# configure_mfa_profile() {
# 	profile_name="${1}-mfa"
# 	aws configure set aws_access_key_id ${AccessKeyId} --profile="${profile_name}"
# 	aws configure set aws_secret_access_key ${SecretAccessKey} --profile="${profile_name}"
# 	aws configure set aws_session_token ${SessionToken} --profile="${profile_name}"
# }
export_aws_env_variables() {
	export AWS_ACCESS_KEY_ID="${AccessKeyId}"
	export AWS_SECRET_ACCESS_KEY="${SecretAccessKey}"
	export AWS_SESSION_TOKEN="${SessionToken}"
}

get_session_token "cloud-eng"

unset_aws_env_variables

export_aws_env_variables






