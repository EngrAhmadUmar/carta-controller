#!/bin/bash

# CARTA Controller Deployment Script
# This script deploys the CARTA controller with pod-based backend spawning

set -e

NAMESPACE="carta"
CONTROLLER_IMAGE="localhost:32000/carta-controller:1.0.0"
BACKEND_IMAGE="localhost:32000/carta-backend:latest"

echo "🚀 Deploying CARTA Controller with Pod-based Backend Spawning..."

# Check if namespace exists, create if not
if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    echo "📦 Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE
else
    echo "✅ Namespace $NAMESPACE already exists"
fi

# Apply RBAC resources first
echo "🔐 Applying RBAC resources..."
kubectl apply -f k8s/carta-controller-deployment.yaml --namespace=$NAMESPACE

# Wait a moment for RBAC to propagate
echo "⏳ Waiting for RBAC resources to propagate..."
sleep 5

# Apply the main deployment
echo "📋 Applying main deployment..."
kubectl apply -f k8s/carta-controller-deployment.yaml --namespace=$NAMESPACE

# Apply backend configuration
echo "⚙️  Applying backend configuration..."
kubectl apply -f k8s/carta-backend-deployment.yaml --namespace=$NAMESPACE

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/carta-controller -n $NAMESPACE

# Check pod status
echo "🔍 Checking pod status..."
kubectl get pods -n $NAMESPACE -l app=carta-controller

# Get service information
echo "🌐 Service information:"
kubectl get svc -n $NAMESPACE

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "📊 To monitor the deployment:"
echo "   kubectl logs -f deployment/carta-controller -n $NAMESPACE -c carta-controller"
echo ""
echo "🌐 Access the application:"
echo "   http://localhost:30004/dashboard"
echo ""
echo "🔧 To test user pod creation:"
echo "   1. Access the dashboard and login with a test user"
echo "   2. Check if user pods are created:"
echo "      kubectl get pods -n $NAMESPACE -l app=carta-backend"
echo ""
echo "🧹 To clean up:"
echo "   kubectl delete namespace $NAMESPACE" 