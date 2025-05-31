#!/bin/bash

# Create namespace
echo "Creating namespace..."
microk8s kubectl apply -f namespace.yaml

# Create secrets
echo "Creating secrets..."
microk8s kubectl create secret generic carta-ssl \
  --from-file=carta_public.pem=../config/carta_public.pem \
  --from-file=carta_private.pem=../config/carta_private.pem \
  -n carta

# Create ConfigMap
echo "Creating ConfigMap..."
microk8s kubectl apply -f configmap.yaml

# Create PVCs
echo "Creating PVCs..."
microk8s kubectl apply -f pvc.yaml

# Deploy MongoDB
echo "Deploying MongoDB..."
microk8s kubectl apply -f mongodb.yaml

# Wait for MongoDB to be ready
echo "Waiting for MongoDB to be ready..."
microk8s kubectl wait --for=condition=available --timeout=300s deployment/mongodb -n carta

# Deploy CARTA Controller
echo "Deploying CARTA Controller..."
microk8s kubectl apply -f deployment.yaml

# Create Service
echo "Creating Service..."
microk8s kubectl apply -f service.yaml

# Create Ingress
echo "Creating Ingress..."
microk8s kubectl apply -f ingress.yaml

echo "Deployment complete! Checking status..."
microk8s kubectl get all -n carta 