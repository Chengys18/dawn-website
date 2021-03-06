#!/usr/bin/env bash

# Script adapted from https://github.com/kappataumu/vagrant-up-github-pages

clonedir="/srv/www/dawn_website"

start_seconds="$(date +%s)"
echo "Welcome to the initialization script."
echo "Setting up DAWN Website Development Environment."

apt_packages=(
    vim
    curl
    git-core
    nodejs
    libgmp3-dev
    gnupg2
    gpgv2
)

ping_result="$(ping -c 2 8.8.4.4 2>&1)"
if [[ $ping_result != *bytes?from* ]]; then
    echo "Network connection unavailable. Try again later."
    exit 1
fi

# Needed for nodejs.
# https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions
curl -sSL https://deb.nodesource.com/setup_4.x | sudo -E bash -
sudo add-apt-repository -y ppa:git-core/ppa

sudo apt-get update
sudo apt-get upgrade

echo "Installing apt-get packages..."
sudo apt-get install -y ${apt_packages[@]}
sudo apt-get clean

# http://rvm.io/rvm/install
for server in ha.pool.sks-keyservers.net \
              hkp://p80.pool.sks-keyservers.net:80 \
              keyserver.ubuntu.com \
              hkp://keyserver.ubuntu.com:80 \
              pgp.mit.edu; do
    gpg --keyserver "$server" --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB && break || echo "Trying new server..."
done
curl -sSL https://get.rvm.io | bash -s stable --quiet-curl
source ~/.rvm/scripts/rvm
rvm install 2.6.4 --quiet-curl
rvm use 2.6.4 --default
ruby --version

# https://github.com/github/pages-gem
gem install github-pages

# Preemptively accept Github's SSH fingerprint, but only
# if we previously haven't done so.
fingerprint="$(ssh-keyscan -H github.com)"
if ! grep -qs "$fingerprint" ~/.ssh/known_hosts; then
    echo "$fingerprint" >> ~/.ssh/known_hosts
fi

# Vagrant should've created /srv/www according to the Vagrantfile,
# but let's make sure it exists even if run directly.
if [[ ! -d '/srv/www' ]]; then
    sudo mkdir '/srv/www'
    sudo chown vagrant:vagrant '/srv/www'
fi

# Now, for the Jekyll part. There are some issues you might hit:
#
# * Due to jekyll/jekyll#3030 we need to detach Jekyll from the shell manually,
#   if we want --watch to work.
#
# * We need Vagrant >= 1.8 to fix a regression that botched emission of the
#   vagrant-mounted upstart event, see mitchellh/vagrant#6074 for details.
#
# * We need Ruby 2.1.7p400 due to what appears to be a regression in Ruby's
#   FileUtils core module, see http://stackoverflow.com/q/33091988

jekyll=$(which jekyll)

wrapper="${jekyll/bin/wrappers}"
log="/home/vagrant/jekyll.log"
run="start-stop-daemon --start --chuid vagrant:vagrant --exec $wrapper -- serve --host 0.0.0.0 --source $clonedir --destination /home/vagrant/_site --watch --force_polling >> $log 2>&1 &"
eval $run

cat << UPSTART | sudo tee /etc/init/jekyll.conf > /dev/null
description "Jekyll"
author "kappataumu <hello@kappataumu.com>"

start on vagrant-mounted MOUNTPOINT=/srv/www/dawn_website

exec $run
UPSTART

end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$(expr $end_seconds - $start_seconds)" seconds"
echo "You can now use 'less -S +F $log' to monitor Jekyll."
