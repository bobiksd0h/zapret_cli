#!/bin/bash
# Shared variables for the zapret terminal installer.
#
# NOTE on internal names: the upstream engine is bol-van/zapret2. Its installer
# fixes the install path to /opt/zapret2 and the init service name to "zapret2".
# These internal names cannot be renamed without breaking service control, so they
# stay as-is. Everything the user sees (menus, the command) is just "zapret".

# where the engine itself is installed (fixed by the upstream installer)
ZAPRET_BASE="/opt/zapret2"
# init service name (fixed by upstream: zapret2.service / init.d/zapret2)
SERVICE="zapret2"
# installed version marker
VER_FILE="/opt/zapret2-ver"
# upstream sources
ZAPRET_REPO="bol-van/zapret2"
ZAPRET_GIT="https://github.com/bol-van/zapret2"

# where this installer (scripts + bundled cfgs) is deployed
INSTALLER_DIR="/opt/zapret.installer"
# bundled strategies/lists/fake-bins (local-files design - no remote cfgs repo)
CFGS_DIR="$INSTALLER_DIR/cfgs"
# control symlink placed in PATH (the user-facing command)
BIN_LINK="/bin/zapret"
