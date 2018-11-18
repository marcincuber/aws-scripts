## AWS BASH SCRIPTS

### Automatic rotation of AWS profile credentials

Script rotates AWS access keys stored in the user's ~/.aws/credentials file. Selected profiles will simply get their credentials rotated. Script will make sure there is just one existing key attached to existing user or to remove one of the two existing keys. It then proceeds to create and test the new key and them replace the keys in the user's ~/.aws/credentials file for specified profiles.

* [IAM profile key script](rotate_profile_keys/) [README doc](rotate_profile_keys/README.md)

### Scripts for automating IAM key rotation for single user, deactivation/removal of keys in AWS account for all user based on age of the key/s (in days).

* [IAM key scripts](key_rotation_deactive_remove/) [README doc](key_rotation_deactive_remove/README.md)

## Disclaimer
_The SOFTWARE PACKAGE provided in this page is provided "as is", without any guarantee made as to its suitability or fitness for any particular use. It may contain bugs, so use of this tool is at your own risk. We take no responsibility for any damage of any sort that may unintentionally be caused through its use._

## Contacts

If you have any questions, drop an email to marcincuber@hotmail.com and leave stars! :)

