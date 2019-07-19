#!/bin/sh

# Test script for Weblate docker container
#
# - test that Weblate is serving it's files
# - test creating admin user
# - runs testsuite
#
# Execute in docker-compose.yml directory, it will create containers and
# test them.

cat >>docker-compose.override.yml <<EOT
version: '3'
services:
  weblate:
    environment:
      WEBLATE_TIME_ZONE: Europe/Prague
EOT

echo "Starting up containers..."
export COMPOSE_PROJECT_NAME=wl
docker-compose up -d || exit 1
docker-compose ps
CONTAINER=`docker-compose ps | grep _weblate_ | sed 's/[[:space:]].*//'`
docker inspect $CONTAINER
IP=`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER`
PORT=8080

echo "Checking '$CONTAINER', IP address '$IP', Port '$PORT'"
TIMEOUT=0
while ! curl --fail --silent --output /dev/null "http://$IP:$PORT/" ; do
    sleep 1
    TIMEOUT=$(($TIMEOUT + 1))
    if [ $TIMEOUT -gt 60 ] ; then
        break
    fi
done
curl --verbose --fail "http://$IP:$PORT/about/" | grep 'Powered by.*Weblate'
RET=$?
curl --verbose --fail --output /dev/null "http://$IP:$PORT/static/weblate-128.png"
RET2=$?
# Display logs so far
docker-compose logs

if [ $RET2 -ne 0 -o $RET -ne 0 ] ; then
    exit 1
fi

echo "Python packages:"
docker-compose exec weblate pip3 list

echo "Deploy checks:"
docker-compose exec \
    --user weblate \
    --env WEBLATE_SILENCED_SYSTEM_CHECKS=weblate.E003,weblate.E017,security.W004,security.W008,security.W012,security.W018,weblate.I021 \
    weblate weblate check --deploy || exit 1

echo "Creating admin..."
docker-compose exec --user weblate weblate weblate createadmin || exit 1

echo "Supervisor status:"
docker-compose exec weblate supervisorctl status all || exit 1

echo "Running testsuite..."
docker-compose exec --user weblate --env DJANGO_SETTINGS_MODULE=weblate.settings_test weblate weblate test --noinput weblate.accounts weblate.trans weblate.lang weblate.api weblate.gitexport weblate.screenshots weblate.utils weblate.machinery weblate.auth weblate.formats weblate.fonts weblate.addons weblate.wladmin
if [ $? -ne 0 ] ; then
    docker-compose logs
    exit 1
fi

echo "Shutting down containers..."
docker-compose down || exit 1
