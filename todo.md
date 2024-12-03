1. Do a check on all these commands on the running system and ensure these exists. Otherwise, ask to download.
    It might be better to prevent the user with a initial message that these packages should be installed to make the script fully compatible. Create a specific command for that.
    * rsync (depends on the distro)
    * realpath (not on macOS by default)
    * dpkg (only on Debian-based systems)
    * gdb (might need to be installed separately)
    * make (sometimes needs to be installed separately)
    * wget (may need to be installed if not available)

2. Detect and use the default package-manager of the current running Unix system.
   Currently using `apt-get`, which is only debian-based.