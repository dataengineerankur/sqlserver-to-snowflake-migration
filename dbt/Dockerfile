# dbt-snowflake runner image for the MSSQL → Snowflake migration project.
# Built once; used by Airflow DockerOperator to run all dbt commands.
#
# Build:
#   cd sqlserver-to-snowflake-migration
#   docker build -t dms-dbt-runner:latest -f dbt/Dockerfile dbt/
#
# Run locally:
#   docker run --rm \
#     -e SNOWFLAKE_ACCOUNT=... -e SNOWFLAKE_USER=... -e SNOWFLAKE_PASSWORD=... \
#     dms-dbt-runner:latest run --select stg

# Using python:3.11-slim + pip install because the official dbt-labs image
# does not publish ARM64 (Apple Silicon) builds.
# On linux/amd64 CI you can swap this for:
#   FROM ghcr.io/dbt-labs/dbt-snowflake:1.8.4
FROM python:3.11-slim

WORKDIR /opt/dbt

# Install dbt-snowflake (pinned for reproducibility)
RUN pip install --no-cache-dir dbt-snowflake==1.8.4

# Copy project files (profiles.yml must be here so --profiles-dir /opt/dbt works)
COPY dbt_project.yml      ./dbt_project.yml
COPY profiles.yml         ./profiles.yml
COPY models/              ./models/
COPY snapshots/           ./snapshots/
COPY macros/              ./macros/

# Install any packages declared in packages.yml (none for now, but good practice)
RUN test -f packages.yml && dbt deps --profiles-dir /opt/dbt || echo "No packages.yml — skipping dbt deps"

ENTRYPOINT ["dbt", "--profiles-dir", "/opt/dbt"]
CMD ["run"]
