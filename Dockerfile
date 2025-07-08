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

# Install all dependencies including LDAP and Kubernetes tools
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
    ldap-utils \
    libldap2-dev \
    libldap-2.5-0 \
    slapd \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

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

# Configure LDAP and MongoDB
RUN echo "auth    required        pam_unix.so try_first_pass\naccount required        pam_unix.so" > /etc/pam.d/carta && \
    chown -R carta:carta /home/carta/mongodb && \
    echo '#!/bin/bash\nmongod --logpath /home/carta/mongodb/mongodb.log --dbpath /home/carta/mongodb/data --bind_ip 127.0.0.1' > /home/carta/start_mongodb.sh && \
    chmod +x /home/carta/start_mongodb.sh

# Create kill script for backend processes (for Kubernetes mode, this will be handled by pod deletion)
RUN echo '#!/bin/bash\necho "Backend termination handled by Kubernetes pod deletion"' > /usr/bin/kill_carta_backend && \
    chmod +x /usr/bin/kill_carta_backend

# Set up application
WORKDIR /home/carta/carta-controller-new
COPY . /home/carta/carta-controller-new/

# Install Node.js dependencies
RUN npm install

# Copy config and keys (using Kubernetes config)
COPY config/docker-k8s.config.json /etc/carta/config.json
COPY config/carta_public.pem /etc/carta/carta_public.pem
COPY config/carta_private.pem /etc/carta/carta_private.pem

# Create comprehensive LDAP initialization script
RUN cat > /home/carta/init_ldap.sh << 'EOF'
#!/bin/bash

# Start LDAP server if not already running
if ! pgrep slapd > /dev/null; then
    slapd -h "ldap:/// ldapi:///" &
    sleep 3
fi

# Wait for LDAP to be ready
until ldapsearch -x -H ldap://localhost:389 -b dc=nodomain -D cn=admin,dc=nodomain -w admin > /dev/null 2>&1; do
    echo "Waiting for LDAP to be ready..."
    sleep 2
done

# Create base LDIF file
cat > /tmp/base.ldif << 'LDIFEOF'
dn: dc=nodomain
objectClass: dcObject
objectClass: organization
dc: nodomain
o: CARTA
LDIFEOF

# Add base DN
ldapadd -x -D "cn=admin,dc=nodomain" -w admin -f /tmp/base.ldif

# Create organizational units
cat > /tmp/ou.ldif << 'LDIFEOF'
dn: ou=users,dc=nodomain
objectClass: organizationalUnit
ou: users

dn: ou=groups,dc=nodomain
objectClass: organizationalUnit
ou: groups
LDIFEOF

# Add OUs
ldapadd -x -D "cn=admin,dc=nodomain" -w admin -f /tmp/ou.ldif

# Create groups
cat > /tmp/groups.ldif << 'LDIFEOF'
dn: cn=carta-users,ou=groups,dc=nodomain
objectClass: posixGroup
objectClass: top
cn: carta-users
gidNumber: 1000
description: CARTA Users Group

dn: cn=carta-admins,ou=groups,dc=nodomain
objectClass: posixGroup
objectClass: top
cn: carta-admins
gidNumber: 1001
description: CARTA Administrators Group
LDIFEOF

# Add groups
ldapadd -x -D "cn=admin,dc=nodomain" -w admin -f /tmp/groups.ldif

# Create test users with proper group memberships
for i in {1..50}; do
    # Generate hashed password
    HASHED_PASS=$(slappasswd -s "testpass" -h "{SSHA}")
    
    cat > /tmp/user.ldif << LDIFEOF
dn: uid=testuser$i,ou=users,dc=nodomain
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
uid: testuser$i
sn: Test$i
givenName: User$i
cn: Test User$i
displayName: Test User$i
uidNumber: $((1000 + i))
gidNumber: 1000
userPassword: $HASHED_PASS
loginShell: /bin/bash
homeDirectory: /home/testuser$i
LDIFEOF

    # Add the user to LDAP
    ldapadd -x -D "cn=admin,dc=nodomain" -w admin -f /tmp/user.ldif
    rm /tmp/user.ldif
    mkdir -p /home/testuser$i/.carta/log
done

# Add admin user
HASHED_ADMIN_PASS=$(slappasswd -s "admin" -h "{SSHA}")

cat > /tmp/admin.ldif << LDIFEOF
dn: uid=admin,ou=users,dc=nodomain
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
uid: admin
sn: Admin
givenName: System
cn: System Admin
displayName: System Administrator
uidNumber: 2000
gidNumber: 1001
userPassword: $HASHED_ADMIN_PASS
loginShell: /bin/bash
homeDirectory: /home/admin
LDIFEOF

# Add admin user
ldapadd -x -D "cn=admin,dc=nodomain" -w admin -f /tmp/admin.ldif

# Clean up
rm /tmp/base.ldif /tmp/ou.ldif /tmp/groups.ldif /tmp/admin.ldif

# Synchronize LDAP users to system users
/home/carta/carta-controller-new/sync_ldap_users.sh

echo "LDAP initialization completed successfully!"
EOF

# Set proper permissions and ownership
RUN chmod 644 /etc/carta/config.json && \
    chmod 644 /etc/carta/carta_public.pem && \
    chmod 600 /etc/carta/carta_private.pem && \
    chmod +x /home/carta/init_ldap.sh && \
    chown -R carta:carta /home/carta && \
    chmod -R 755 /home/carta && \
    chmod -R 755 /home/carta/carta-controller-new/node_modules && \
    chown -R mona:mona /home/mona && \
    chmod -R 755 /home/mona && \
    chmod +x /home/carta/carta-controller-new/sync_ldap_users.sh

# Create startup script
RUN cat > /home/carta/start.sh << 'EOF'
#!/bin/bash

# Start MongoDB
/home/carta/start_mongodb.sh &
sleep 5

# Initialize LDAP with users and groups
/home/carta/init_ldap.sh

# Start the application
cd /home/carta/carta-controller-new
npm start -- --config /etc/carta/config.json
EOF

RUN chmod +x /home/carta/start.sh

EXPOSE 3002 3003 3004 389
CMD ["/home/carta/start.sh"] 