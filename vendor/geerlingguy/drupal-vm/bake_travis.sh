#!/bin/bash
#
# Bake a Docker container with Drupal VM.

# Exit on any individual command failure.
set -e

# Set variables.
DRUPALVM_IP_ADDRESS="${DRUPALVM_IP_ADDRESS:-192.168.88.88}"
DRUPALVM_MACHINE_NAME="${DRUPALVM_MACHINE_NAME:-earth}"
DRUPALVM_HOSTNAME="${DRUPALVM_HOSTNAME:-earth.local}"
DRUPALVM_PROJECT_ROOT="${DRUPALVM_PROJECT_ROOT:-/var/www/earth}"

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
docker run --name=$DRUPALVM_MACHINE_NAME -d \
  --add-host "$DRUPALVM_HOSTNAME":127.0.0.1 \
  -v $PWD:$DRUPALVM_PROJECT_ROOT/:$volume_opts \
  $OPTS \
  geerlingguy/docker-$DISTRO-ansible:latest \
  $INIT

# Create Drupal directory.
docker exec $DRUPALVM_MACHINE_NAME mkdir -p $DRUPALVM_PROJECT_ROOT

# Set things up and run the Ansible playbook.
status "Running setup playbook..."
docker exec --tty $DRUPALVM_MACHINE_NAME env TERM=xterm \
  ansible-playbook $DRUPALVM_PROJECT_ROOT/vendor/geerlingguy/drupal-vm/tests/test-setup.yml

status "Provisioning Drupal VM inside Docker container..."
docker exec $DRUPALVM_MACHINE_NAME env TERM=xterm ANSIBLE_FORCE_COLOR=true \
  ansible-playbook $DRUPALVM_PROJECT_ROOT/vendor/geerlingguy/drupal-vm/provisioning/playbook.yml

status "...done!"
status "Visit the Drupal VM dashboard: http://$DRUPALVM_IP_ADDRESS"

status "Install BLT alias and vim"
docker exec $DRUPALVM_MACHINE_NAME /var/www/earth/vendor/acquia/blt/scripts/blt/install-alias.sh -y

status "Installing Chrome 59.0.3071.104"
docker exec $DRUPALVM_MACHINE_NAME sudo apt-get install libxss1 libappindicator1 libindicator7 vim wget -y
docker exec $DRUPALVM_MACHINE_NAME wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

# Unpackaging chrome returns an error because it is missing dependencies, which is not a problem,
# We install them a moment later.  So adding || true to be sure this behavior does not quite the script.
docker exec $DRUPALVM_MACHINE_NAME sudo dpkg -i google-chrome-stable_current_amd64.deb || true
docker exec $DRUPALVM_MACHINE_NAME sudo apt-get -f install -y
docker exec $DRUPALVM_MACHINE_NAME google-chrome --version

status "Installing Chromedriver"
docker exec $DRUPALVM_MACHINE_NAME wget https://chromedriver.storage.googleapis.com/2.30/chromedriver_linux64.zip
docker exec $DRUPALVM_MACHINE_NAME unzip chromedriver_linux64.zip
docker exec $DRUPALVM_MACHINE_NAME sudo mv -f chromedriver /usr/local/share/chromedriver
docker exec $DRUPALVM_MACHINE_NAME sudo ln -s /usr/local/share/chromedriver /usr/local/bin/chromedriver
docker exec $DRUPALVM_MACHINE_NAME sudo ln -s /usr/local/share/chromedriver /usr/bin/chromedriver
status "Starting Selenium"
docker exec $DRUPALVM_MACHINE_NAME service selenium start

status "Installing Site, this make take a while"
# Forcing this to resolve as true, so the script may continue.
# Content is not able to be imported at the comment.
docker exec $DRUPALVM_MACHINE_NAME sh -c "cd /var/www/earth && vendor/bin/blt local:setup" || true

status "Running tests"
docker exec $DRUPALVM_MACHINE_NAME sh -c "cd /var/www/earth/tests/behat && ../../vendor/bin/behat -p default --colors features"

read -p "Would you like to log into the test environment? Yes to login, No to quit. " -n 1 -r
echo "\n"
if [[ $REPLY =~ ^[Yy]$ ]]; then
  docker exec -it $DRUPALVM_MACHINE_NAME earth bash
else
 exit
fi