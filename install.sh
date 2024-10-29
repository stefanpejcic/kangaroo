#!/bin/bash


sudo apt update
sudo apt install fzf




# Ensure these lines are set as follows:
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

sudo systemctl restart ssh
