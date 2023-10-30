#!/usr/bin/env bash

# shellcheck disable=SC2059

set -eux

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
        sudo apt install -y curl
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
# check_sudo_command() {
#     if ! (type sudo > /dev/null 2>&1); then
#         printf "${RED}" "sudo command not found!"
#         printf "${CYAN}" "Installing sudo..."
#         apt update
#         apt install -y sudo
#     else
#         printf "${CYAN}" "sudo command found!"
#     fi
#
#     sudo apt update
# }

# Get hangover repository hash
clone_hangover() {
    if ! (type git > /dev/null 2>&1); then
        printf "${RED}" "git command not found!"
        printf "${CYAN}" "Installing git..."
        sudo apt install -y git
    else
        printf "${CYAN}" "git command found!"
    fi

    git clone --recursive "${HANGOVER_REPOSITORY}" hangover
}

# Detect arch
detect_arch() {
    # Install LLVM
    install_llvm() {
        printf "${CYAN}" "Installing tar,xz-utils..."
        sudo apt install -y \
        tar \
        xz-utils

        printf "${CYAN}" "Installing LLVM..."
        mkdir -p llvm
        pushd llvm || exit

        curl -L -o "${LLVM_FILE_NAME}" "${LLVM_URL}"
        tar -xJvf "${LLVM_FILE_NAME}"
        rm -f "${LLVM_FILE_NAME}"

        popd || exit
    }

    # Build QEMU
    build_qemu() {
        printf "${CYAN}" "Installing QEMU dependencies..."
        sudo apt install -y \
            libglib2.0-dev \
            libfdt-dev \
            libpixman-1-dev \
            zlib1g-dev \
            ninja-build \
            build-essential

        printf "${CYAN}" "Building QEMU..."
        export PATH="${BASE_PATH}"
        mkdir hangover/qemu/build
        pushd hangover/qemu/build || exit

        unset CC CXX
        ../configure --disable-werror --target-list=arm-linux-user,i386-linux-user
        make -j"$(nproc)"

        popd || exit
    }

    # Build FEX Unix
    build_fex_unix() {
        printf "${CYAN}" "Installing FEX dependencies..."
        sudo apt install -y \
            cmake \
            clang \
            libsdl2-dev \
            libepoxy-dev \
            build-essential

        printf "${CYAN}" "Building FEX(Unix)..."
        export PATH="${BASE_PATH}"
        mkdir -p hangover/fex/build_unix
        pushd hangover/fex/build_unix || exit

        unset CC CXX
        CC=clang CXX=clang++ cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_LTO=True -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False ..
        make -j"$(nproc)" FEXCore_shared

        popd || exit
    }

    # Build FEX PE
    build_fex_pe() {
        printf "${CYAN}" "Building FEX(PE)..."
        export PATH="$PWD/llvm/${LLVM_FOLDER_NAME}/bin:${BASE_PATH}"
        mkdir -p hangover/fex/build_pe
        pushd hangover/fex/build_pe || exit

        unset CC CXX
        cmake -DCMAKE_TOOLCHAIN_FILE=../toolchain_mingw.cmake -DENABLE_JEMALLOC=0 -DENABLE_JEMALLOC_GLIBC_ALLOC=0 -DMINGW_TRIPLE=aarch64-w64-mingw32 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False ..
        make -j"$(nproc)" wow64fex

        popd || exit
    }

    # Build Wine
    build_wine() {
        printf "${CYAN}" "Installing Wine dependencies..."
        # shellcheck disable=SC2086
        sudo apt install -y ${WINE_DEPENDENCIES}

        printf "${CYAN}" "Building Wine..."
        mkdir -p hangover/wine/build
        export PATH="$PWD/llvm/${LLVM_FOLDER_NAME}/bin:${BASE_PATH}"
        pushd hangover/wine/build || exit

        unset CC CXX
        # shellcheck disable=SC2086
        ../configure ${WINE_BUILD_OPTION} --prefix="../../../${INSTALL_FOLDER_NAME}"
        make -j"$(nproc)"

        printf "${CYAN}" "Installing Wine..."
        mkdir -p "../../../${INSTALL_FOLDER_NAME}"
        sudo env PATH="$PATH" make install

        popd || exit
    }

    copy_library() {
        if [ -f hangover/qemu/build/libqemu-arm.so ]; then
            printf "${CYAN}" "Copying libqemu-arm.so..."
            cp hangover/qemu/build/libqemu-arm.so ${INSTALL_FOLDER_NAME}/
        fi

        if [ -f hangover/qemu/build/libqemu-i386.so ]; then
            printf "${CYAN}" "Copying libqemu-i386.so..."
            cp hangover/qemu/build/libqemu-i386.so ${INSTALL_FOLDER_NAME}/
        fi

        if [ -f hangover/fex/build_unix/FEXCore/Source/libFEXCore.so ]; then
            printf "${CYAN}" "Copying libFEXCore.so..."
            cp hangover/fex/build_unix/FEXCore/Source/libFEXCore.so ${INSTALL_FOLDER_NAME}/
        fi

        if [ -f hangover/fex/build_pe/Bin/libwow64fex.dll ]; then
            printf "${CYAN}" "Copying libwow64fex.dll..."
            cp hangover/fex/build_pe/Bin/libwow64fex.dll ${INSTALL_FOLDER_NAME}/
        fi
    }

    sudo apt update

    # Detect arch
    if [ x86_64 = "${ARCH}" ]; then
        printf "${CYAN}" "You selected x86_64!"

        # x86_64 environments
        export LLVM_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20231017/llvm-mingw-20231017-ucrt-ubuntu-20.04-x86_64.tar.xz"
        export LLVM_FOLDER_NAME="llvm-mingw-20231017-ucrt-ubuntu-20.04-x86_64"
        export LLVM_FILE_NAME="${LLVM_FOLDER_NAME}.tar.xz"
        export INSTALL_FOLDER_NAME="build_x86_64"
        export WINE_DEPENDENCIES="
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
            flex \
            libbison-dev \
            build-essential
        "
        export WINE_BUILD_OPTION="--enable-win64 --disable-tests --with-mingw --enable-archs=i386,x86_64,arm"

        install_llvm
        build_qemu
        build_fex_unix
        build_fex_pe
        build_wine
        copy_library
    elif [ arm64 = "${ARCH}" ]; then
        printf "${CYAN}" "You selected arm64!"

        # arm64 environments
        export LLVM_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20231017/llvm-mingw-20231017-ucrt-ubuntu-20.04-aarch64.tar.xz"
        export LLVM_FOLDER_NAME="llvm-mingw-20231017-ucrt-ubuntu-20.04-aarch64"
        export LLVM_FILE_NAME="${LLVM_FOLDER_NAME}.tar.xz"
        export INSTALL_FOLDER_NAME="build_arm64"
        export WINE_DEPENDENCIES="
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
            flex \
            libbison-dev \
            build-essential
        "
        export WINE_BUILD_OPTION="--disable-tests --with-mingw --enable-archs=i386,aarch64,arm"

        install_llvm
        build_qemu
        build_fex_unix
        build_fex_pe
        build_wine
        copy_library
    fi
}

# Run
check_options "$@"
mkdir -p build
pushd build || exit
# check_sudo_command
clone_hangover
detect_arch
popd || exit
