#!/bin/bash
set -e

echo "Ensuring MongoDB log file permissions..."
sudo mkdir -p /var/log/mongodb
sudo touch /var/log/mongodb/mongodb.log
sudo chown mongodb:mongodb /var/log/mongodb/mongodb.log
sudo chmod 644 /var/log/mongodb/mongodb.log

echo "Ensuring MongoDB data directory permissions..."
sudo mkdir -p /var/lib/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb

echo "Starting MongoDB..."
sudo -u mongodb mongod --dbpath /var/lib/mongodb --logpath /var/log/mongodb/mongodb.log --fork

echo "Waiting for MongoDB to start..."
for i in {1..30}; do
    if mongosh --eval "db.adminCommand(\"ping\")" > /dev/null 2>&1; then
        echo "MongoDB started successfully"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "MongoDB failed to start. Check logs:"
        cat /var/log/mongodb/mongodb.log
        exit 1
    fi
    sleep 1
done

echo "Creating MongoDB user..."
mongosh --eval "db = db.getSiblingDB(\"admin\"); if (!db.getUser(\"carta\")) { db.createUser({user: \"carta\", pwd: \"carta\", roles: [{role: \"root\", db: \"admin\"}]}) }"

echo "Stopping MongoDB to enable authentication..."
sudo pkill mongod || true
sleep 2

echo "Updating MongoDB configuration to enable authentication..."
sudo bash -c "cat > /etc/mongod.conf << EOL
systemLog:
  destination: file
  path: /var/log/mongodb/mongodb.log
  logAppend: true
storage:
  dbPath: /var/lib/mongodb
net:
  bindIp: 0.0.0.0
  port: 27017
security:
  authorization: enabled
EOL"

echo "Starting MongoDB with authentication enabled..."
sudo -u mongodb mongod --config /etc/mongod.conf --fork

echo "Waiting for MongoDB to start with authentication..."
for i in {1..30}; do
    if mongosh "mongodb://carta:carta@localhost:27017/admin" --eval "db.adminCommand(\"ping\")" > /dev/null 2>&1; then
        echo "MongoDB started successfully with authentication"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "MongoDB failed to start with authentication"
        exit 1
    fi
    sleep 1
done

# Create required directories for users
echo "Setting up directories for user: carta"
sudo mkdir -p /home/carta/carta-controller-new/data
sudo mkdir -p /home/carta/carta-controller-new/logs
sudo chown -R carta:carta /home/carta/carta-controller-new

# Make sure we have a home directory for the carta user with correct permissions
echo "Checking home directory for carta user"
if [ ! -d "/home/carta" ]; then
    echo "Creating home directory for carta user"
    sudo mkdir -p /home/carta
fi
sudo chown -R carta:carta /home/carta
sudo chmod 755 /home/carta

# Check if the config.json exists
if [ ! -f "/home/carta/carta-controller-new/config/config.json" ]; then
    echo "ERROR: Configuration file /home/carta/carta-controller-new/config/config.json not found!"
    exit 1
fi

# Check if the carta_backend binary exists and is executable
if [ ! -x "/home/carta/carta-controller-new/carta_backend" ]; then
    echo "WARNING: carta_backend not found or not executable!"
    echo "Creating a dummy carta_backend for testing..."
    echo '#!/bin/bash
echo "This is a dummy carta_backend for testing"
echo "Args: $@"
sleep infinity' | sudo tee /home/carta/carta-controller-new/carta_backend
    sudo chmod +x /home/carta/carta-controller-new/carta_backend
fi

echo "Starting application..."
cd /home/carta/carta-controller-new && npm start 

# Start MongoDB
/home/carta/start_mongodb.sh &
sleep 5

# Set up sample files directory
SAMPLE_FILES_PATH=${CARTA_SAMPLE_FILES_PATH:-"/home/carta/carta-controller-new/data"}
if [ ! -d "$SAMPLE_FILES_PATH" ]; then
    echo "Creating sample files directory at $SAMPLE_FILES_PATH"
    mkdir -p "$SAMPLE_FILES_PATH"
fi

# Ensure proper permissions
chown -R carta:carta "$SAMPLE_FILES_PATH"
chmod -R 755 "$SAMPLE_FILES_PATH"

# Start CARTA Controller
cd /home/carta/carta-controller-new
npm start -- --config /etc/carta/config.json 