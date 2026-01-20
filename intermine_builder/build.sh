#!/bin/bash

set -euxo pipefail

THE_MINE_NAME=${MINE_NAME:-biotestmine}
FORCE_MINE_BUILD=${FORCE_MINE_BUILD:-0}
IM_VERSION=${IM_VERSION:-}
BIO_VERSION=${BIO_VERSION:-}

THE_PGHOST=${PGHOST:-postgres}
THE_PGPORT=${PGPORT:-5432}
THE_PSQL_USER=${PSQL_USER:-postgres}
THE_PSQL_PWD=${PSQL_PWD:-postgres}

THE_SOLR_HOST=${SOLR_HOST:-solr}
THE_SOLR_PORT=${SOLR_PORT:-8983}

THE_TOMCAT_HOST=${TOMCAT_HOST:-tomcat}
THE_TOMCAT_PORT=${TOMCAT_PORT:-8080}

# Bail out early if none of these is up
wait-for-it "${THE_PGHOST}":"${THE_PGPORT}" -t 60
wait-for-it "${THE_SOLR_HOST}":"${THE_SOLR_PORT}" -t 60
wait-for-it "${THE_TOMCAT_HOST}":"${THE_TOMCAT_PORT}" -t 60

HOME_DIR=/home/intermine

DOT_INTERMINE_DIR="${HOME_DIR}"/.intermine
THE_MINE_PROPERTIES="${DOT_INTERMINE_DIR}"/"${THE_MINE_NAME}".properties

# Potential for confusion here:
#
#           1         2         3         4
# /home/intermine/intermine/intermine/intermine
#
# 1. The intermine user's home directory
# 2. The overall project root containing the other repositories
# 3. The Git checkout of the intermine project
# 4. The intermine Gradle project
#
# TODO: Better names?

PROJECT_ROOT="${HOME_DIR}"/intermine

INTERMINE_DIR="${PROJECT_ROOT}"/intermine

THE_MINE_DIR="${PROJECT_ROOT}"/"${THE_MINE_NAME}"
THE_MINE_GRADLE_PROPERTIES="${THE_MINE_DIR}"/gradle.properties
THE_MINE_KEYWORD_SEARCH_PROPERTIES="${THE_MINE_DIR}"/dbmodel/resources/keyword_search.properties

LOG_FILE="${PROJECT_ROOT}"/build.progress

if [ -d "${THE_MINE_DIR}" ] && [ -n "$(ls -A ${THE_MINE_DIR})" ] && [ ! "$FORCE_MINE_BUILD" ]; then
    echo "$(date +%Y/%m/%d-%H:%M) Mine ${THE_MINE_NAME} already exists"
    echo "$(date +%Y/%m/%d-%H:%M) Gradle: build webapp"
    cd "${THE_MINE_DIR}"
    # If on opening the webapp you get the Tomcat error:
    # HTTP Status 404 - /<yourmine>/ The requested resource is not available,
    # implement the workaround at
    # https://github.com/intermine/intermine/issues/2162#issuecomment-952099300
    ./gradlew cargoRedeployRemote --stacktrace
    exit 0
fi

# Empty log
echo "" > "${LOG_FILE}"

gradle_clean_install() {
    local dir=$1

    cd "$dir"
    ./gradlew clean
    ./gradlew install --stacktrace
}

copy_properties() {
    local source=$1
    local target=$2

    echo "#--- creating $target"
    cp "$source" "$target"
    sed -i -e "s/PSQL_HOST/${THE_PGHOST}/" "$target"
    sed -i -e "s/PSQL_USER/${THE_PSQL_USER}/" "$target"
    sed -i -e "s/PSQL_PWD/${THE_PSQL_PWD}/" "$target"
}


# Build InterMine if any of the envvars are specified.
if [ -n "${IM_REPO_URL}" ] || [ -n "${IM_REPO_BRANCH}" ]; then
    echo "$(date +%Y/%m/%d-%H:%M) Start InterMine build" #>> "${LOG_FILE}"
    echo "$(date +%Y/%m/%d-%H:%M) Cloning ${IM_REPO_URL:-https://github.com/intermine/intermine} branch ${IM_REPO_BRANCH:-master} for InterMine build" #>> "${LOG_FILE}"
    cd "${PROJECT_ROOT}"
    git clone ${IM_REPO_URL:-https://github.com/intermine/intermine} intermine --single-branch --branch ${IM_REPO_BRANCH:-master} --depth=1

    export PSQL_HOST=${THE_PGHOST}
    export PSQL_USER=${THE_PSQL_USER}
    export PSQL_PWD=${THE_PSQL_PWD}
    python3 "${INTERMINE_DIR}/config/lib/install_intermine.py"

    INTERMINE_BUILD_GRADLE="${INTERMINE_DIR}"/intermine/build.gradle
    BIO_BUILD_GRADLE="${INTERMINE_DIR}"/bio/build.gradle

    # Read the version numbers of the built InterMine, as we'll need to set
    # the mine to use the same versions for it to use the local build.
    IM_VERSION=$(sed -n "s/^\s*version.*\+'\(.*\)'\s*$/\1/p" ${INTERMINE_BUILD_GRADLE})
    BIO_VERSION=$(sed -n "s/^\s*version.*\+'\(.*\)'\s*$/\1/p" ${BIO_BUILD_GRADLE})
fi


echo "Starting mine build"
echo $MINE_REPO_URL
# Check if mine exists and is not empty
if [ -d "${THE_MINE_DIR}" ] && [ -n "$(ls -A ${THE_MINE_DIR})" ]; then
    # TODO: Should this be enabled?
    echo "$(date +%Y/%m/%d-%H:%M) Update ${THE_MINE_NAME} to newest version" #>> "${LOG_FILE}"
    cd "${THE_MINE_DIR}"
    # git pull
else
    echo "$(date +%Y/%m/%d-%H:%M) Clone ${THE_MINE_NAME}" #>> "${LOG_FILE}"
    git clone ${MINE_REPO_URL:-https://github.com/intermine/biotestmine} "${THE_MINE_DIR}"
    echo "$(date +%Y/%m/%d-%H:%M) Update ${THE_MINE_KEYWORD_SEARCH_PROPERTIES} to use http://solr" #>> "${LOG_FILE}"
    sed -i 's/localhost/'${THE_SOLR_HOST}'/g' "${THE_MINE_KEYWORD_SEARCH_PROPERTIES}"
fi

# If InterMine or Bio versions have been set (likely because of a custom
# InterMine build), update gradle.properties in the mine.

if [ -f "${THE_MINE_GRADLE_PROPERTIES}" ]; then
    # cadremine generates gradle.properties from gradle.properties.in
    # so only do this stage if the files exist.

    if [ -n "${IM_VERSION}" ]; then
        sed -i "s/\(systemProp\.imVersion=\).*\$/\1${IM_VERSION}/" "${THE_MINE_GRADLE_PROPERTIES}"
    fi
    if [ -n "${BIO_VERSION}" ]; then
        sed -i "s/\(systemProp\.bioVersion=\).*\$/\1${BIO_VERSION}/" "${THE_MINE_GRADLE_PROPERTIES}"
    fi
fi

# Copy project_build from intermine_scripts repo
if [ ! -f "${THE_MINE_DIR}"/project_build ]; then
    cd "${PROJECT_ROOT}"
    echo "$(date +%Y/%m/%d-%H:%M) Cloning intermine scripts repo to "${PROJECT_ROOT}"/intermine-scripts"
    git clone https://github.com/intermine/intermine-scripts
    echo "$(date +%Y/%m/%d-%H:%M) Copy project_build to "${THE_MINE_DIR}""
    cp "${PROJECT_ROOT}"/intermine-scripts/project_build "${THE_MINE_DIR}"/project_build
    chmod +x "${THE_MINE_DIR}"/project_build
fi

# Copy mine properties
if [ ! -f "${THE_MINE_PROPERTIES}" ]; then
    if [ ! -f "${PROJECT_ROOT}"/configs/${THE_MINE_NAME}.properties ]; then
        echo "$(date +%Y/%m/%d-%H:%M) Copy ${THE_MINE_NAME}.properties to ~/.intermine/${THE_MINE_NAME}.properties" #>> "${LOG_FILE}"
        cp "${THE_MINE_DIR}"/data/${THE_MINE_NAME}.properties "${DOT_INTERMINE_DIR}"/
    else
        echo "$(date +%Y/%m/%d-%H:%M) Copy ${THE_MINE_NAME}.properties to ~/.intermine/${THE_MINE_NAME}.properties"
        cp "${PROJECT_ROOT}"/configs/${THE_MINE_NAME}.properties "${DOT_INTERMINE_DIR}"/
    fi

    echo -e "$(date +%Y/%m/%d-%H:%M) Set properties in .intermine/${THE_MINE_NAME}.properties to\nPSQL_DB_NAME\tbiotestmine\nPSQL_USER\t$PSQL_USER\nPSQL_PWD\t$PSQL_PWD\nTOMCAT_USER\t$TOMCAT_USER\nTOMCAT_PWD\t$TOMCAT_PWD\nGRADLE_OPTS\t$GRADLE_OPTS" #>> "${LOG_FILE}"

    #sed -i "s/PSQL_PORT/${THE_PGPORT}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/PSQL_DB_NAME/${THE_MINE_NAME}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/PSQL_USER/${THE_PSQL_USER}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/PSQL_PWD/${THE_PSQL_PWD}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/TOMCAT_USER/${TOMCAT_USER:-tomcat}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/TOMCAT_PWD/${TOMCAT_PWD:-tomcat}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/webapp.deploy.url=http:\/\/localhost:8080/webapp.deploy.url=http:\/\/${THE_TOMCAT_HOST}:${THE_TOMCAT_PORT}/g" "${THE_MINE_PROPERTIES}"
    sed -i "s/serverName=localhost/serverName=${THE_PGHOST}:${THE_PGPORT}/g" "${THE_MINE_PROPERTIES}"


    # echo "project.rss=http://localhost:$WORDPRESS_PORT/?feed=rss2" >> "${THE_MINE_PROPERTIES}"
    # echo "links.blog=https://localhost:$WORDPRESS_PORT" >> "${THE_MINE_PROPERTIES}"
fi

# Copy mine configs
if [ ! -f "${THE_MINE_DIR}"/project.xml ]; then
    if [ -f "${PROJECT_ROOT}"/configs/project.xml ]; then
        echo "$(date +%Y/%m/%d-%H:%M) Copy project.xml to ~/${THE_MINE_DIR}/project.xml"
        cp "${PROJECT_ROOT}"/configs/project.xml "${THE_MINE_DIR}"/
        echo "$(date +%Y/%m/%d-%H:%M) Set correct source path in project.xml"
        sed -i 's/'${IM_DATA_DIR:-DATA_DIR}'/\/home\/intermine\/intermine\/data/g' "${THE_MINE_DIR}"/project.xml
        sed -i 's/dump="true"/dump="false"/g' "${THE_MINE_DIR}"/project.xml
    else
        echo "$(date +%Y/%m/%d-%H:%M) Copy project.xml to ~/intermine/${THE_MINE_NAME}/project.xml" #>> "${LOG_FILE}"
        cp "${THE_MINE_DIR}"/data/project.xml "${THE_MINE_DIR}"

        echo "$(date +%Y/%m/%d-%H:%M) Set correct source path in project.xml" #>> "${LOG_FILE}"
        sed -i 's/'${IM_DATA_DIR:-DATA_DIR}'/\/home\/intermine\/intermine\/data/g' "${THE_MINE_DIR}"/project.xml
        sed -i 's/dump="true"/dump="false"/g' "${THE_MINE_DIR}"/project.xml

    fi
else
    echo "$(date +%Y/%m/%d-%H:%M) Set correct source path in project.xml"
    sed -i "s~${IM_DATA_DIR:-DATA_DIR}~"${PROJECT_ROOT}"/data~g" "${THE_MINE_DIR}"/project.xml
    sed -i 's/dump="true"/dump="false"/g' "${THE_MINE_DIR}"/project.xml
fi

# Copy data
if [ -d "${PROJECT_ROOT}"/data ]; then
    echo "$(date +%Y/%m/%d-%H:%M) found user data directory"
    if [ !  -n "$(find "${PROJECT_ROOT}"/data -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
        for f in *.tar.gz; do
            tar xzf "$f" && rm "$f"
        done
    fi
else
    echo "$(date +%Y/%m/%d-%H:%M) No user data directory found"
    mkdir -p "${PROJECT_ROOT}"/data/
    if [ ! -d "${PROJECT_ROOT}"/data/malaria ]; then
        if [ -f "${THE_MINE_DIR}"/data/malaria-data.tar.gz ]; then
            echo "$(date +%Y/%m/%d-%H:%M) Copy malaria-data to ~/data" #>> "${LOG_FILE}"
            cp "${THE_MINE_DIR}"/data/malaria-data.tar.gz "${PROJECT_ROOT}"/data/
            cd "${PROJECT_ROOT}"/data/
            tar -xf malaria-data.tar.gz
            rm malaria-data.tar.gz
        fi
    fi
fi


echo "$(date +%Y/%m/%d-%H:%M) Connect and create Postgres databases" #>> "${LOG_FILE}"

echo >&2 "$(date +%Y%m%dt%H%M%S) Postgres is up - executing command"

# Close all open connections to database
psql -U postgres -h ${THE_PGHOST} -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid();"

echo "$(date +%Y/%m/%d-%H:%M) Database is now available ..." #>> "${LOG_FILE}"
echo "$(date +%Y/%m/%d-%H:%M) Reset databases and roles" #>> "${LOG_FILE}"

# Delete Databases if exist
psql -U postgres -h ${THE_PGHOST} -c "DROP DATABASE IF EXISTS \"${THE_MINE_NAME}\";"
psql -U postgres -h ${THE_PGHOST} -c "DROP DATABASE IF EXISTS \"items-${THE_MINE_NAME}\";"
psql -U postgres -h ${THE_PGHOST} -c "DROP DATABASE IF EXISTS \"userprofile-${THE_MINE_NAME}\";"

# psql -U postgres -h ${THE_PGHOST} -c "DROP ROLE IF EXISTS ${PSQL_USER:-postgres};"

# Create Databases
echo "$(date +%Y/%m/%d-%H:%M) Creating postgres database tables and roles.." #>> "${LOG_FILE}"
# psql -U postgres -h ${THE_PGHOST} -c "CREATE USER ${PSQL_USER:-postgres} WITH PASSWORD '${PSQL_PWD:-postgres}';"
psql -U postgres -h ${THE_PGHOST} -c "ALTER USER ${PSQL_USER:-postgres} WITH SUPERUSER;"
psql -U postgres -h ${THE_PGHOST} -c "CREATE DATABASE \"${THE_MINE_NAME}\";"
psql -U postgres -h ${THE_PGHOST} -c "CREATE DATABASE \"items-${THE_MINE_NAME}\";"
psql -U postgres -h ${THE_PGHOST} -c "CREATE DATABASE \"userprofile-${THE_MINE_NAME}\";"
psql -U postgres -h ${THE_PGHOST} -c "GRANT ALL PRIVILEGES ON DATABASE \"${THE_MINE_NAME}\" to ${PSQL_USER:-postgres};"
psql -U postgres -h ${THE_PGHOST} -c "GRANT ALL PRIVILEGES ON DATABASE \"items-${THE_MINE_NAME}\" to ${PSQL_USER:-postgres};"
psql -U postgres -h ${THE_PGHOST} -c "GRANT ALL PRIVILEGES ON DATABASE \"userprofile-${THE_MINE_NAME}\" to ${PSQL_USER:-postgres};"


cd "${THE_MINE_DIR}"

echo "$(date +%Y/%m/%d-%H:%M) Running project_build script"
./project_build -b -T localhost "${PROJECT_ROOT}"/dump/dump

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: buildDB" #>> "${LOG_FILE}"
# ./gradlew buildDB --stacktrace #>> "${LOG_FILE}"

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: integrate uniprot-malaria" #>> "${LOG_FILE}"
# ./gradlew integrate -Psource=uniprot-malaria --stacktrace

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: integrate malaria-gff" #>> "${LOG_FILE}"
# ./gradlew integrate -Psource=malaria-gff --stacktrace

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: integrate malaria-chromosome-fasta" #>> "${LOG_FILE}"
# ./gradlew integrate -Psource=malaria-chromosome-fasta --stacktrace

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: integrate entrez-organism" #>> "${LOG_FILE}"
# ./gradlew integrate -Psource=entrez-organism --stacktrace

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: integrate update-publications" #>> "${LOG_FILE}"
# ./gradlew integrate -Psource=update-publications --stacktrace #>> "${LOG_FILE}"

# echo "$(date +%Y/%m/%d-%H:%M) Gradle: run post_processess" #>> "${LOG_FILE}"
# ./gradlew postProcess --stacktrace #>> "${LOG_FILE}"

echo "$(date +%Y/%m/%d-%H:%M) Gradle: build userDB" #>> "${LOG_FILE}"
./gradlew buildUserDB --stacktrace #>> "${LOG_FILE}"

echo "$(date +%Y/%m/%d-%H:%M) Gradle: build webapp" #>> "${LOG_FILE}"
# ./gradlew clean
# --stacktrace --debug --info --scan
./gradlew cargoRedeployRemote  --stacktrace

# Debug: Keep the container going
# tail -f /dev/null
