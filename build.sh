#!/usr/bin/env bash

# shellcheck disable=SC2059

set -eux

# Environments
export VERSION="0.0.1"
export RED="\033[1;31m%s\033[m\n"
export CYAN="\033[1;36m%s\033[m\n"
export GETOPTIONS_URL="https://github.com/ko1nksm/getoptions/releases/download/v3.3.0/getoptions"
export LLVM_MINGW_TAG_NAME="20231128"
export HANGOVER_REPOSITORY="https://github.com/AndreRH/hangover.git"
export BASE_PATH="/usr/lib/ccache:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

check_dependencies() {
    if ! (type curl > /dev/null 2>&1); then
        printf "${RED}" "curl command not found!"
        return 1
    else
        printf "${CYAN}" "curl command found!"
    fi

    if ! (type sudo > /dev/null 2>&1); then
        printf "${RED}" "sudo command not found!"
        return 1
    else
        printf "${CYAN}" "sudo command found!"
    fi
}

# Check options
check_options() {
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

# Detect arch
detect_arch() {
    if [ x86_64 = "${ARCH}" ]; then
        printf "${CYAN}" "You selected x86_64!"

        # x86_64 environments
        export LLVM_MINGW_ARCH="x86_64"
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
    elif [ arm64 = "${ARCH}" ]; then
        printf "${CYAN}" "You selected arm64!"

        # arm64 environments
        export LLVM_MINGW_ARCH="aarch64"
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
    fi
}

# Install ccache
install_ccache() {
    apt install -y ccache
    export CCACHE_DIR=/root/.ccache
}

# Install LLVM
install_llvm() {
    printf "${CYAN}" "Installing tar,xz-utils..."
    sudo apt install -y \
    tar \
    xz-utils

    printf "${CYAN}" "Installing LLVM..."
    mkdir -p llvm
    pushd llvm || exit

    curl -OL "$(curl -fsSL "https://api.github.com/repos/mstorsjo/llvm-mingw/releases/tags/${LLVM_MINGW_TAG_NAME}" |\
        grep browser_download_url |\
        grep ucrt |\
        grep ubuntu |\
        grep "${LLVM_MINGW_ARCH}" |\
        awk -F': ' '{print $2}' |\
        sed 's/"//g')"

    find llvm-mingw*.tar.xz -maxdepth 1 -exec tar -xvf {} \;
    find llvm-mingw*.tar.xz -maxdepth 1 -exec rm -f {} \;

    LLVM_MINGW_PATH="${PWD}/$(find llvm-mingw*/bin -maxdepth 0)"
    export LLVM_MINGW_PATH

    popd || exit
}

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
    CC='ccache gcc' CXX='ccache g++' ../configure --disable-werror --target-list=arm-linux-user,i386-linux-user
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
    CC='ccache clang' CXX='ccache clang++' cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_LTO=True -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False ..
    make -j"$(nproc)" FEXCore_shared

    popd || exit
}

# Build FEX PE
build_fex_pe() {
    printf "${CYAN}" "Building FEX(PE)..."
    export PATH="${LLVM_MINGW_PATH}:${BASE_PATH}"
    mkdir -p hangover/fex/build_pe
    pushd hangover/fex/build_pe || exit

    unset CC CXX
    CC='ccache clang' CXX='ccache clang++' cmake -DCMAKE_TOOLCHAIN_FILE=../toolchain_mingw.cmake -DENABLE_JEMALLOC=0 -DENABLE_JEMALLOC_GLIBC_ALLOC=0 -DMINGW_TRIPLE=aarch64-w64-mingw32 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False ..
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
    export PATH="${LLVM_MINGW_PATH}:${BASE_PATH}"
    pushd hangover/wine/build || exit

    unset CC CXX
    mkdir -p "../../../${INSTALL_FOLDER_NAME}"
    # shellcheck disable=SC2086
    CC='ccache gcc' CXX='ccache g++' ../configure ${WINE_BUILD_OPTION} --prefix="$(cd ../../../${INSTALL_FOLDER_NAME}; pwd;)"
    make -j"$(nproc)"

    printf "${CYAN}" "Installing Wine..."
    sudo env PATH="$PATH" make install

    popd || exit
}

copy_library() {
    if [ -f hangover/qemu/build/libqemu-arm.so ]; then
        printf "${CYAN}" "Copying libqemu-arm.so..."
        cp hangover/qemu/build/libqemu-arm.so "${INSTALL_FOLDER_NAME}/"
    fi

    if [ -f hangover/qemu/build/libqemu-i386.so ]; then
        printf "${CYAN}" "Copying libqemu-i386.so..."
        cp hangover/qemu/build/libqemu-i386.so "${INSTALL_FOLDER_NAME}/"
    fi

    if [ -f hangover/fex/build_unix/FEXCore/Source/libFEXCore.so ]; then
        printf "${CYAN}" "Copying libFEXCore.so..."
        cp hangover/fex/build_unix/FEXCore/Source/libFEXCore.so "${INSTALL_FOLDER_NAME}/"
    fi

    if [ -f hangover/fex/build_pe/Bin/libwow64fex.dll ]; then
        printf "${CYAN}" "Copying libwow64fex.dll..."
        cp hangover/fex/build_pe/Bin/libwow64fex.dll "${INSTALL_FOLDER_NAME}/"
    fi
}

# Run
check_dependencies
check_options "$@"
detect_arch
mkdir -p build
pushd build || exit
install_ccache
install_llvm
clone_hangover
build_qemu
build_fex_unix
build_fex_pe
build_wine
copy_library
printf "${CYAN}" "The build is complete!!"
popd || exit
