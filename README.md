# Noxfly Project Manager

A free, lightweight and open-source project manager for linux C/C++ projects.

Always struggled to manage a project where every members of the team are in different OS, and with libraries at different paths ?

This scripts helps you improve your time by :
- Managing packages, config, compilation and run
- for cross-env development
- whether for a personal or team project
with a lightweight configuration and use.

## Prerequisites

For now, the use of this script only works in a Unix like environment (Linux, MacOS, MingW, Cygwin, ...).
However, once you generated the base of the project with the script, it will also create a CMake configuration, that'll can be used across OS and configurations.

**Bash 4 is required for the script to work.**

## Installation and use

Make this command to download the script and make it globally available on your computer.
Adapt to your OS.

```sh
# wGET
sudo wget --https-only -O /usr/local/bin/nf https://raw.githubusercontent.com/NoxFly/nfpm/refs/heads/main/nf.sh
# cURL
sudo curl --fail --location --output /usr/local/bin/nf https://raw.githubusercontent.com/NoxFly/nfpm/refs/heads/main/nf.sh
# Permission to execute, and read/write for updating itself when requested
sudo chmod 755 /usr/local/bin/nf
# Test :
nf --version
nf --help
```

## Basic commands

Add the `-v` or `--verbose` flag to put some commands in verbose mode.

### Update the script

```sh
# Download the latest version of the script
nf --update
nf -U
```

### Create, compile and run a project

```sh
# new project
nf new
# build
nf build
# [build] + run
nf run
```

The `new` command can take parameters to customize the project directly from the beginning.

If you wish to create a new nf project with already existing code structure, then running the `new` command will just create a `project.yml` and missing stuff.

All the parameters are optional.

A path can be specified as first argument. If not present, it will create a new project in the current directory.

```sh
# these are the default values
nf new . --name=NewProject --lang=cpp --mode=0 --guard=ifndef
# example of a non default base configuration
nf new ./poc --name=poc --lang=c --mode=1 --guard=pragma

# with verbose :
nf new -v

# if no language specified and not set in global config
# it will ask you :
nf new
# Choose the project language (c/CPP):
# (cpp is chosen if you hit Enter with blank value)
```

Note : specifying a name during the `nf new` command via the `--name` argument does not allow spaces in it. Don't worry, you'll can change it later thanks a dedicated command (see below).

#### Files generation

```sh
# create a class depending the current project's architecture
nf g c MyClass

# architecture mode 0 generates this :
# src/MyClass.cpp
# include/MyClass.hpp

# architecture mode 1 generates this :
# src/MyClass/MyClass.cpp
# src/MyClass/MyClass.hpp

nf g c core/MyClass
# if folders of the specified path do not exist
# it will create them
```

### Libraries

You can manage easily libraries in your project.

Associate a keywork to one or more packages that will be used by your project.

Then, when a someone else goes in your project, he just have to ask the script to download them all !

#### To add some packages
```sh
nf add GLEW libglew-dev
nf add SDL2 libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev

# example output :
# 3 added, 2 installed, 0 failed in 0m 4s 656ms
```

Your project configuration file will then have these lines added :

```yml
dependencies:
  GLEW: libglew-dev
  SDL2: libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev
```

If a package is not installed on your computer, it will try to install It.
If it fails, the package won't be added to your project's configuration.

These lines are always sorted by their key.

#### Ask to install all packages :
```sh
nf install # or nf i
```

If a package is already installed on your computer, it will just skip it in the installation process.

#### Remove or uninstall packages

To remove a package from a project :

It will ask you for each of the packages for the key you entered if you want to also uninstall it from your computer (default to 'No').

```sh
nf remove SDL2 # or nf rm
# SDL2 packages have been removed from the project.
# uninstall libsdl2-dev ? (y/N)
# uninstall libsdl2-image-dev ? (y/N)
# uninstall libsdl2-ttf-dev ? (y/N)
nf remove SDL2 -y # answer in advance 'yes' to uninstall every packages
nf remove SDL2 -n # answer in advance 'no' to uninstall every packages
```

If you wish to directly uninstall a package, you can :
```sh
nf uninstall libsdl2-dev # or nf u
```

`libsdl2-dev` is then removed from the project and the computer.

#### List packages of a project

```sh
nf list # or nf l
# ├─  GLEW
# │      └ libglew-dev
# └─  SDL2
#        ├ libsdl2-dev
#        ├ libsdl2-image-dev
#        └ libsdl2-ttf-dev
```

### Project's management

The following commands help you manage your project easily.

It is recommended to NOT modify by yourself the `project.yml` file, even for overview.

To change things in your `project.yml`, do the following command, with key begin a key that exists in this file, inside the `project` or `config` section

```sh
nf set <key> <value>

# For instance :
nf set name My super project
# results in :
#   - `name: My Super Project` inside the project.yml file
#   - updates the project's name also in the cmake file (capitalized) : MySuperProject

nf set author NoxFly
nf set license MIT

nf set mode 1
# this lets you switch between architectures.
# it moves your files accordingly.
# if it fails, it backups.
```

If an author is set, copyrights will automatically added at the beginning of created files with the `nf g` command.

If a license is set in addition to the author, it is added below the author.

#### Update the version of your project :

```sh
nf patch
nf minor
nf major
```