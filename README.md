# docker-compose-updater

This is a utility that will update all the docker compose services running on the host. You can run the script with `--dry-run` to view the list of services and their age. The age is based on the creation date of the container, not the image. If you want to exclude any services, you can create a `excludes.txt` file with the list of the names of the services to exclude.

- `--dry-run`
  - Performs a dry-run without making any changes
- `--selected`
  - Provide a comma-separated list of compose instances to pre-select (e.g. `--selected foo,bar`)

### TODO

- Add an `--exclude-recent` argument that will exclude services that have already been updated in the past 24 hours.
