# Use OpenSUSE Leap as the base image
# Just an experiment.
FROM opensuse/leap:15.6@sha256:8b764b0497b17a85ef5ac8f388ead8449d4e334e8a741d6529c45be2e14d66e5

# Update system and install necessary packages
RUN zypper refresh \
    && zypper install -y \
    curl \
    gzip \
    tar \
    which \
    git \
    vim \
    ripgrep \
    fd \
    fzf \
    bat \
    jq \
    nodejs20 \
    java-21-openjdk-devel \
    python3 \
    python3-pip \
    xorg-x11-server \
    xorg-x11-fonts \
    # Install Firefox
    MozillaFirefox \
    # Install additional tools if needed
    && zypper clean --all

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-353.0.0-linux-x86_64.tar.gz \
    && tar -xzf google-cloud-sdk-353.0.0-linux-x86_64.tar.gz -C /usr/local/ \
    && rm google-cloud-sdk-353.0.0-linux-x86_64.tar.gz \
    && /usr/local/google-cloud-sdk/install.sh --quiet
ENV PATH="/usr/local/google-cloud-sdk/bin:${PATH}"

# Reduce image size and prevent issues with different mirror states
RUN zypper lr && zypper --no-refresh

# Setup environment variables
ENV JAVA_HOME /usr/lib64/jvm/java-21-openjdk
ENV PATH $JAVA_HOME/bin:$PATH

# Command to run when the container starts
CMD ["bash"]
