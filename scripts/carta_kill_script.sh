#!/bin/bash

# Kill any existing carta_backend processes for the user
pkill -f carta_backend

# Kill any existing node processes for the user
pkill -f node

# Kill any existing ts-node processes for the user
pkill -f ts-node

exit 0
