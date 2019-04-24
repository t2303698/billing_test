#!/bin/bash
# XMRig road warrior installer for OS X, Debian, Ubuntu and CentOS

# This script will work on OS X, Debian, Ubuntu, CentOS and probably other distros
# of the same families, although no support is offered for them. It isn't
# bulletproof but it will probably work. It has been designed to be as unobtrusive and
# universal as possible.

# Made by Hash to Cash @H2Cash, based on pagespeed script

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -qs "dash"; then
	echo "This script needs to be run with bash, not sh"
	exit 1
fi

RED=31
GREEN=32
YELLOW=33
function begin_color() {
  color="$1"
  echo -e -n "\033[0;${color}m"
}
function end_color() {
  echo -e -n "\033[0m"
}

function echo_color() {
  color="$1"
  shift
  begin_color "$color"
  echo "$@"
  end_color
}

function run() {
  if "$DRYRUN"; then
    echo_color "$YELLOW" -n "would run"
    echo " $@"
    env_differences=$(comm -13 <(echo "$INITIAL_ENV") <(printenv | sort))
    if [ -n "$env_differences" ]; then
      echo "  with the following additional environment variables:"
      echo "$env_differences" | sed 's/^/    /'
    fi
  else
    if ! "$@"; then
      error "Failure running '$@', exiting."
      exit 1
    fi
  fi
}

function status() {
  echo_color "$GREEN" "$@"
}
function error() {
  local error_message="$@"
  echo_color "$RED" -n "Error: " >&2
  echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
  error "$@"

  # Normally I'd use $0 in "usage" here, but since most people will be running
  # this via curl, that wouldn't actually give something useful.
  echo >&2
  echo "For usage information, run this script with --help" >&2
  exit 1
}

function redhat_is_installed() {
  local package_name="$1"
  rpm -qa $package_name | grep -q .
}

function brew_is_installed() {
  local package_name="$1"
  brew ls --versions $package_name > /dev/null
}

function debian_is_installed() {
  local package_name="$1"
  dpkg -l $package_name | grep ^ii | grep -q .
}

# Usage:
#  install_dependencies install_pkg_cmd is_pkg_installed_cmd dep1 dep2 ...
#
# install_pkg_cmd is a command to install a dependency
# is_pkg_installed_cmd is a command that returns true if the dependency is
#   already installed
# each dependency is a package name
function install_dependencies() {
  local install_pkg_cmd="$1"
  local is_pkg_installed_cmd="$2"
  shift 2

  local missing_dependencies=""

  for package_name in "$@"; do
    if ! $is_pkg_installed_cmd $package_name; then
      missing_dependencies+="$package_name "
    fi
  done
  if [ -n "$missing_dependencies" ]; then
    status "Detected that we're missing the following depencencies:"
    echo "  $missing_dependencies"
    status "Installing them:"
    if [[ "$unamestr" == 'Darwin' ]]; then
        $install_pkg_cmd $missing_dependencies
    else
        $install_pkg_cmd $missing_dependencies
    fi
  fi
}

function usage() {
    echo "
Usage: build_xmrig.sh [options]
    Installs xmrig and its dependencies. Can be run either as:
        bash <(curl -f -L -sS https://hashto.cash/bash_install) [options]
Options:
   -v, --xmrig-tag
        What tag (version) of xmrig to build. Valid options are Git tags, include:
        * v2.8.1
        * v2.8.0-rc
        * v2.6.4
        * v2.6.3
        * ...etc
    -p, --no-deps-check
        By default, this script checks for the packages it depends on and tries to
        install them.  If you have installed dependencies from source or are on a
        non-deb non-rpm system, this won't work.  In that case, install the
        dependencies yourself and pass --no-deps-check.
    -i, --install
        Installs xmrig at /usr/local/bin or /usr/bin.
    -a, --additional-cmake-configure-arguments
      When running \`cmake ..\` for xmrig, you may want to specify additional
      arguments, such as -DWITH_AEON=OFF. For
      example, you might do:
        -a '-DWITH_AEON=OFF -DUV_LIBRARY=/usr/lib/x86_64-linux-gnu/libuv.a'
    -b, --builddir <directory>
        Where to build.  Defaults to \$HOME.
    -f, --force
        Use if you want to delete build directory if exists.
    -h, --help
        Print this message and exit.
"
}

unamestr=`uname`
get_opt='getopt'

function getopt_path() {
    if [[ "$unamestr" == 'Darwin' ]]; then
        which -s brew
        if [[ $? != 0 ]] ; then
            status "Brew not found. Installing it..."
            # Install Homebrew
            # https://github.com/mxcl/homebrew/wiki/installation
            sudo /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
        else
            brew update
        fi

        install_dependencies "brew install" brew_is_installed gnu-getopt

        get_opt="$(brew --prefix gnu-getopt)/bin/getopt"
    fi
}

function build_xmrig() {
    if [[ "$unamestr" == 'Darwin' ]]; then
        # We have to install Xcode before anything.
        xcode-select --install
    fi
    getopt_path

    $get_opt --test
    if [ "$?" != 4 ]; then
        # Even Centos 5 and Ubuntu 10 LTS have new-style getopt, so I don't expect
        # this to be hit in practice on systems that are actually able to run
        # XMRig.
        fail "Your version of getopt is too old.  Exiting with no changes made."
    fi

    opts=$($get_opt -o v:pigna:b:hf \
        --longoptions xmrig-tag:,no-deps-check,install,force \
        --longoptions buildir:,use-gcc-7,dont-use-gcc-7 \
        --longoptions additional-cmake-configure-arguments:,help \
        -n "$(basename "$0")" -- "$@")
    if [ $? != 0 ]; then
        usage
        exit 1
    fi
    eval set -- "$opts"

    XMRIG_TAG="master"
    DO_DEPS_CHECK=true
    INSTALL=false
    FORCE=false
    ADDITIONAL_CMAKE_CONFIGURE_ARGUMENTS=""
    USE_GCC_7=false
    BUILDDIR="$HOME"

    if [ -f /etc/debian_version ]; then
        USE_GCC_7=true
    fi

    while true; do
    case "$1" in
      -v | --xmrig-tag) shift
        XMRIG_TAG="$1"
        shift
        ;;
      -b | --builddir) shift
        BUILDDIR="$1"
        shift
        ;;
      -p | --no-deps-check) shift
        DO_DEPS_CHECK=false
        ;;
      -i | --install) shift
        INSTALL=true
        ;;
      -f | --force) shift
        FORCE=true
        ;;
      -g | --use-gcc-7) shift
        USE_GCC_7=true
        ;;
      -n | --dont-use-gcc-7) shift
        USE_GCC_7=false
        ;;
      -y | --assume-yes) shift
        ASSUME_YES="true"
        ;;
      -a | --additional-cmake-configure-arguments) shift
        ADDITIONAL_CMAKE_CONFIGURE_ARGUMENTS="$1"
        shift
        ;;
      -h | --help) shift
        usage
        exit 0
        ;;
      --) shift
        break
        ;;
      *)
        echo "Invalid argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  # Now make sure our dependencies are installed.
  if "$DO_DEPS_CHECK"; then

    if [ -f /etc/debian_version ]; then
      status "Detected debian-based distro."

      ADDITIONAL_CMAKE_CONFIGURE_ARGUMENTS+=" -DOPENSSL_ROOT_DIR=/usr/local/ssl -DOPENSSL_LIBRARIES=/usr/local/ssl/lib"
      install_dependencies "apt-get install -y" debian_is_installed \
        software-properties-common git build-essential cmake libuv1-dev libmicrohttpd-dev libssl-dev

    elif [ -f /etc/redhat-release ]; then
      status "Detected redhat-based distro."

    ADDITIONAL_CMAKE_CONFIGURE_ARGUMENTS+=" -DOPENSSL_ROOT_DIR=/usr/local/ssl -DOPENSSL_LIBRARIES=/usr/local/ssl/lib"
      install_dependencies "yum install -y" redhat_is_installed \
        epel-release git make cmake gcc gcc-c++ libstdc++-static libmicrohttpd-devel libuv-static openssl-devel

    elif [[ "$unamestr" == 'Darwin' ]]; then
        status "Detected OS X distro."

        ADDITIONAL_CMAKE_CONFIGURE_ARGUMENTS+=" -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl"
        install_dependencies "brew install" brew_is_installed cmake libuv libmicrohttpd openssl
    else
      fail "
This doesn't appear to be a deb-based distro or an rpm-based one.  Not going to
be able to install dependencies. Please install dependencies manually and rerun
with --no-deps-check."
    fi

    status "Operating system dependencies are all set."
  else
    status "Not checking whether operating system dependencies are installed."
  fi

  if [ ! -d "$BUILDDIR" ]; then
    fail "Told to build in $BUILDDIR, but that directory doesn't exist."
  fi

  cd "$BUILDDIR"
  if [ -d "$BUILDDIR/xmrig" ]; then
    if "$FORCE"; then
        rm -Rf "$BUILDDIR/xmrig"
    else
        fail "Directory $BUILDDIR/xmrig already exists. Remove it first (rm -Rf $BUILDDIR/xmrig) or use another --buildDir or use --force"
    fi
  fi

  status "Checking out xmrig on $XMRIG_TAG..."
  git clone "https://github.com/xmrig/xmrig.git"
  cd xmrig

  git checkout "$XMRIG_TAG"

  mkdir build
  cd build

  status "Building..."
  cmake .. $ADDITIONAL_CMAKE_CONFIGURE_ARGUMENTS
  make

  XMRIG_FILE="xmrig"
  if "$INSTALL"; then
    status "We moving binary to /usr/local/bin. You can skip this step, so xmrig will be available from $BUILDDIR/xmrig/build/xmrig."
    if echo "$PATH" | grep /usr/local/bin; then
        sudo mv xmrig /usr/local/bin
        status "Success! xmrig has been installed to /usr/local/bin and now availabe from \$PATH."
    else
        sudo mv xmrig /usr/bin
        echo 'Success! xmrig has been installed to /usr/bin and now availabe from \$PATH.'
    fi
    else
        XMRIG_FILE="$BUILDDIR/xmrig/build/xmrig"
        status "Success! XMRig located under $BUILDDIR/xmrig/build/xmrig"
  fi

  status "Usage example: $XMRIG_FILE -o xmr.pool.hashto.cash:80 -O \033[1ma43a0540-aebc-11e7-baaa-330048cb5252\033[0m:x --max-cpu-usage 100"

  status "Don't forget to replace ID with your email or ID (https://hashto.cash/profile). Happy mining! ðŸŽ‰"
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
build_xmrig "$@"
