#!/usr/bin/env bash

# shellcheck disable=SC2059

set -eu

# Environments
export VERSION="0.0.1"
export RED="\033[1;31m%s\033[m\n"
export CYAN="\033[1;36m%s\033[m\n"
export GETOPTIONS_URL="https://github.com/ko1nksm/getoptions/releases/download/v3.3.0/getoptions"
export HANGOVER_REPOSITORY="https://github.com/AndreRH/hangover.git"
export BASE_PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Check options
check_options() {
    if ! (type curl > /dev/null 2>&1); then
        printf "${RED}" "curl command not found!"
        printf "${CYAN}" "Installing curl..."
        apt update
        apt install -y curl
    else
        printf "${CYAN}" "curl command found!"
    fi

    # getoptions: https://github.com/ko1nksm/getoptions
    getoptions() {
        curl -fsSL "${GETOPTIONS_URL}" | bash -s -- "$@"
    }

    parser_definition() {
        setup   REST help:usage abbr:true -- "Usage: $0 [options]..." ''
        msg -- 'Options:'
        param   ARCH    -a --arch pattern:"x86_64 | arm64" -- "Select 'arm64' or 'x86_64'"
        disp    :usage  -h --help
        disp    VERSION --version
    }

    eval "$(getoptions parser_definition - "$0") exit 1"
}

# Check sudo command
check_sudo_command() {
    if ! (type sudo > /dev/null 2>&1); then
        printf "${RED}" "sudo command not found!"
        printf "${CYAN}" "Installing sudo..."
        apt update
        apt install -y sudo
    else
        printf "${CYAN}" "sudo command found!"
    fi
}

# Get hangover repository hash
clone_hangover() {
    if ! (type git > /dev/null 2>&1); then
        printf "${RED}" "git command not found!"
        printf "${CYAN}" "Installing git..."
        apt update
        apt install -y git
    else
        printf "${CYAN}" "git command found!"
    fi

    git clone --recursive "${HANGOVER_REPOSITORY}" hangover
}

# Detect arch
detect_arch() {
    # Install dependencies
    install_dependencies() {
        printf "${CYAN}" "Installing dependencies..."
        sudo apt update
        # shellcheck disable=SC2086
        sudo apt install -y ${DEPENDENCIES}
    }

    # Install LLVM
    install_llvm() {
        printf "${CYAN}" "Installing LLVM..."
        mkdir -p llvm
        pushd llvm || exit
        curl -L -C - "${LLVM_URL}" > "${LLVM_FILE_NAME}"
        tar -xJf "${LLVM_FILE_NAME}"
        rm -f "${LLVM_FILE_NAME}"
        popd || exit
    }

    # Build QEMU
    build_qemu() {
        printf "${CYAN}" "Building QEMU..."
        export PATH="${BASE_PATH}"
        mkdir hangover/qemu/build
        pushd hangover/qemu/build || exit
        ../configure --disable-werror --target-list=arm-linux-user,i386-linux-user
        make -j"$(nproc)"
        popd || exit
    }

    # Build Wine
    build_wine() {
        printf "${CYAN}" "Building Wine..."
        mkdir -p hangover/wine/build
        pushd hangover/wine/build || exit
        export PATH="$PWD/llvm/${LLVM_FOLDER_NAME}/bin:${BASE_PATH}"
        # shellcheck disable=SC2086
        ../configure ${WINE_BUILD_OPTION}
        make -j"$(nproc)"
        make install --prefix "../../../${INSTALL_FOLDER_NAME}"
        popd || exit
    }

    # Detect arch
    if [ x86_64 = "${ARCH}" ]; then
        printf "${CYAN}" "You selected x86_64!"

        # x86_64 environments
        export DEPENDENCIES="
            gcc-multilib \
            gcc-mingw-w64 \
            libasound2-dev \
            libpulse-dev \
            libdbus-1-dev \
            libfontconfig-dev \
            libfreetype-dev \
            libgnutls28-dev \
            libgl-dev \
            libunwind-dev \
            libx11-dev \
            libxcomposite-dev \
            libxcursor-dev \
            libxfixes-dev \
            libxi-dev \
            libxrandr-dev \
            libxrender-dev \
            libxext-dev \
            libgstreamer1.0-dev \
            libgstreamer-plugins-base1.0-dev \
            libosmesa6-dev \
            libsdl2-dev \
            libudev-dev \
            libvulkan-dev \
            libcapi20-dev \
            libcups2-dev \
            libgphoto2-dev \
            libsane-dev \
            libkrb5-dev \
            samba-dev \
            ocl-icd-opencl-dev \
            libpcap-dev \
            libusb-1.0-0-dev \
            libv4l-dev \
            \
            flex \
            libbison-dev \
            clang
        "
        export LLVM_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20230614/llvm-mingw-20230614-ucrt-ubuntu-20.04-x86_64.tar.xz"
        export LLVM_FOLDER_NAME="llvm-mingw-20230614-ucrt-ubuntu-20.04-x86_64"
        export LLVM_FILE_NAME="${LLVM_FOLDER_NAME}.tar.xz"
        export WINE_BUILD_OPTION="--enable-win64 --disable-tests --with-mingw --enable-archs=i386,x86_64,arm"
        export INSTALL_FOLDER_NAME="build_x86_64"

        install_dependencies
        install_llvm
        build_qemu
        build_wine
    elif [ arm64 = "${ARCH}" ]; then
        printf "${CYAN}" "You selected arm64!"
        printf "${RED}" "not available"
        exit 1
    fi
}

# Run
check_options "$@"
mkdir -p build
pushd build || exit
check_sudo_command
clone_hangover
detect_arch
popd || exit
