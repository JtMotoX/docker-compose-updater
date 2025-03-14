#!/bin/bash

set -e
cd "$(dirname "$0")"

# SET SOME DEFAULTS
dry_run="false"

# SET SOME COLORS
export GUM_CHOOSE_CURSOR_FOREGROUND=214

# FUNCTION TO PRINT USAGE
usage() {
    echo "Usage: ./$(basename "$0") [--dry-run]" | gum style --foreground 212
}

# PARSE ARGUMENTS
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            dry_run="true"
            shift
            ;;
		--selected)
			user_preselected_options="$2"
			shift 2
			;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Invalid argument '$1'" | gum style --foreground 196
            usage
            exit 1
            ;;
    esac
done

# MAKE SURE JQ IS INSTALLED
if ! command -v jq >/dev/null; then
    echo "ERROR: jq is required to run this script. Please install jq and try again. (https://jqlang.org/download)"
    exit 1
fi

# MAKE SURE GUM IS INSTALLED
if ! command -v gum >/dev/null; then
	echo "ERROR: gum is required to run this script. Please install gum and try again. (https://github.com/charmbracelet/gum?tab=readme-ov-file#installation)"
	exit 1
fi

if [ "${is_docker}" = "true" ]; then
    export path_prefix="/host"
fi

# LOAD EXCLUDE LIST FROM excludes.txt INTO AN ARRAY
excludes=()
if [ -f excludes.txt ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "${line}" = "" ] || { echo "${line}" | grep -q -E '^\s*#'; }; then
            continue
        fi
        line="$(echo "${line}" | tr -d '[:space:]')"
        excludes+=("$line")
    done < excludes.txt
fi

# CHECK IF DRY RUN
if [ "${dry_run}" = "true" ]; then
	echo "-- This is a dry run. No changes will be made --" | gum style --foreground 214 --bold
	echo
	dry_run_suffix=" (dry run)"
fi

get_compose_data() {
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
	services_list=()
	for compose_b64 in $(printf '%s' "${compose_json}" | jq -r '.[] | @base64'); do
		compose_entry="$(echo "${compose_b64}" | base64 -d)"
		compose_name="$(echo "${compose_entry}" | jq -r '.Name')"
		compose_file="$(echo "${compose_entry}" | jq -r '.ConfigFiles')"
		compose_dir="$(dirname "${compose_file}")"
		cd "${path_prefix}${compose_dir}"
		compose_data="$(docker compose ps --format json)"
		compose_running="$(printf '%s' "${compose_data}" | jq -r -s '.[0].RunningFor')"
		compose_created="$(printf '%s' "${compose_data}" | jq -r -s '.[0].CreatedAt')"
		compose_created_epoch="$(date -d "$(echo "${compose_created}" | sed -E 's/ [A-Z]+$//')" +%s)"
		compose_created_days_ago="$((($(date +%s) - ${compose_created_epoch}) / 86400))"

		# CHECK IF COMPOSE IS IN THE EXCLUDES LIST
		if [[ " ${excludes[@]} " =~ " ${compose_name} " ]]; then
			exclude_msg=" ---EXCLUDING---"
		else
			exclude_msg=""
		fi

		entry="${compose_name}~(${compose_running})~${compose_created_days_ago}"

		services_list+=("${entry}")
	done
}
export -f get_compose_data

# SHOW SPINNER WHILE GETTING DOCKER COMPOSE INSTANCES
eval "$(gum spin --spinner dot --title "Getting docker compose instances..." --show-output -- bash -c "source <(declare -f get_compose_data); get_compose_data; declare -p | grep -v '^declare -[[:alpha:]]*r'")"

# PRESELECT SERVICES THAT ARE OLDER THAN 7 DAYS
max_service_length=$(for item in "${services_list[@]}"; do echo -e "${item}" | awk -F'~' '{print length($1)}'; done | sort -nr | head -1)
services_list_formatted="$(for item in "${services_list[@]}"; do echo -e "${item}"; done | awk -F'~' -v max_service_length="$max_service_length" '{printf "%-"max_service_length"s %s~%s\n", $1, $2, $3}')"
while IFS= read -r item; do
	compose_created_days_ago="$(echo "${item}" | awk -F'~' '{print $2}')"
	entry="$(echo "${item}" | awk -F'~' '{print $1}')"
	if [ "${user_preselected_options}" != "" ]; then
		if echo "$(echo "${user_preselected_options}" | sed 's/,/ /g')" | grep -wq "$(echo "${entry}" | awk '{print $1}')"; then
			preselected_options="${preselected_options},${entry}"
		fi
	else
		if [ "${compose_created_days_ago}" -gt 7 ]; then
			preselected_options="${preselected_options},${entry}"
		fi
	fi
	services_list_final+=("${entry}")
done <<< "${services_list_formatted}"
preselected_options="${preselected_options#,}"

# PROMPT TO SELECT SERVICES TO UPDATE
selected_compose=$(
	for item in "${services_list_final[@]}"; do echo -e "${item}"; done | \
	gum choose \
		--header "Select services to update (spacebar to select)" \
		--no-limit \
		--height $((${#services_list_final[@]} + 1)) \
		--selected="${preselected_options}"
)

selected_services="$(echo "${selected_compose}" | grep -v -E '^\s*$' | awk '{print $1}')"
selected_count="$(echo "${selected_compose}" | grep -v -E '^\s*$' | wc -l)"

if [ "${selected_count}" -eq 0 ]; then
    echo "No services to update." | gum style --foreground 196
    exit 0
fi

gum style --border rounded --margin "1" --padding "0 2" --border-foreground 14 "
$(echo "The following ${selected_count} services will be updated:" | gum style --foreground 214)
$(echo "${selected_services}" | sed -E 's/^/- /g' | gum style --foreground 212)
"

# PROMPT TO CONTINUE
response="$(gum confirm "Do you want to continue?")" || exit 1

# UPDATE ALL RUNNING DOCKER COMPOSE SERVICES
for compose_b64 in $(printf '%s' "${compose_json_apply}" | jq -r '.[] | @base64'); do
    compose_entry="$(echo "${compose_b64}" | base64 -d)"
    compose_name="$(echo "${compose_entry}" | jq -r '.Name')"
	if ! echo "${selected_services}" | grep -wq "${compose_name}"; then continue; fi
    compose_file="$(echo "${compose_entry}" | jq -r '.ConfigFiles')"
    compose_dir="$(dirname "${compose_file}")"
	if [ "${path_prefix}" != "" ]; then
		mkdir -p "$(dirname "${compose_dir}")"
		ln -s "${path_prefix}${compose_dir}" "${compose_dir}"
	fi
    cd "${compose_dir}"
    echo "--- Updating '${compose_name}'...${dry_run_suffix} ---" | gum style --foreground 212
    command="docker compose up --force-recreate --build --pull always -d"
    if [ "${dry_run}" = "true" ]; then
        echo "Command To Be Executed: ${command}" | gum style --foreground 214
    else
        eval "${command}"
    fi
	if [ "${path_prefix}" != "" ] && [ -L ${compose_dir} ] && [ -e ${compose_dir} ]; then
		rm -f "${compose_dir}"
	fi
done

echo '---' | gum style --foreground 212
echo "done" | gum style --foreground 212
