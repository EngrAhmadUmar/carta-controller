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

# Install all dependencies including LDAP
RUN apt-get update && apt-get install -y \
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
    ldap-utils \
    libldap2-dev \
    libldap-2.5-0 \
    slapd \
    && rm -rf /var/lib/apt/lists/*

# Configure slapd non-interactively
RUN debconf-set-selections << EOF
slapd slapd/password1 password admin
slapd slapd/password2 password admin
slapd slapd/domain string nodomain
slapd shared/organization string NoDomain
slapd slapd/backend string MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
EOF

# Reconfigure slapd with our settings
RUN dpkg-reconfigure -f noninteractive slapd

# Create base LDIF
RUN cat > /tmp/base.ldif << EOF
dn: dc=nodomain
objectClass: top
objectClass: dcObject
objectClass: organization
o: NoDomain
dc: nodomain

dn: cn=admin,dc=nodomain
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
userPassword: {SSHA}3XwbwWa4IzgUBy3qScahf8qOtMZ5DUrK
description: LDAP administrator

dn: ou=users,dc=nodomain
objectClass: organizationalUnit
ou: users
EOF

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
    /home/carta/mongodb/data \
    /etc/ldap

# Copy and set up backend
COPY carta_backend /usr/bin/carta_backend
RUN chmod 755 /usr/bin/carta_backend && \
    chown root:root /usr/bin/carta_backend

# Configure LDAP and MongoDB
RUN echo "auth    required        pam_unix.so try_first_pass\naccount required        pam_unix.so" > /etc/pam.d/carta && \
    chown -R carta:carta /home/carta/mongodb && \
    echo '#!/bin/bash\nmongod --logpath /home/carta/mongodb/mongodb.log --dbpath /home/carta/mongodb/data --bind_ip 127.0.0.1' > /home/carta/start_mongodb.sh && \
    chmod +x /home/carta/start_mongodb.sh

# Set up application
WORKDIR /home/carta/carta-controller-new
COPY . /home/carta/carta-controller-new/

# Copy config and keys
COPY config/docker.config.json /etc/carta/config.json
COPY config/carta_public.pem /etc/carta/carta_public.pem
COPY config/carta_private.pem /etc/carta/carta_private.pem
RUN chmod 644 /etc/carta/config.json && \
    chmod 644 /etc/carta/carta_public.pem && \
    chmod 600 /etc/carta/carta_private.pem && \
    chown -R carta:carta /home/carta && \
    chmod -R 755 /home/carta && \
    chmod -R 755 /home/carta/carta-controller-new/node_modules && \
    chown -R mona:mona /home/mona && \
    chmod -R 755 /home/mona && \
    chmod +x /home/carta/carta-controller-new/sync_ldap_users.sh && \
    echo '#!/bin/bash\n\
# Start MongoDB\n\
/home/carta/start_mongodb.sh &\n\
sleep 5\n\
\n\
# Start LDAP server if not already running\n\
if ! pgrep slapd > /dev/null; then\n\
    slapd -h "ldap:/// ldapi:///" &\n\
    sleep 2\n\
fi\n\
\n\
# Start the application\n\
cd /home/carta/carta-controller-new\n\
npm start -- --config /etc/carta/config.json\n\
' > /home/carta/start.sh && \
    chmod +x /home/carta/start.sh

EXPOSE 3002 3003 3004 389
CMD ["/home/carta/start.sh"] 