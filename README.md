# AWS IAM ACCESS KEYS- ROTATION, DEACTIVATION and REMOVAL

**Bash scripts for automating IAM key rotation for single user, deactivation/removal of keys in AWS account for all user based on age of the key/s (in days). **

# aws_iam_keys_main.sh

**aws_iam_keys_main.sh** is the main bash script that rotates, deactivates or removes IAM keys.

We have following options that we can trigger;

    usage: ./aws_iam_keys_main.sh [options...]
    options:
     -d  --deactivate     Deactivate IAM keys for all_users or with specific email which are older than provided number of days.
     -rm --remove         Remove IAM keys for all_users or with specific email which are older than provided number of days.
     -a  --key-file       The file for the .csv access key file for an AWS administrator. Optional for key rotation.
     -u  --user           The IAM user whose key you want to rotate. Required for key rotation.
     -j  --json           Name of the final to output new credentials. Optional for key rotation.
         --help           Prints help menu.

NOTE: don't mix flags `-d -rm -u` together. You must only use one of those flags when running the script. See examples below.

## Rotating IAM keys
Ensure that you have aws credentials setup. When the profile is configured you can easily rotate your keys by running the following;

```bash
./aws_iam_keys_main.sh -u <Your_AWS_USER_ID> -j <file_name_for_new_creds> -r true # both -r and -j flags can be omitted, only -u is required. Do not use -r or -rm with -u flag.

# Alterantively you can run (exactly the same as above)
./aws_iam_keys_main.sh --user <Your_AWS_USER_ID> --json <file_name_for_new_creds> --reconfigure true

```

The script is executing the following actions;

1. Generate new access key for the user.
2. Test the new key with some basic aws cli commands.
3. If tests pass, remove old key.
4. Reconfigure environment with new keys (when `-r true` or `--reconfigure true` are present).

## Deactivate keys in AWS account

The following command will scan through all users in the account and deactivate IAM keys which are older than specified number of days.
It will deactivate keys whos `status=Active`. 
The script `won't deactivate keys for the current user` that you execute script with.

```bash
./aws_iam_keys_main.sh -d # Don't use with flags -u or -rm

# Alterantively you can run (exactly the same as above)
./aws_iam_keys_main.sh --deactivate

# After you execute one from above you will be prompt with:
Enter the max age of your key in days:
# Enter any positive integare. 
# E.g. if you type in 90, that will mean any key older than 90 days will be deactivated.

# Second prompt will allow you to select two options but select the following
You chose to deactivate keys for all users

You can always customise the other option to match another organisation's email.

```


The script is executing the following actions;

1. Input number of days and which users to take into account.
2. Pull all users.
3. For each user pull his keys.
4. For each key check the age and status.
5. Deactivate when key is `Active` and `older than specified number of days`.

## Delete keys in AWS account

The following command will scan through all users in the account and remove IAM keys which are older than specified number of days.
It will remove keys based on your selection which is `Active, Inactive, Both` (Both means you can. 
The script `won't delete any keys for the current user` that you execute script with.

```bash
./aws_iam_keys_main.sh -rm # Don't use with flags -u or -d

# Alterantively you can run (exactly the same as above)
./aws_iam_keys_main.sh --remove

# After you execute one from above you will be prompt with:
Enter the max age of your key in days:
# Enter any positive integare. 
# E.g. if you type in 90, that will mean any key older than 90 days will be removed.

# Second prompt will ask you which keys it should remove. Options;
1. Active
2. Inactive
3. Both # Both= Active and Inactive
4. Exit
It is upto you which keys with the above status you want to remove. Select any numeric value 1-4 in this case.


# Third prompt will allow you to select two options but select the following.
You chose to remove keys for all users.

You can always customise the other option to match another organisation's email.

```

The script is executing the following actions;

1. Input number of days, which keys should be rotated and which users to take into account.
2. Pull all users.
3. For each user pull his keys.
4. For each key check the age and status.
5. Delete when key is status match your selection and `older than specified number of days`.

## Package Requirements and Dependencies

Scripts are using the following tools;

1. AWS CLI- (always go for latest version). Install with `pip install awscli` [More on CLI](https://aws.amazon.com/cli/)
2. jq- various options to install e.g.`apt-get install jq or brew install jq`  [jq install](https://stedolan.github.io/jq/download/)
## Disclaimer
3. GNU date- on linux and ubuntu `date` should work. On OSX you will require to install `gdate`. To install run `brew install coreutils`.

_The SOFTWARE PACKAGE provided in this page is provided "as is", without any guarantee made as to its suitability or fitness for any particular use. It may contain bugs, so use of this tool is at your own risk. We take no responsibility for any damage of any sort that may unintentionally be caused through its use._

## Contacts

If you have any questions, drop an email to marcincuber@hotmail.com and leave stars! :)

