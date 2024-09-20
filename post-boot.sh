#!/usr/bin/env bash

# Function to install XRT
install_xrt() {
    echo "Download XRT installation package"
    wget -cO - "https://www.xilinx.com/bin/public/openDownload?filename=$XRT_PACKAGE" > /tmp/$XRT_PACKAGE
    
    echo "Install XRT"
    if [[ "$OSVERSION" == "ubuntu-16.04" ]] || [[ "$OSVERSION" == "ubuntu-18.04" ]] || [[ "$OSVERSION" == "ubuntu-20.04" ]]; then
        echo "Ubuntu XRT install"
        echo "Installing XRT dependencies..."
        apt update
        echo "Installing XRT package..."
        apt install -y /tmp/$XRT_PACKAGE
    elif [[ "$OSVERSION" == "centos-7" ]]; then
        echo "CentOS 7 XRT install"
        echo "Installing XRT dependencies..."
        yum install -y epel-release
        echo "Installing XRT package..."
        yum install -y /tmp/$XRT_PACKAGE
    elif [[ "$OSVERSION" == "centos-8" ]]; then
        echo "CentOS 8 XRT install"
        echo "Installing XRT dependencies..."
        yum config-manager --set-enabled powertools
        yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        yum config-manager --set-enabled appstream
        echo "Installing XRT package..."
        sudo yum install -y /tmp/$XRT_PACKAGE
    fi
}

# Function to install the FPGA shell package
install_shellpkg() {
    if [[ "$U280" == 0 ]]; then
        echo "[WARNING] No FPGA Board Detected."
        exit 1;
    fi

    for PF in U280; do
        if [[ "$(($PF))" != 0 ]]; then
            echo "You have $(($PF)) $PF card(s)."
            PLATFORM=`echo "alveo-$PF" | awk '{print tolower($0)}'`
            install_u280_shell
        fi
    done
}

# Check if shell package is installed
check_shellpkg() {
    if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
        PACKAGE_INSTALL_INFO=`apt list --installed 2>/dev/null | grep "$PACKAGE_NAME" | grep "$PACKAGE_VERSION"`
    elif [[ "$OSVERSION" == "centos-8" ]]; then
        PACKAGE_INSTALL_INFO=`yum list installed 2>/dev/null | grep "$PACKAGE_NAME" | grep "$PACKAGE_VERSION"`
    fi
}

# Check if XRT is installed
check_xrt() {
    if [[ "$OSVERSION" == "ubuntu-16.04" ]] || [[ "$OSVERSION" == "ubuntu-18.04" ]] || [[ "$OSVERSION" == "ubuntu-20.04" ]]; then
        XRT_INSTALL_INFO=`apt list --installed 2>/dev/null | grep "xrt" | grep "$XRT_VERSION"`
    elif [[ "$OSVERSION" == "centos-7" ]] || [[ "$OSVERSION" == "centos-8" ]]; then
        XRT_INSTALL_INFO=`yum list installed 2>/dev/null | grep "xrt" | grep "$XRT_VERSION"`
    fi
}

# Function to install xbflash
install_xbflash() {
    cp -r /proj/oct-fpga-p4-PG0/tools/xbflash/${OSVERSION} /tmp
    echo "Installing xbflash."
    if [[ "$OSVERSION" == "ubuntu-18.04" ]] || [[ "$OSVERSION" == "ubuntu-20.04" ]]; then
        apt install /tmp/${OSVERSION}/*.deb
    elif [[ "$OSVERSION" == "centos-7" ]] || [[ "$OSVERSION" == "centos-8" ]]; then
        yum install /tmp/${OSVERSION}/*.rpm
    fi    
}

# Check the requested shell
check_requested_shell() {
    SHELL_INSTALL_INFO=`/opt/xilinx/xrt/bin/xbmgmt examine | grep "$DSA"`
}

# Flash the FPGA card
flash_card() {
    echo "Flashing FPGA card."
    /opt/xilinx/xrt/bin/xbmgmt program --base --device $PCI_ADDR
}

# Detect FPGA cards
detect_cards() {
    lspci > /dev/null
    if [ $? != 0 ] ; then
        if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
            apt-get install -y pciutils
        elif [[ "$OSVERSION" == "centos-7" ]] || [[ "$OSVERSION" == "centos-8" ]]; then
            yum install -y pciutils
        fi
    fi
    if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
        PCI_ADDR=$(lspci -d 10ee: | awk '{print $1}' | head -n 1)
        if [ -n "$PCI_ADDR" ]; then
            U280=$((U280 + 1))
        else
            echo "Error: No card detected."
            exit 1
        fi
    fi
}

# Function to install config-fpga
install_config_fpga() {
    echo "Installing config-fpga."
    cp /proj/oct-fpga-p4-PG0/tools/post-boot/* /usr/local/bin
}

# Disable PCIe fatal error reporting
disable_pcie_fatal_error() {
    echo "Disabling PCIe fatal error reporting."
    sudo /proj/oct-fpga-p4-PG0/tools/pcie_disable_fatal.sh $PCI_ADDR
}

# Main script starts here

XRT_BASE_PATH="/proj/oct-fpga-p4-PG0/tools/deployment/xrt"
SHELL_BASE_PATH="/proj/oct-fpga-p4-PG0/tools/deployment/shell"
XBFLASH_BASE_PATH="/proj/oct-fpga-p4-PG0/tools/xbflash"
CONFIG_FPGA_PATH="/proj/oct-fpga-p4-PG0/tools/post-boot"
VITIS_BASE_PATH="/proj/oct-fpga-p4-PG0/tools/Xilinx/Vitis"

OSVERSION=`grep '^ID=' /etc/os-release | awk -F= '{print $2}'`
OSVERSION=`echo $OSVERSION | tr -d '"'`
VERSION_ID=`grep '^VERSION_ID=' /etc/os-release | awk -F= '{print $2}'`
VERSION_ID=`echo $VERSION_ID | tr -d '"'`
OSVERSION="$OSVERSION-$VERSION_ID"

WORKFLOW=$1
TOOLVERSION=$2
VITISVERSION="2023.1"
SCRIPT_PATH=/local/repository
COMB="${TOOLVERSION}_${OSVERSION}"

XRT_PACKAGE=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $1}' | awk -F= '{print $2}'`
SHELL_PACKAGE=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $2}' | awk -F= '{print $2}'`
DSA=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $3}' | awk -F= '{print $2}'`
PACKAGE_NAME=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $5}' | awk -F= '{print $2}'`
PACKAGE_VERSION=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $6}' | awk -F= '{print $2}'`
XRT_VERSION=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $7}' | awk -F= '{print $2}'`

# Start card detection and XRT check
echo "User name: $USER"
detect_cards

check_xrt
if [ $? == 0 ]; then
    echo "XRT is already installed."
else
    echo "XRT is not installed. Attempting to install XRT..."
    install_xrt

    check_xrt
    if [ $? == 0 ]; then
        echo "XRT was successfully installed."
    else
        echo "Error: XRT installation failed."
        exit 1
    fi
fi

install_libs
disable_pcie_fatal_error 
install_config_fpga

# Check workflow
if [ "$WORKFLOW" = "Vitis" ]; then
    check_shellpkg
    if [ $? == 0 ]; then
        echo "Shell is already installed."
        if check_requested_shell; then
            echo "FPGA shell verified."
        else
            echo "Error: FPGA shell couldn't be verified."
            exit 1
        fi
    else
        echo "Shell is not installed. Installing shell..."
        install_shellpkg
        check_shellpkg
        if [ $? == 0 ]; then
            echo "Shell installed successfully. Flashing the FPGA."
            flash_card
        else
            echo "Error: Shell installation failed."
            exit 1
        fi
    fi
fi
