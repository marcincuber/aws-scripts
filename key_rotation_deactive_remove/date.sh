#!/usr/bin/env bash
# ================================================================
# === DESCRIPTION
# ================================================================
# 
# File name: date.sh
# 
# Summary: Script to calculate number of weeks/days/hours between
# current and a date in the past.
# 
# Example usage: ./date.sh 2010-10-10
# 
# Author: marcincuber@hotmail.com

# ================================================================
# === FUNCTIONS
# ================================================================

check_package() {
  package_name=${1}
  check_type=$(which ${package_name})
  if [[ -z "${check_type}" ]] ;
  then
    echo "Install the required ${package_name} which isn't installed!"
    echo "Ensure ${package_name} is in your $PATH"
    exit 2
  fi
}

# Usage calculate_date_diff package_name date -d/-h/-m/-s
calculate_date_diff() {
  current_date=$(${1} '+%Y-%m-%d')
  first_date=$(${1} -d "$current_date" "+%s")
  second_date=$(${1} -d "${2}" "+%s")

  case "${3}" in
    "--seconds" | "-s") period=1;;
    "--minutes" | "-m") period=60;;
    "--hours" | "-h") period=$((60*60));;
    "--days" | "-d" | "") period=$((60*60*24));;
  esac

  datediff=$(( (${first_date} - ${second_date})/(${period}) ))
  echo ${datediff}
}

# ======================================================
# === MAIN SCRIPT
# ======================================================

# Format of date: yyyy-mm-dd
DATE_IN_PAST=${1}

# Detect the platform (similar to $OSTYPE)
OS="$(uname)"
case ${OS} in
  'Darwin') 
    check_package "gdate" && calculate_date_diff "gdate" ${DATE_IN_PAST} -d
    ;;
  'Linux')
    check_package "date" && calculate_date_diff "date" ${DATE_IN_PAST} -d
    ;;
  'FreeBSD')
    check_package "date" && calculate_date_diff "date" ${DATE_IN_PAST} -d
    ;;
  'SunOS')
    check_package "date" && calculate_date_diff "date" ${DATE_IN_PAST} -d
    ;;
  *) ;;
esac
