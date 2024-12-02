# Noxfly Project Manager

A free, lightweight and open-source project manager for linux C/C++ projects.

Always struggled to manage a project where every members of the team are in different OS, and with libraries at different paths ?

This scripts helps you improve your time by :
- Managing packages, config, compilation and run
- for cross-env development
- whether for a personal or team project
with a lightweight configuration and use.

## Prerequisites

For now, the use of this script only works in a Unix like environment.
However, once you generated the base of the project with the script, it will also create a CMake configuration, that'll can be used across OS and configurations.

You'll need to have these packages preinstalled :
- cmake
- make
- wget
- rsync
- a compiler and/or a debugger, depending your needs: gcc, g++, gdb

### Future improvements :

It currently only uses `dpkg`, `awk` and `apt-get` for some commands.
This is available by default on a Debian-based distro, but not for every distros.
I'll make sure to make this compatible to other distros soon.

## Installation and use

Make this command to download the script and make it globally available on your computer.

```sh
sudo wget --https-only -O /usr/local/bin/nf https://raw.githubusercontent.com/NoxFly/nfpm/refs/heads/main/nf.sh
sudo chmod 755 /usr/local/bin/nf # allow to read/write/execute properly depending the user
# then you can do anywhere :
nf --help
```

## Basic commands

```sh
# new project
nf init

# build
nf build

# [build] + run
nf run
```

Add the `-v` flag to put some commands in verbose mode.

## Advanced commands

This section will be filled soon.