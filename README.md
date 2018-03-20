# AWS ACCESS KEYS DEACTIVATION SCRIPTS

**Bash scripts for automating IAM key deactivation.**

Running scripts will pull all the keys that are older than 500 days and deactivate them. Scripts currently only `update-keys` but can easily be changed to `delete-keys`. The same applies for number of days (how old the keys are).

To run the scripts ensure you have the current user set locally on your machine and run the following;
```
bash deactivate.sh
```


