#!/bin/bash

# Create namespace if it doesn't exist
microk8s kubectl create namespace carta --dry-run=client -o yaml | microk8s kubectl apply -f -

# Create ConfigMap from docker config
microk8s kubectl create configmap carta-config --from-file=config/docker.config.json -n carta --dry-run=client -o yaml | microk8s kubectl apply -f -

# Create Secret for SSL keys
microk8s kubectl create secret generic carta-ssl --from-file=carta_public.pem=config/carta_public.pem --from-file=carta_private.pem=config/carta_private.pem -n carta --dry-run=client -o yaml | microk8s kubectl apply -f -

# Apply PVCs
microk8s kubectl apply -f k8s/carta-pvc.yaml

# Tag and push the image to local registry
docker tag carta-controller:1.0.0 localhost:32000/carta-controller:1.0.0
docker push localhost:32000/carta-controller:1.0.0

# Deploy the application
microk8s kubectl apply -f k8s/carta-controller-deployment.yaml
microk8s kubectl apply -f k8s/carta-controller-service.yaml

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
microk8s kubectl rollout status deployment/carta-controller -n carta

# Get service access information
echo "Service access information:"
microk8s kubectl get svc carta-controller -n carta 