FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Add repositories first
RUN apt-get update && apt-get install -y curl gnupg software-properties-common && \
    # Add MongoDB repository
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && \
    # Add NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    # Add CARTA repository
    add-apt-repository ppa:cartavis-team/carta && \
    apt-get update

# Install all dependencies
RUN apt-get install -y \
    sudo \
    nginx \
    git \
    build-essential \
    cmake \
    libssl-dev \
    libpam0g-dev \
    libmongoc-dev \
    libbson-dev \
    nodejs \
    mongodb-org \
    carta-backend \
    && rm -rf /var/lib/apt/lists/*

# Install zfp library
RUN git clone https://github.com/LLNL/zfp.git && \
    cd zfp && \
    git checkout 1.0.0 && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /zfp

# Create users and set up directories
RUN useradd -m -s /bin/bash carta && \
    echo "carta:carta" | chpasswd && \
    usermod -aG sudo carta && \
    useradd -m -s /bin/bash mona && \
    echo "mona:Captain01*" | chpasswd && \
    usermod -aG sudo mona && \
    mkdir -p /etc/carta \
    /home/carta/carta-controller-new/config \
    /home/carta/carta-controller-new/data \
    /home/carta/carta-controller-new/logs \
    /home/carta/.carta/log \
    /home/mona/.carta/log \
    /home/mona/carta-controller-new/data \
    /home/carta/mongodb/data

# Copy and set up backend
COPY carta_backend /usr/bin/carta_backend
RUN chmod 755 /usr/bin/carta_backend && \
    chown root:root /usr/bin/carta_backend

# Configure PAM and MongoDB
RUN echo "auth    required        pam_unix.so try_first_pass\naccount required        pam_unix.so" > /etc/pam.d/carta && \
    chown -R carta:carta /home/carta/mongodb && \
    echo '#!/bin/bash\nmongod --logpath /home/carta/mongodb/mongodb.log --dbpath /home/carta/mongodb/data --bind_ip 127.0.0.1' > /home/carta/start_mongodb.sh && \
    chmod +x /home/carta/start_mongodb.sh

# Set up application
WORKDIR /home/carta/carta-controller-new
COPY . /home/carta/carta-controller-new/

# Copy config and keys
RUN cp /home/carta/carta-controller-new/config/docker.config.json /etc/carta/config.json && \
    cp /home/carta/carta-controller-new/config/carta_public.pem /etc/carta/carta_public.pem && \
    cp /home/carta/carta-controller-new/config/carta_private.pem /etc/carta/carta_private.pem && \
    chmod 644 /etc/carta/config.json && \
    chmod 644 /etc/carta/carta_public.pem && \
    chmod 600 /etc/carta/carta_private.pem && \
    chown -R carta:carta /home/carta && \
    chmod -R 755 /home/carta && \
    chmod -R 755 /home/carta/carta-controller-new/node_modules && \
    chown -R mona:mona /home/mona && \
    chmod -R 755 /home/mona

# Set up sample files directory
RUN mkdir -p /home/carta/carta-controller-new/data && \
    chown -R carta:carta /home/carta/carta-controller-new/data && \
    chmod -R 755 /home/carta/carta-controller-new/data

# Set up application
WORKDIR /home/carta/carta-controller-new
COPY . /home/carta/carta-controller-new/

# Copy config and keys
RUN cp /home/carta/carta-controller-new/config/docker.config.json /etc/carta/config.json && \
    cp /home/carta/carta-controller-new/config/carta_public.pem /etc/carta/carta_public.pem && \
    cp /home/carta/carta-controller-new/config/carta_private.pem /etc/carta/carta_private.pem && \
    chmod 644 /etc/carta/config.json && \
    chmod 644 /etc/carta/carta_public.pem && \
    chmod 600 /etc/carta/carta_private.pem && \
    chown -R carta:carta /home/carta && \
    chmod -R 755 /home/carta && \
    chmod -R 755 /home/carta/carta-controller-new/node_modules && \
    chown -R mona:mona /home/mona && \
    chmod -R 755 /home/mona && \
    echo '#!/bin/bash\n\
/home/carta/start_mongodb.sh &\n\
sleep 5\n\
cd /home/carta/carta-controller-new\n\
npm start -- --config /etc/carta/config.json\n\
' > /home/carta/start.sh && \
    chmod +x /home/carta/start.sh

EXPOSE 3002 3003 3004
CMD ["/home/carta/start.sh"] 