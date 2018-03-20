#!/bin/bash

current_date=$(gdate '+%Y-%m-%d')

first_date=$(gdate -d "$current_date" "+%s")
second_date=$(gdate -d "${1}" "+%s")

case "$3" in
        "--seconds" | "-s") period=1
        ;;
        "--minutes" | "-m") period=60;;
        "--hours" | "-h") period=$((60*60));;
        "--days" | "-d" | "") period=$((60*60*24));;
esac

datediff=$(( ($first_date - $second_date)/($period) ))
echo $datediff
