# CARTA Kubernetes Deployment

This directory contains the Kubernetes deployment configuration for the CARTA (Continuum Analysis and Reduction Tool for Astronomy) system with automatic pod-based backend spawning.

## 🏗️ Architecture Overview

The system consists of several components:

- **Controller**: Manages user sessions and spawns backend pods on demand
- **Dashboard**: Web interface for user authentication and session management
- **Backend Pods**: Individual CARTA backend instances for each user
- **Database**: PostgreSQL for user management and session tracking
- **Storage**: Persistent volumes for user data and logs

## 📁 File Structure

```
k8s/
├── README.md                    # This file
├── deploy.sh                    # Main deployment script
├── undeploy.sh                  # Cleanup script
├── test-pod-creation.sh         # Test script for pod creation
├── namespace.yaml               # Kubernetes namespace
├── configmap.yaml               # Backend configuration
├── secrets.yaml                 # Database credentials
├── pvc.yaml                     # Persistent volume claims
├── database.yaml                # PostgreSQL deployment
├── controller.yaml              # Controller deployment
├── dashboard.yaml               # Dashboard deployment
├── service.yaml                 # Service definitions
└── ingress.yaml                 # Ingress configuration
```

## 🚀 Quick Start

### Prerequisites

1. **Kubernetes Cluster**: Minikube, Docker Desktop, or any Kubernetes cluster
2. **kubectl**: Configured to access your cluster
3. **CARTA Images**: Backend and dashboard images available in your registry

### Deployment

1. **Deploy the application**:
   ```bash
   ./k8s/deploy.sh
   ```

2. **Access the dashboard**:
   ```
   http://localhost:30004/dashboard
   ```

3. **Test pod creation**:
   ```bash
   ./k8s/test-pod-creation.sh
   ```

### Cleanup

To remove all resources:
```bash
./k8s/undeploy.sh
```

## 🔧 Configuration

### Environment Variables

The controller can be configured using these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `carta-db` | Database hostname |
| `DB_PORT` | `5432` | Database port |
| `DB_NAME` | `carta` | Database name |
| `DB_USER` | `carta` | Database username |
| `DB_PASSWORD` | `carta123` | Database password |
| `BACKEND_IMAGE` | `localhost:32000/carta-backend:latest` | Backend container image |
| `POD_NAMESPACE` | `carta` | Kubernetes namespace |
| `POD_CPU_REQUEST` | `250m` | CPU request per pod |
| `POD_CPU_LIMIT` | `1000m` | CPU limit per pod |
| `POD_MEMORY_REQUEST` | `256Mi` | Memory request per pod |
| `POD_MEMORY_LIMIT` | `1Gi` | Memory limit per pod |
| `POD_TIMEOUT` | `300` | Pod timeout in seconds |

### Backend Configuration

The backend pods are configured via a ConfigMap (`carta-backend-config`) that contains:

- CARTA configuration files
- Environment-specific settings
- Security policies

## 🎯 Pod Creation System

### How It Works

1. **User Authentication**: User logs in through the dashboard
2. **Session Creation**: Controller creates a database session record
3. **Pod Spawning**: Controller spawns a dedicated backend pod for the user
4. **Pod Management**: Controller monitors pod health and cleans up inactive pods

### Pod Lifecycle

```
User Login → Session Created → Pod Spawned → User Works → Pod Cleanup
```

### Pod Configuration

Each user pod includes:

- **Security**: Non-root user, read-only filesystem where possible
- **Resources**: Configurable CPU and memory limits
- **Volumes**: Persistent storage for user data and logs
- **Networking**: Internal service discovery
- **Environment**: User-specific environment variables

## 📊 Monitoring

### Check Pod Status

```bash
# List all user pods
kubectl get pods -n carta -l app=carta-backend

# Check pod logs
kubectl logs -n carta <pod-name>

# Describe pod details
kubectl describe pod -n carta <pod-name>
```

### Check Controller Logs

```bash
# Controller logs
kubectl logs -n carta deployment/carta-controller

# Follow logs in real-time
kubectl logs -n carta deployment/carta-controller -f
```

### Database Queries

```bash
# Connect to database
kubectl exec -n carta deployment/carta-db -- psql -U carta -d carta

# Check active sessions
SELECT * FROM user_sessions WHERE active = true;
```

## 🔒 Security

### Pod Security

- **Non-root execution**: All containers run as user 1000
- **Read-only filesystem**: Where possible, filesystems are read-only
- **No privilege escalation**: Containers cannot escalate privileges
- **Resource limits**: CPU and memory limits prevent resource exhaustion

### Network Security

- **Internal communication**: Pods communicate via internal Kubernetes networking
- **Service isolation**: Each component has its own service
- **Ingress control**: External access only through dashboard

### Data Security

- **Persistent storage**: User data is stored in persistent volumes
- **Database encryption**: PostgreSQL with encrypted connections
- **Session management**: Secure session tokens and cleanup

## 🐛 Troubleshooting

### Common Issues

1. **Pod Creation Fails**
   ```bash
   # Check controller logs
   kubectl logs -n carta deployment/carta-controller
   
   # Check pod events
   kubectl describe pod -n carta <pod-name>
   ```

2. **Database Connection Issues**
   ```bash
   # Check database status
   kubectl get pods -n carta -l app=carta-db
   
   # Check database logs
   kubectl logs -n carta deployment/carta-db
   ```

3. **Image Pull Issues**
   ```bash
   # Check if images exist
   docker images | grep carta
   
   # Check image pull policy
   kubectl describe pod -n carta <pod-name>
   ```

### Debug Commands

```bash
# Get all resources in namespace
kubectl get all -n carta

# Check events
kubectl get events -n carta --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n carta

# Check service endpoints
kubectl get endpoints -n carta
```

## 📈 Scaling

### Horizontal Pod Autoscaling

The system can be scaled horizontally by:

1. **Multiple Controller Instances**: Deploy multiple controller replicas
2. **Load Balancing**: Use Kubernetes services for load distribution
3. **Resource Optimization**: Adjust CPU/memory requests and limits

### Performance Tuning

- **Pod Resources**: Adjust CPU and memory limits based on workload
- **Database Tuning**: Optimize PostgreSQL configuration
- **Storage Performance**: Use high-performance storage classes
- **Network Optimization**: Configure appropriate network policies

## 🔄 Updates and Maintenance

### Rolling Updates

```bash
# Update controller image
kubectl set image deployment/carta-controller carta-controller=localhost:32000/carta-controller:new-version -n carta

# Update backend image
kubectl set image deployment/carta-controller carta-controller=localhost:32000/carta-backend:new-version -n carta
```

### Backup and Restore

```bash
# Backup database
kubectl exec -n carta deployment/carta-db -- pg_dump -U carta carta > backup.sql

# Restore database
kubectl exec -i -n carta deployment/carta-db -- psql -U carta carta < backup.sql
```

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [CARTA Documentation](https://carta.readthedocs.io/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## 🤝 Contributing

When contributing to this deployment:

1. Test changes in a development environment
2. Update documentation for any configuration changes
3. Ensure backward compatibility
4. Follow Kubernetes best practices
5. Test pod creation and cleanup workflows 