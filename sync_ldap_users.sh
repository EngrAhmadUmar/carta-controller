#!/bin/bash

# Function to create local user if it doesn't exist
create_local_user() {
    local username=$1
    local uid=$2
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Creating local user $username with UID $uid"
        useradd -u "$uid" -s /bin/bash "$username"
        # Create home directory
        mkdir -p "/home/$username"
        chown "$username:$username" "/home/$username"
    else
        echo "User $username already exists"
    fi
}

# Get all users from LDAP
echo "Querying LDAP for users..."
ldapsearch -x -D "cn=admin,dc=nodomain" -w admin -b "ou=users,dc=nodomain" "objectClass=inetOrgPerson" | while read -r line; do
    if [[ $line =~ ^uid: ]]; then
        username=$(echo "$line" | cut -d' ' -f2)
        # Get UID from LDAP
        uid=$(ldapsearch -x -D "cn=admin,dc=nodomain" -w admin -b "ou=users,dc=nodomain" "uid=$username" uidNumber | grep "uidNumber:" | cut -d' ' -f2)
        if [ -n "$uid" ]; then
            create_local_user "$username" "$uid"
        fi
    fi
done

echo "User synchronization complete" 