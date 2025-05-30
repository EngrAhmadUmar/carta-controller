# CARTA Controller Local Setup Guide

## System Requirements
- Ubuntu Linux (tested on Ubuntu 22.04 LTS)
- Node.js and npm
- MongoDB
- CARTA Backend installation
- Sudo access for system configuration

## Installation Steps

### 1. Prerequisites Installation

```bash
# Install MongoDB
sudo apt-get update
sudo apt-get install -y mongodb

# Install Node.js and npm (if not already installed)
sudo apt-get install -y nodejs npm

# Install CARTA Backend
# Note: Ensure CARTA backend is installed at /home/mona/CARTA/carta-backend/
```

### 2. CARTA Controller Setup

1. Clone the repository:
```bash
git clone <repository-url> carta-controller-new
cd carta-controller-new
```

2. Install dependencies:
```bash
npm install
```

### 3. Configuration

#### MongoDB Configuration
- MongoDB runs on localhost:27017
- Database name: carta
- No authentication required for local setup

#### PAM Authentication Setup

1. Create RSA key pair:
```bash
# Generate private key
openssl genrsa -out config/carta_private.pem 2048

# Generate public key
openssl rsa -in config/carta_private.pem -pubout -out config/carta_public.pem
```

2. Set proper permissions:
```bash
chmod 600 config/carta_private.pem
chmod 644 config/carta_public.pem
```

#### System Permissions

1. Create sudoers rule for backend process:
```bash
# Add to /etc/sudoers.d/carta
mona ALL=(ALL) NOPASSWD: /home/mona/CARTA/carta-backend/build/carta_backend
mona ALL=(ALL) NOPASSWD: /home/mona/carta-controller-new/scripts/carta_kill_script.sh
```

2. Set proper permissions for data directory:
```bash
sudo mkdir -p /home/mona/carta-controller-new/data
sudo chown -R mona:mona /home/mona/carta-controller-new/data
```

### 4. Configuration Files

#### config/config.json
```json
{
    "authProviders": {
        "pam": {
            "publicKeyLocation": "./config/carta_public.pem",
            "privateKeyLocation": "./config/carta_private.pem",
            "issuer": "carta.local",
            "keyAlgorithm": "RS256",
            "accessTokenAge": "15m",
            "refreshTokenAge": "1w"
        }
    },
    "database": {
        "uri": "mongodb://localhost:27017",
        "databaseName": "carta"
    },
    "serverPort": 3003,
    "serverInterface": "localhost",
    "processCommand": "/home/mona/CARTA/carta-backend/build/carta_backend",
    "killCommand": "/home/mona/carta-controller-new/scripts/carta_kill_script.sh",
    "rootFolderTemplate": "/home/mona/carta-controller-new/data/{username}",
    "baseFolderTemplate": "/home/mona/carta-controller-new/data/{username}",
    "logFileTemplate": "/home/mona/carta-controller-new/logs/{username}_{pid}_{datetime}.log",
    "additionalArgs": ["--no_frontend", "--no_database"],
    "preserveEnv": true
}
```

### 5. Directory Structure

```
carta-controller-new/
├── config/
│   ├── carta_private.pem
│   ├── carta_public.pem
│   └── config.json
├── data/
│   └── {username}/  # User data directory
├── logs/
├── public/
├── scripts/
│   └── carta_kill_script.sh
└── src/
```

### 6. Authentication Flow

1. User logs in through the web interface
2. PAM authentication verifies credentials against system users
3. JWT tokens are generated using RSA keys:
   - Access token: 15 minutes validity
   - Refresh token: 1 week validity
4. Tokens are used for subsequent API requests

### 7. Running the Application

1. Start MongoDB:
```bash
sudo systemctl start mongodb
```

2. Start CARTA Controller:
```bash
npm start
```

3. Access the application at: http://localhost:3003

### 8. Troubleshooting

#### Common Issues and Solutions

1. PAM Authentication Failures:
   - Verify user exists in system
   - Check PAM configuration
   - Ensure proper permissions on RSA keys

2. Backend Process Issues:
   - Verify sudoers configuration
   - Check backend binary permissions
   - Ensure CARTA backend is properly installed

3. File Access Issues:
   - Verify directory permissions
   - Check user ownership of data directories
   - Ensure proper SELinux/AppArmor settings

### 9. Security Considerations

1. RSA Keys:
   - Keep private key secure (600 permissions)
   - Regular key rotation recommended
   - Backup keys securely

2. System Users:
   - Only create necessary system users
   - Use strong passwords
   - Regular security audits

3. File Permissions:
   - Follow principle of least privilege
   - Regular permission audits
   - Secure log file handling

### 10. Backup and Recovery

1. Critical Files to Backup:
   - RSA keys
   - Configuration files
   - User data
   - Logs

2. Recovery Process:
   - Restore configuration files
   - Verify permissions
   - Test authentication
   - Validate backend connectivity

## Maintenance

### Regular Tasks
1. Monitor log files
2. Check disk space
3. Verify MongoDB status
4. Review system user accounts
5. Update RSA keys periodically

### Updates
1. Pull latest code changes
2. Update dependencies
3. Test in staging environment
4. Deploy to production
5. Verify functionality

## Support

For issues and support:
1. Check logs in `/home/mona/carta-controller-new/logs/`
2. Review MongoDB logs
3. Check system logs
4. Contact system administrator 