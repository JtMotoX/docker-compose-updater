#!/bin/bash

set -e
cd "$(dirname "$0")"

# MAKE SURE JQ IS INSTALLED
if ! command -v jq >/dev/null; then
	echo "jq is required to run this script. Please install jq and try again. (https://jqlang.org/download)"
	exit 1
fi

# LOAD EXCLUDE LIST FROM excludes.txt INTO AN ARRAY
excludes=()
if [ -f excludes.txt ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "${line}" = "" ]; then
			continue
		fi
		line="$(echo "${line}" | tr -d '[:space:]')"
		excludes+=("$line")
	done < excludes.txt
fi

# GET ALL RUNNING DOCKER COMPOSE SERVICES
compose_json="$(docker compose ls --format json | jq -r '[.[] | select(.Status | test("running\\("))]')"
compose_count="$(printf '%s' "${compose_json}" | jq -r 'length')"

# REMOVE EXCLUDED SERVICES FROM THE LIST
compose_json_apply="${compose_json}"
for exclude in "${excludes[@]}"; do
	compose_json_apply="$(printf '%s' "${compose_json_apply}" | jq -r "map(select(.Name != \"${exclude}\"))")"
done
compose_count_apply="$(printf '%s' "${compose_json_apply}" | jq -r 'length')"

# LIST ALL RUNNING DOCKER COMPOSE SERVICES
echo "This will update ${compose_count_apply} running docker compose services:"
for compose_b64 in $(printf '%s' "${compose_json}" | jq -r '.[] | @base64'); do
	compose_entry="$(echo "${compose_b64}" | base64 -d)"
	compose_name="$(echo "${compose_entry}" | jq -r '.Name')"
	compose_file="$(echo "${compose_entry}" | jq -r '.ConfigFiles')"
	compose_dir="$(dirname "${compose_file}")"
	cd "${compose_dir}"
	compose_data="$(docker compose ps --format json)"
	compose_running="$(printf '%s' "${compose_data}" | jq -r -s '.[0].RunningFor')"
	compose_created="$(printf '%s' "${compose_data}" | jq -r -s '.[0].CreatedAt')"
	compose_created_epoch="$(date -d "$(echo "${compose_created}" | sed -E 's/ [A-Z]+$//')" +%s)"
	compose_created_days_ago="$((($(date +%s) - ${compose_created_epoch}) / 86400))"
	if [ "${compose_created_days_ago}" -gt 240 ]; then
		color="red"
	elif [ "${compose_created_days_ago}" -gt 90 ]; then
		color="orange"
	elif [ "${compose_created_days_ago}" -gt 30 ]; then
		color="yellow"
	else
		color="green"
	fi
	case "${color}" in
		red) color_code='\033[0;31m' ;;
		orange) color_code='\033[0;33m' ;;
		yellow) color_code='\033[0;33m' ;;
		green) color_code='\033[0;32m' ;;
	esac
	# CHECK IF COMPOSE IS IN THE EXCLUDES LIST
	if [[ " ${excludes[@]} " =~ " ${compose_name} " ]]; then
		exclude_msg=" ---EXCLUDING---"
	else
		exclude_msg=""
	fi
	printf "${color_code}  - ${compose_name} (${compose_running})${exclude_msg}\033[0m\n"
done

echo "If you wish to exclude any of these, add the name to the 'excludes.txt' file and run this script again."

# PROMPT TO CONTINUE
printf "%s " "Press enter to continue or Ctrl+C to cancel"
read ans

# UPDATE ALL RUNNING DOCKER COMPOSE SERVICES
for compose_b64 in $(printf '%s' "${compose_json_apply}" | jq -r '.[] | @base64'); do
	echo '---'
	compose_entry="$(echo "${compose_b64}" | base64 -d)"
	compose_name="$(echo "${compose_entry}" | jq -r '.Name')"
	compose_file="$(echo "${compose_entry}" | jq -r '.ConfigFiles')"
	compose_dir="$(dirname "${compose_file}")"
	cd "${compose_dir}"
	echo "Updating '${compose_name}'..."
	docker compose pull; docker compose up --force-recreate --build --pull always -d
done

echo '---'
echo "done"