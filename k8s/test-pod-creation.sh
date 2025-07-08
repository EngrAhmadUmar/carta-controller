#!/bin/bash

# Test script for CARTA Pod Creation
# This script tests the pod-based backend spawning functionality

set -e

NAMESPACE="carta"
TEST_USER="testuser1"

echo "🧪 Testing CARTA Pod Creation..."

# Check if the controller is running
echo "🔍 Checking if controller is running..."
if ! kubectl get pods -n $NAMESPACE -l app=carta-controller --field-selector=status.phase=Running | grep -q carta-controller; then
    echo "❌ Controller is not running. Please deploy first."
    exit 1
fi

echo "✅ Controller is running"

# Check if we can create a test pod manually
echo "🔧 Testing manual pod creation..."

# Create a test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: carta-backend-test-manual
  namespace: $NAMESPACE
  labels:
    app: carta-backend
    user: test-manual
    component: user-backend
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    supplementalGroups: [1000]
    fsGroup: 1000
  containers:
  - name: carta-backend
    image: localhost:32000/carta-backend:latest
    imagePullPolicy: Always
    ports:
    - containerPort: 3002
      name: backend
    command: ["python3", "/usr/local/bin/carta_backend"]
    args:
    - --no_frontend
    - --no_database
    - --port
    - "3002"
    - --top_level_folder
    - /data
    - --controller_deployment
    - /data
    env:
    - name: CARTA_AUTH_TOKEN
      value: "test-auth-token"
    - name: USER
      value: "test-manual"
    volumeMounts:
    - name: data-volume
      mountPath: /data
    - name: logs-volume
      mountPath: /home/carta/.carta/log
    - name: config-volume
      mountPath: /etc/carta
      readOnly: true
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "1Gi"
        cpu: "1000m"
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      runAsNonRoot: true
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: carta-data-pvc
  - name: logs-volume
    persistentVolumeClaim:
      claimName: carta-logs-pvc
  - name: config-volume
    configMap:
      name: carta-backend-config
EOF

# Wait for the test pod to be ready
echo "⏳ Waiting for test pod to be ready..."
if kubectl wait --for=condition=ready pod/carta-backend-test-manual -n $NAMESPACE --timeout=60s; then
    echo "✅ Test pod created successfully"
    
    # Check pod status
    echo "📊 Pod status:"
    kubectl get pod carta-backend-test-manual -n $NAMESPACE
    
    # Get pod logs
    echo "📋 Pod logs:"
    kubectl logs carta-backend-test-manual -n $NAMESPACE --tail=10
    
    # Clean up test pod
    echo "🧹 Cleaning up test pod..."
    kubectl delete pod carta-backend-test-manual -n $NAMESPACE
    
    echo "✅ Manual pod creation test passed!"
else
    echo "❌ Test pod failed to become ready"
    echo "📋 Pod events:"
    kubectl describe pod carta-backend-test-manual -n $NAMESPACE
    echo "📋 Pod logs:"
    kubectl logs carta-backend-test-manual -n $NAMESPACE --tail=20
    exit 1
fi

echo ""
echo "🎉 All tests passed!"
echo ""
echo "📝 Next steps:"
echo "   1. Deploy the application: ./k8s/deploy.sh"
echo "   2. Access the dashboard: http://localhost:30004/dashboard"
echo "   3. Login with a test user to trigger automatic pod creation"
echo "   4. Monitor user pods: kubectl get pods -n $NAMESPACE -l app=carta-backend" 