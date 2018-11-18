## AWS IAM ACCESS KEYS- ROTATE PROFILE CREDENTIALS/KEYS

### Purpose

Often software engineer have access to multiple AWS accounts and for each they have profile setup with access keys. This bash script provides them with easier rotation of AWS IAM credentials set for each profile defined in `credentails` `config`. Script will allow to rotate keys for one or more configured profile based on the selection. It is using `~/.aws` directory and `~/.aws/credentials` file to find profile information.

### Script

`roate_keys_profiles.sh` is the main bash script that rotates IAM keys based on the profile configuration.

	Usage: ./rotate_keys_profiles.sh [options...]
	options:
		-d  --debug    Enable debug mode. Optional.
		-h  --help     Prints this help message.

If you don't want debug mode simply run:
```bash
./rotate_keys_profiles.sh
```

How it works:

1. Verify that AWS CLI is installed.
2. Check for ~/.aws directory and credentials/config files
3. Check for configured AWS profiles
4. Collect and prompt user to specify profile numbers which will be rotated
5. Rotote key for each specified profile

### Sample prompt during execution

```
CONFIGURED AWS PROFILES AND THEIR ASSOCIATED KEYS:

X: core (CHECK CREDENTIALS!)

2: main (marcincuber@hotmail.com)
	Active key AKIAIZKEYASDWADSB is 60 days old
3: eng (marcincuber@hotmail.com)
    Active key AKIAIZKEYASDWADSA is 50 days old

SELECT THE PROFILE NUMBER(green) WHOSE KEYS YOU WANT TO ROTATE (press [ENTER] to continue):

```

When you see the prompt simply specify a single number that belongs to your profile such as `2`. You can also specify multiple value for example `2 3`. Simple list of numbers seperated with a space. 

After pressing [ENTER] you get another prompt
```
SELECT ANOTHER PROFILE (or press [ENTER] to continue):
```
If you don't want to specify any more profiles simply press [ENTER] and the rotation process will start.

Verification process will check whether you have two Access Keys attached to you AWS IAM user account. If that is the case, you will get an option to remove one of them. Otherwise you have to remove it manually.

Rest of the process is simply creating and testing new Access Key. Then profile is reconfigured with new keys and old keys are removed.

### Package Requirements

1. AWS CLI- (always go for latest version). Install with `pip install awscli` [More on CLI](https://aws.amazon.com/cli/)

## Disclaimer
_The SOFTWARE PACKAGE provided in this page is provided "as is", without any guarantee made as to its suitability or fitness for any particular use. It may contain bugs, so use of this tool is at your own risk. We take no responsibility for any damage of any sort that may unintentionally be caused through its use._

## Contacts

If you have any questions, drop an email to marcincuber@hotmail.com and leave stars! :)