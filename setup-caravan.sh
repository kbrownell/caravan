#!/bin/bash
#
# This script assumes you are running this file from the repository root directory.
# For example, /var/www/se3_blt

# Setup config file paths
BEHAT_DEFAULT_CONFIG="vendor/su-sws/drupal-caravan/config/behat.yml"
DRUPALVM_CONFIG="vendor/su-sws/drupal-caravan/config/caravan.yml"
DRUSH_ALIAS="vendor/su-sws/drupal-caravan/config/caravan.aliases.drushrc.php"

# Bake a Docker container with Drupal VM.

# Exit on any individual command failure.
set -e

# Set variables.
DRUPALVM_IP_ADDRESS="${DRUPALVM_IP_ADDRESS:-192.168.88.88}"
DRUPALVM_MACHINE_NAME="${DRUPALVM_MACHINE_NAME:-earth}"
DRUPALVM_HOSTNAME="${DRUPALVM_HOSTNAME:-earth.local}"
DRUPALVM_PROJECT_ROOT="${DRUPALVM_PROJECT_ROOT:-/var/www/earth}"

DRUPALVM_HTTP_PORT="${DRUPALVM_HTTP_PORT:-9000}"
DRUPALVM_HTTPS_PORT="${DRUPALVM_HTTPS_PORT:-9001}"

DISTRO="${DISTRO:-ubuntu1604}"
OPTS="${OPTS:---privileged}"
INIT="${INIT:-/lib/systemd/systemd}"

# Helper function to colorize statuses.
function status() {
  status=$1
  printf "\n"
  echo -e -n "\033[32m$status"
  echo -e '\033[0m'
}

# Set volume options.
if [[ "$OSTYPE" == "darwin"* ]]; then
  volume_opts='rw,cached'
else
  volume_opts='rw'
fi

# Run the container.
status "Bringing up Docker container..."
if [ "$ENVIRONMENT" == "travis" ]; then
  docker run --name=$DRUPALVM_MACHINE_NAME -d \
    --add-host "$DRUPALVM_HOSTNAME":127.0.0.1 \
    -v $PWD:$DRUPALVM_PROJECT_ROOT/:$volume_opts \
    $OPTS \
    geerlingguy/docker-$DISTRO-ansible:latest \
    $INIT
else
  docker run --name=$DRUPALVM_MACHINE_NAME -d \
    --add-host "$DRUPALVM_HOSTNAME":127.0.0.1 \
    -v $PWD:$DRUPALVM_PROJECT_ROOT/:$volume_opts \
    -p $DRUPALVM_IP_ADDRESS:$DRUPALVM_HTTP_PORT:80 \
    -p $DRUPALVM_IP_ADDRESS:$DRUPALVM_HTTPS_PORT:443 \
    -v $HOME/.ssh/acquia_id_rsa:/root/.ssh/id_rsa \
    -v $HOME/.ssh/acquia_id_rsa.pub:/root/.ssh/id_rsa.pub \
    $OPTS \
    geerlingguy/docker-$DISTRO-ansible:latest \
    $INIT
fi

# Create Drupal directory.
docker exec $DRUPALVM_MACHINE_NAME mkdir -p $DRUPALVM_PROJECT_ROOT

# Set things up and run the Ansible playbook.
status "Running setup playbook..."
docker exec --tty $DRUPALVM_MACHINE_NAME env TERM=xterm \
  ansible-playbook $DRUPALVM_PROJECT_ROOT/vendor/geerlingguy/drupal-vm/tests/test-setup.yml

status "Provisioning Drupal VM inside Docker container..."
docker exec $DRUPALVM_MACHINE_NAME env TERM=xterm ANSIBLE_FORCE_COLOR=true \
  DRUPALVM_ENV=acquia \
  ansible-playbook $DRUPALVM_PROJECT_ROOT/vendor/su-sws/drupal-caravan/provisioning/playbook.yml

status "...done!"
status "Visit the Drupal VM dashboard: http://$DRUPALVM_IP_ADDRESS:$DRUPALVM_HTTP_PORT"

# Do not run in continuous integration environments
if [ -z "$ENVIRONMENT" ]; then
  read -p "Would you like to log into the test environment? Yes to login, No to quit. " -n 1 -r
  echo "\n"
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker exec -it $DRUPALVM_MACHINE_NAME bash
  else
   exit
  fi
fi
