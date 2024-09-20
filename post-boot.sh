#!/usr/bin/env bash

# Constants and Paths
XRT_BASE_PATH="/proj/octfpga-PG0/tools/deployment/xrt"
SHELL_BASE_PATH="/proj/octfpga-PG0/tools/deployment/shell"
XBFLASH_BASE_PATH="/proj/octfpga-PG0/tools/xbflash"
VITIS_BASE_PATH="/proj/octfpga-PG0/tools/Xilinx/Vitis"
CONFIG_FPGA_PATH="/proj/octfpga-PG0/tools/post-boot"
FACTORY_SHELL="xilinx_u280_GOLDEN_8"

# Detect OS Version
OSVERSION=`grep '^ID=' /etc/os-release | awk -F= '{print $2}'`
OSVERSION=`echo $OSVERSION | tr -d '"'`
VERSION_ID=`grep '^VERSION_ID=' /etc/os-release | awk -F= '{print $2}'`
VERSION_ID=`echo $VERSION_ID | tr -d '"'`
OSVERSION="$OSVERSION-$VERSION_ID"

# Input Arguments
WORKFLOW=$1
TOOLVERSION=$2
VITISVERSION="2023.1"
SCRIPT_PATH=/local/repository

# Extract package info from spec.txt
COMB="${TOOLVERSION}_${OSVERSION}"
XRT_PACKAGE=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $1}' | awk -F= '{print $2}'`
SHELL_PACKAGE=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $2}' | awk -F= '{print $2}'`
DSA=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $3}' | awk -F= '{print $2}'`
PACKAGE_NAME=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $5}' | awk -F= '{print $2}'`
PACKAGE_VERSION=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $6}' | awk -F= '{print $2}'`
XRT_VERSION=`grep ^$COMB: $SCRIPT_PATH/spec.txt | awk -F':' '{print $2}' | awk -F';' '{print $7}' | awk -F= '{print $2}'`

# Node ID for PCIe operations
NODE_ID=$(hostname | cut -d'.' -f1)

# Install XRT
install_xrt() {
    echo "Installing XRT..."
    if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
        apt update
        apt install -y $XRT_BASE_PATH/$TOOLVERSION/$OSVERSION/$XRT_PACKAGE
    fi
    sudo bash -c "echo 'source /opt/xilinx/xrt/setup.sh' >> /etc/profile"
    sudo bash -c "echo 'source $VITIS_BASE_PATH/$VITISVERSION/settings64.sh' >> /etc/profile"
}

# Install Shell Package
install_shellpkg() {
    if [[ "$U280" == 0 ]]; then
        echo "[WARNING] No FPGA Board Detected."
        exit 1
    fi
    echo "Installing shell package..."
    if [[ $SHELL_PACKAGE == *.tar.gz ]]; then
        tar xzvf $SHELL_BASE_PATH/$TOOLVERSION/$OSVERSION/$SHELL_PACKAGE -C /tmp/
    fi
    if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
        apt-get install -y /tmp/xilinx*
    fi
    rm /tmp/xilinx*
}

# Install xbflash
install_xbflash() {
    echo "Installing xbflash..."
    cp -r $XBFLASH_BASE_PATH/${OSVERSION} /tmp
    if [[ "$OSVERSION" == "ubuntu-18.04" ]] || [[ "$OSVERSION" == "ubuntu-20.04" ]]; then
        apt install /tmp/${OSVERSION}/*.deb
    fi
}

# Check XRT Installation
check_xrt() {
    if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
        XRT_INSTALL_INFO=`apt list --installed 2>/dev/null | grep "xrt" | grep "$XRT_VERSION"`
    fi
}

# Check Shell Package Installation
check_shellpkg() {
    if [[ "$OSVERSION" == "ubuntu-20.04" ]] || [[ "$OSVERSION" == "ubuntu-22.04" ]]; then
        PACKAGE_INSTALL_INFO=`apt list --installed 2>/dev/null | grep "$PACKAGE_NAME" | grep "$PACKAGE_VERSION"`
    fi
}

# Check Requested Shell
check_requested_shell() {
    SHELL_INSTALL_INFO=`/opt/xilinx/xrt/bin/xbmgmt examine | grep "$DSA"`
}

# Flash the FPGA Card
flash_card() {
    echo "Flashing the FPGA card..."
    /opt/xilinx/xrt/bin/xbmgmt program --base --device $PCI_ADDR
}

# Detect FPGA Cards
detect_cards() {
    lspci > /dev/null
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

# Install additional libraries
install_libs() {
    echo "Installing additional libraries..."
    sudo $VITIS_BASE_PATH/$VITISVERSION/scripts/installLibs.sh
}

# Install FPGA configuration
install_config_fpga() {
    echo "Installing FPGA configuration..."
    cp $CONFIG_FPGA_PATH/* /usr/local/bin
}

# Disable PCIe Fatal Errors
disable_pcie_fatal_error() {
    echo "Disabling PCIe fatal error reporting for node: $NODE_ID"
    sudo /proj/octfpga-PG0/tools/pcie_disable_fatal.sh $PCI_ADDR
}

# Main Script Execution
echo "Post-boot script for fpga-p4-oct-fabric profile"

# Detect FPGA Cards
detect_cards

# Check and Install XRT
check_xrt
if [[ $? == 0 ]]; then
    echo "XRT is already installed."
else
    echo "Installing XRT..."
    install_xrt
    check_xrt
    if [[ $? != 0 ]]; then
        echo "Error: XRT installation failed."
        exit 1
    fi
fi

# Install Libraries
install_libs

# Disable PCIe Fatal Errors
disable_pcie_fatal_error

# Install FPGA Configuration
install_config_fpga

# Handle Shell and Workflow
if [[ "$WORKFLOW" == "Vitis" ]]; then
    check_shellpkg
    if [[ $? == 0 ]]; then
        echo "Shell is already installed."
        check_requested_shell
        if [[ $? == 0 ]]; then
            echo "FPGA shell verified."
        else
            echo "Error: FPGA shell couldn't be verified."
            exit 1
        fi
    else
        echo "Installing shell..."
        install_shellpkg
        check_shellpkg
        if [[ $? == 0 ]]; then
            echo "Shell installation successful. Flashing the card..."
            flash_card
        else
            echo "Error: Shell installation failed."
            exit 1
        fi
    fi
else
    echo "Custom workflow selected. Installing xbflash..."
    install_xbflash
fi

echo "Post-boot script completed."
