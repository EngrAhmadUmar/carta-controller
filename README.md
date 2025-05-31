# CARTA Controller

CARTA Controller is a secure, containerized web application for managing and monitoring CARTA (Common Astronomy Research Applications) backend services. It provides a user-friendly interface for administrators to control and monitor CARTA instances.

## Features

- Secure user authentication with PAM integration
- Real-time monitoring of CARTA backend services
- SSL/TLS encryption for secure communication
- Containerized deployment for easy installation
- Support for multiple user roles (admin and regular users)
- Comprehensive logging and error tracking

## System Requirements

- Docker 20.10.0 or higher
- Linux host system with PAM support
- Minimum 2GB RAM
- 10GB free disk space

## Installation

1. Clone the repository:
   ```bash
git clone https://github.com/your-org/carta-controller.git
cd carta-controller
```

2. Build the Docker image:
   ```bash
   docker build -t carta-controller .
   ```

3. Run the container:
   ```bash
   docker run -d \
     --name carta-controller \
  -p 3000:3000 \
  -p 3002:3002 \
  -v /etc/pam.d:/etc/pam.d:ro \
  -v /etc/shadow:/etc/shadow:ro \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/group:/etc/group:ro \
     carta-controller
   ```

## Configuration

### Environment Variables

The following environment variables can be configured:

- `PORT`: Web interface port (default: 3000)
- `BACKEND_PORT`: CARTA backend port (default: 3002)
- `NODE_ENV`: Environment mode (development/production)

### SSL/TLS Configuration

SSL certificates are automatically generated during container build. The certificates are stored in:
- Public key: `/home/carta/carta-controller-new/config/carta_public.pem`
- Private key: `/home/carta/carta-controller-new/config/carta_private.pem`

### User Management

The system supports two types of users:
1. Admin users (member of the `carta` group)
2. Regular users

User authentication is handled through PAM, with the following requirements:
- Users must exist in the system's `/etc/passwd`
- Admin users must be members of the `carta` group
- The `carta` user must be a member of the `shadow` group for user lookups

## Directory Structure

```
carta-controller/
├── config/                 # Configuration files
│   ├── carta_public.pem   # SSL public key
│   └── carta_private.pem  # SSL private key
├── src/                   # Source code
│   ├── routes/           # API routes
│   ├── controllers/      # Business logic
│   ├── models/          # Data models
│   └── utils/           # Utility functions
├── public/              # Static assets
├── views/              # Frontend templates
└── logs/              # Application logs
```

## Security

### Authentication

- PAM-based authentication for system users
- SSL/TLS encryption for all communications
- Secure password handling
- Role-based access control

### File Permissions

- SSL keys: 600 (private) and 644 (public)
- Log files: 755
- Configuration files: 644
- User home directories: 755

## Logging

Logs are stored in the following locations:
- Application logs: `/home/carta/.carta/log/`
- User-specific logs: `/home/<username>/.carta/log/`

## API Endpoints

### Authentication
- `POST /api/auth/login`: User login
- `POST /api/auth/logout`: User logout

### CARTA Management
- `GET /api/carta/status`: Get CARTA backend status
- `POST /api/carta/start`: Start CARTA backend
- `POST /api/carta/stop`: Stop CARTA backend
- `GET /api/carta/logs`: Get CARTA backend logs

### User Management
- `GET /api/users`: List users (admin only)
- `POST /api/users`: Create user (admin only)
- `DELETE /api/users/:id`: Delete user (admin only)

## Troubleshooting

### Common Issues

1. **Login Failures**
   - Verify user exists in `/etc/passwd`
   - Check user's group membership
   - Ensure PAM configuration is correct

2. **Permission Denied**
   - Verify directory permissions
   - Check user's group membership
   - Ensure SSL keys are properly configured

3. **Backend Connection Issues**
   - Verify backend port (3002) is accessible
   - Check backend process status
   - Review backend logs

### Log Files

- Application logs: `/home/carta/.carta/log/carta.log`
- User logs: `/home/<username>/.carta/log/carta.log`
- Docker logs: `docker logs carta-controller`

## Development

### Building from Source

1. Install dependencies:
   ```bash
npm install
```

2. Build the application:
```bash
npm run build
```

3. Start the development server:
```bash
npm run dev
```

### Testing

Run the test suite:
   ```bash
npm test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support, please:
1. Check the troubleshooting guide
2. Review the documentation
3. Open an issue on GitHub
4. Contact the development team

## Acknowledgments

- CARTA Project Team
- Open Source Contributors
- System Administrators

## Local Development vs Docker Setup

### Local Development Setup

For local development, you'll need to set up the environment manually:

1. Install system dependencies:
   ```bash
sudo apt-get update
sudo apt-get install -y \
    libpam0g-dev \
    libssl-dev \
    nodejs \
    npm
```

2. Create required users and groups:
   ```bash
sudo groupadd carta
sudo useradd -m -g carta carta
sudo usermod -aG shadow carta
```

3. Set up directories and permissions:
   ```bash
sudo mkdir -p /etc/carta
sudo mkdir -p /home/carta/.carta/log
sudo mkdir -p /home/carta/carta-controller-new/config
sudo chown -R carta:carta /etc/carta /home/carta/.carta
sudo chmod 755 /home/carta/.carta
```

4. Generate SSL certificates:
```bash
sudo -u carta openssl genrsa -out /home/carta/carta-controller-new/config/carta_private.pem 2048
sudo -u carta openssl rsa -in /home/carta/carta-controller-new/config/carta_private.pem -pubout -out /home/carta/carta-controller-new/config/carta_public.pem
sudo chmod 600 /home/carta/carta-controller-new/config/carta_private.pem
sudo chmod 644 /home/carta/carta-controller-new/config/carta_public.pem
```

### Configuration Differences

#### Local Development Configuration

In local development, configuration is managed through:

1. Environment variables in `.env` file:
```bash
PORT=3000
BACKEND_PORT=3002
NODE_ENV=development
```

2. PAM configuration in `/etc/pam.d/carta`:
```
auth required pam_unix.so
account required pam_unix.so
```

3. User management through system files:
- `/etc/passwd`: User accounts
- `/etc/group`: Group memberships
- `/etc/shadow`: Password hashes

#### Docker Configuration

In Docker, configuration is handled through:

1. Environment variables in `docker-compose.yml`:
```yaml
environment:
  - NODE_ENV=production
  - MONGODB_URI=mongodb://127.0.0.1:27017
  - MONGODB_DATABASE=carta
  - CARTA_SERVER_PORT=3003
  - CARTA_SERVER_INTERFACE=0.0.0.0
```

2. Volume mounts for data persistence:
```yaml
volumes:
  - type: volume
    source: carta-mongodb-data
    target: /data/db
  - type: volume
    source: carta-logs
    target: /home/carta/carta-controller-new/logs
  - type: volume
    source: carta-data
    target: /home/carta/carta-controller-new/data
```

3. Configuration file mounts:
```yaml
volumes:
  - type: bind
    source: ./config/docker.config.json
    target: /home/carta/carta-controller-new/config/config.json
    read_only: true
  - type: bind
    source: ./config/carta_public.pem
    target: /etc/carta/carta_public.pem
    read_only: true
  - type: bind
    source: ./config/carta_private.pem
    target: /etc/carta/carta_private.pem
    read_only: true
```

### Key Differences

1. **User Management**
   - Local: Manual user/group creation and PAM configuration
   - Docker: Automated setup of both `carta` and `mona` users with specific permissions

2. **File Permissions**
   - Local: Manual permission setup required
   - Docker: Handled automatically during container build with specific permissions for each directory

3. **SSL Certificates**
   - Local: Manual generation and placement
   - Docker: Mounted from host system with read-only access

4. **Environment Isolation**
   - Local: Direct system access
   - Docker: Isolated container environment with MongoDB running internally

5. **Configuration Updates**
   - Local: Direct file modifications
   - Docker: Requires container rebuild or volume updates

### Configuration Files

#### Local Development

1. `.env`:
```bash
PORT=3003
MONGODB_URI=mongodb://localhost:27017
MONGODB_DATABASE=carta
CARTA_SERVER_PORT=3003
CARTA_SERVER_INTERFACE=0.0.0.0
```

2. `config.json`:
```json
{
  "auth": {
    "type": "pam",
    "pamService": "carta"
  },
  "ssl": {
    "publicKey": "/etc/carta/carta_public.pem",
    "privateKey": "/etc/carta/carta_private.pem"
  },
  "logging": {
    "level": "debug",
    "path": "/home/carta/carta-controller-new/logs"
  },
  "mongodb": {
    "uri": "mongodb://127.0.0.1:27017",
    "database": "carta"
  }
}
```

#### Docker Environment

1. `docker-compose.yml`:
```yaml
version: '3.8'
services:
  carta-controller:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: carta-controller
    ports:
      - "3003:3003"
      - "27018:27017"
    volumes:
      - type: volume
        source: carta-mongodb-data
        target: /data/db
      - type: volume
        source: carta-logs
        target: /home/carta/carta-controller-new/logs
      - type: volume
        source: carta-data
        target: /home/carta/carta-controller-new/data
      - type: bind
        source: ./config/docker.config.json
        target: /home/carta/carta-controller-new/config/config.json
        read_only: true
      - type: bind
        source: ./config/carta_public.pem
        target: /etc/carta/carta_public.pem
        read_only: true
      - type: bind
        source: ./config/carta_private.pem
        target: /etc/carta/carta_private.pem
        read_only: true
    environment:
      - NODE_ENV=production
      - MONGODB_URI=mongodb://127.0.0.1:27017
      - MONGODB_DATABASE=carta
      - CARTA_SERVER_PORT=3003
      - CARTA_SERVER_INTERFACE=0.0.0.0
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/home/carta/carta-controller-new/healthcheck.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s

volumes:
  carta-mongodb-data:
    driver: local
  carta-logs:
    driver: local
  carta-data:
    driver: local
```

2. `Dockerfile`:
```dockerfile
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Add repositories
RUN apt-get update && apt-get install -y curl gnupg software-properties-common && \
    # Add MongoDB repository
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && \
    # Add NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    # Add CARTA repository
    add-apt-repository ppa:cartavis-team/carta && \
    apt-get update

# Install dependencies
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
    carta-backend

# Create users and directories
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

# Set up application
WORKDIR /home/carta/carta-controller-new
COPY . /home/carta/carta-controller-new/

# Configure permissions
RUN chown -R carta:carta /home/carta && \
    chmod -R 755 /home/carta && \
    chown -R mona:mona /home/mona && \
    chmod -R 755 /home/mona

EXPOSE 3002 3003 3004
CMD ["/home/carta/start.sh"]
```

## Detailed System Architecture

### Authentication System

The CARTA Controller uses a multi-layered authentication system:

1. **PAM Authentication**
   - Uses system-level PAM (Pluggable Authentication Modules)
   - Configuration in `/etc/pam.d/carta`:
     ```
     auth    required        pam_unix.so try_first_pass
     account required        pam_unix.so
     ```
   - `try_first_pass`: Attempts to use previously entered password
   - `pam_unix.so`: Uses system's password database

2. **User Roles**
   - **Admin Users** (carta group members):
     - Full system access
     - Can manage other users
     - Can control CARTA backend processes
   - **Regular Users**:
     - Can start/stop their own CARTA instances
     - Limited to their own data directories
     - Cannot modify system settings

### MongoDB Integration

The system uses MongoDB for data persistence:

1. **Database Structure**
   ```
   carta/
   ├── users/           # User information and preferences
   ├── sessions/        # Active user sessions
   ├── processes/       # CARTA backend process information
   └── logs/           # System and user activity logs
   ```

2. **Connection Configuration**
   - Internal MongoDB instance runs on port 27017
   - Externally mapped to port 27018 to avoid conflicts
   - Connection string: `mongodb://127.0.0.1:27017`
   - Database name: `carta`

3. **Data Persistence**
   - MongoDB data stored in Docker volume: `carta-mongodb-data`
   - Automatic data persistence between container restarts
   - Backup recommended for production deployments

### SSL/TLS Security

The system implements secure communication:

1. **Certificate Management**
   - Public key: `/etc/carta/carta_public.pem`
   - Private key: `/etc/carta/carta_private.pem`
   - Keys mounted as read-only in container
   - 2048-bit RSA key pair

2. **Security Best Practices**
   - Private key permissions: 600 (user read/write only)
   - Public key permissions: 644 (user read/write, group/others read)
   - Keys stored outside container for better security
   - Regular key rotation recommended

### Directory Structure and Permissions

Detailed explanation of the system's directory structure:

1. **System Directories**
   ```
   /etc/carta/                    # System configuration
   ├── config.json               # Main configuration file
   ├── carta_public.pem         # SSL public key
   └── carta_private.pem        # SSL private key
   ```

2. **User Directories**
   ```
   /home/carta/                  # Carta user home
   ├── carta-controller-new/    # Application directory
   │   ├── config/             # Application config
   │   ├── data/              # Application data
   │   └── logs/             # Application logs
   ├── .carta/                # User-specific data
   │   └── log/             # User logs
   └── mongodb/              # MongoDB data
       └── data/            # Database files
   ```

3. **Permission Structure**
   - System directories: 755 (drwxr-xr-x)
   - Configuration files: 644 (-rw-r--r--)
   - Private keys: 600 (-rw-------)
   - Log directories: 755 (drwxr-xr-x)
   - Data directories: 755 (drwxr-xr-x)

### Process Management

Detailed explanation of how CARTA processes are managed:

1. **Backend Process Control**
   - Process management through Node.js child processes
   - Automatic process cleanup on container shutdown
   - Process isolation between users
   - Resource limits per user

2. **Startup Sequence**
   ```bash
   # 1. Start MongoDB
   /home/carta/start_mongodb.sh
   
   # 2. Wait for MongoDB to be ready
   sleep 5
   
   # 3. Start CARTA Controller
   cd /home/carta/carta-controller-new
   npm start -- --config /etc/carta/config.json
   ```

3. **Health Monitoring**
   - Regular health checks every 30 seconds
   - Checks MongoDB connectivity
   - Verifies CARTA backend status
   - Monitors system resources

### Logging System

Comprehensive logging implementation:

1. **Log Locations**
   - System logs: `/home/carta/carta-controller-new/logs/`
   - User logs: `/home/<username>/.carta/log/`
   - MongoDB logs: `/home/carta/mongodb/mongodb.log`

2. **Log Rotation**
   - Daily log rotation
   - 7-day retention period
   - Compression of old logs
   - Automatic cleanup

3. **Log Levels**
   - ERROR: System errors and failures
   - WARN: Warning conditions
   - INFO: General information
   - DEBUG: Detailed debugging information

### Network Configuration

Detailed network setup:

1. **Port Usage**
   - 3002: CARTA backend communication
   - 3003: Web interface
   - 3004: WebSocket connections
   - 27018: MongoDB (mapped from 27017)

2. **Network Security**
   - All external connections use SSL/TLS
   - Internal MongoDB only accessible locally
   - WebSocket connections authenticated
   - Rate limiting on API endpoints

### Backup and Recovery

System backup procedures:

1. **Data Backup**
   - MongoDB data: `carta-mongodb-data` volume
   - User data: `carta-data` volume
   - Configuration files: Host system
   - SSL certificates: Host system

2. **Recovery Procedures**
   - Database restore from MongoDB dumps
   - Configuration restore from backups
   - User data recovery from volume backups
   - Certificate replacement if compromised

### Performance Considerations

System performance optimization:

1. **Resource Allocation**
   - MongoDB memory limits
   - Node.js process limits
   - User process quotas
   - Disk space monitoring

2. **Caching Strategy**
   - MongoDB query caching
   - Static file caching
   - Session data caching
   - Process status caching

### Security Best Practices

Additional security measures:

1. **User Security**
   - Password policies
   - Session timeout
   - Failed login attempts
   - IP-based access control

2. **System Security**
   - Regular security updates
   - Vulnerability scanning
   - Access logging
   - Audit trails

## Setup Instructions

### Prerequisites
- Docker
- MicroK8s (for Kubernetes deployment)

### Building the Docker Image
1. Build the Docker image:
   ```bash
   docker build -t carta-controller .
   ```
2. Tag the image for MicroK8s:
   ```bash
   docker tag carta-controller localhost:32000/carta-controller:latest
   ```
3. Push the image to MicroK8s:
   ```bash
   docker push localhost:32000/carta-controller:latest
   ```

### Deploying on MicroK8s
1. Apply the Kubernetes manifests:
   ```bash
   kubectl apply -f kubernetes/namespace.yaml
   kubectl apply -f kubernetes/pvc.yaml
   kubectl apply -f kubernetes/mongodb.yaml
   kubectl apply -f kubernetes/deployment.yaml
   kubectl apply -f kubernetes/service.yaml
   ```
2. Expose the carta-controller service:
   - The service is configured as a NodePort. To access it from your local browser, run:
     ```bash
     kubectl get svc carta-controller -n carta
     ```
   - Use the URL: http://localhost:<NodePort> (e.g., http://localhost:31992)

## Additional Information
- The deployment uses PersistentVolumeClaims for MongoDB data, user data, and test files.
- The service is exposed as a NodePort to allow local browser access.
