#!/bin/bash
# 4gauteauOS Build Environment Setup Script

echo "========================================="
echo "4gauteauOS Build Environment Setup"
echo "========================================="

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo "Please do not run as root"
    exit 1
fi

# Check Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
if [[ "$UBUNTU_VERSION" != "20.04" && "$UBUNTU_VERSION" != "22.04" ]]; then
    echo "Warning: Ubuntu 20.04 or 22.04 recommended. You're on $UBUNTU_VERSION"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Installing required packages..."
sudo apt-get update
sudo apt-get install -y \
    git-core gnupg flex bison build-essential zip curl zlib1g-dev \
    gcc-multilib g++-multilib libc6-dev-i386 libncurses5 lib32ncurses5-dev \
    x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils \
    xsltproc unzip fontconfig python3 python3-pip python3-venv \
    repo rsync schedtool ccache libssl-dev liblz4-tool \
    libxml2-utils lzma lzop m4 libtinfo5 libncurses5-dev \
    libncursesw5-dev libreadline-dev libgmp-dev libmpfr-dev \
    libmpc-dev zip unzip zstd

echo "Step 2: Setting up Git..."
git config --global user.name "4gauteauOS Developer"
git config --global user.email "developer@4gauteauos.com"
git config --global color.ui auto

echo "Step 3: Installing repo tool..."
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo

# Add ~/bin to PATH if not already
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
fi

echo "Step 4: Setting up environment variables..."
cat >> ~/.bashrc << 'EOF'

# 4gauteauOS Build Environment
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR=~/.ccache
ccache -M 50G

# Java (for older Android versions)
# export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
# export PATH=$JAVA_HOME/bin:$PATH

# For Android 11+
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

# Build aliases
alias m='make -j$(nproc)'
alias mm='mma'
alias mmm='mmma'

EOF

source ~/.bashrc

echo "Step 5: Creating workspace directory..."
mkdir -p ~/4gauteauOS
cd ~/4gauteauOS

echo "Step 6: Initializing repo with 4gauteauOS manifest..."
repo init -u https://github.com/4gauteauOS/manifests -b main -m default.xml

echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Sync the source code:"
echo "   cd ~/4gauteauOS"
echo "   repo sync -c -j$(nproc) --no-tags --no-clone-bundle"
echo ""
echo "2. Set up build environment:"
echo "   source build/envsetup.sh"
echo ""
echo "3. Choose lunch target:"
echo "   lunch aosp_crosshatch-userdebug  # For Pixel 3 XL"
echo "   lunch aosp_bonito-userdebug      # For Pixel 3a"
echo "   lunch aosp_coral-userdebug       # For Pixel 4"
echo ""
echo "4. Start build:"
echo "   m -j$(nproc)"
echo ""
echo "Note: First sync will download ~150GB of data"
echo "      Build will take 3-6 hours depending on hardware"
echo "========================================="