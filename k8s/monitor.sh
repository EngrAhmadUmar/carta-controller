#!/bin/bash

# CARTA System Monitoring Script
# This script provides real-time monitoring of the CARTA system

set -e

NAMESPACE="carta"
REFRESH_INTERVAL=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "OK")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Function to check if namespace exists
check_namespace() {
    if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        print_status "OK" "Namespace '$NAMESPACE' exists"
        return 0
    else
        print_status "ERROR" "Namespace '$NAMESPACE' not found"
        return 1
    fi
}

# Function to check deployment status
check_deployments() {
    echo ""
    print_status "INFO" "Checking deployments..."
    
    local deployments=("carta-controller" "carta-dashboard" "carta-db")
    local all_ok=true
    
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment $deployment -n $NAMESPACE >/dev/null 2>&1; then
            local ready=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.replicas}')
            
            if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
                print_status "OK" "Deployment '$deployment': $ready/$desired ready"
            else
                print_status "WARNING" "Deployment '$deployment': $ready/$desired ready"
                all_ok=false
            fi
        else
            print_status "ERROR" "Deployment '$deployment' not found"
            all_ok=false
        fi
    done
    
    return $([ "$all_ok" = true ] && echo 0 || echo 1)
}

# Function to check services
check_services() {
    echo ""
    print_status "INFO" "Checking services..."
    
    local services=("carta-controller" "carta-dashboard" "carta-db")
    local all_ok=true
    
    for service in "${services[@]}"; do
        if kubectl get service $service -n $NAMESPACE >/dev/null 2>&1; then
            local endpoints=$(kubectl get endpoints $service -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | wc -w)
            if [ "$endpoints" -gt 0 ]; then
                print_status "OK" "Service '$service': $endpoints endpoint(s)"
            else
                print_status "WARNING" "Service '$service': no endpoints"
                all_ok=false
            fi
        else
            print_status "ERROR" "Service '$service' not found"
            all_ok=false
        fi
    done
    
    return $([ "$all_ok" = true ] && echo 0 || echo 1)
}

# Function to check user pods
check_user_pods() {
    echo ""
    print_status "INFO" "Checking user backend pods..."
    
    local user_pods=$(kubectl get pods -n $NAMESPACE -l app=carta-backend --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n $NAMESPACE -l app=carta-backend --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    local pending_pods=$(kubectl get pods -n $NAMESPACE -l app=carta-backend --no-headers 2>/dev/null | grep -c "Pending" || echo 0)
    local failed_pods=$(kubectl get pods -n $NAMESPACE -l app=carta-backend --no-headers 2>/dev/null | grep -c "Failed\|Error" || echo 0)
    
    if [ "$user_pods" -eq 0 ]; then
        print_status "INFO" "No user backend pods found"
    else
        print_status "OK" "User pods: $running_pods running, $pending_pods pending, $failed_pods failed (total: $user_pods)"
        
        if [ "$failed_pods" -gt 0 ]; then
            echo ""
            print_status "WARNING" "Failed pods:"
            kubectl get pods -n $NAMESPACE -l app=carta-backend --no-headers | grep "Failed\|Error" | while read line; do
                echo "  - $line"
            done
        fi
    fi
}

# Function to check database
check_database() {
    echo ""
    print_status "INFO" "Checking database..."
    
    if kubectl get pod -n $NAMESPACE -l app=carta-db --field-selector=status.phase=Running | grep -q carta-db; then
        # Try to connect to database
        if kubectl exec -n $NAMESPACE deployment/carta-db -- pg_isready -U carta -d carta >/dev/null 2>&1; then
            print_status "OK" "Database is ready and accepting connections"
            
            # Check active sessions
            local active_sessions=$(kubectl exec -n $NAMESPACE deployment/carta-db -- psql -U carta -d carta -t -c "SELECT COUNT(*) FROM user_sessions WHERE active = true;" 2>/dev/null | tr -d ' ' || echo "0")
            print_status "INFO" "Active sessions: $active_sessions"
        else
            print_status "WARNING" "Database pod is running but not accepting connections"
        fi
    else
        print_status "ERROR" "Database pod is not running"
    fi
}

# Function to check resource usage
check_resources() {
    echo ""
    print_status "INFO" "Checking resource usage..."
    
    # Check if metrics server is available
    if kubectl top nodes >/dev/null 2>&1; then
        echo "Node resource usage:"
        kubectl top nodes --no-headers | while read line; do
            echo "  $line"
        done
        
        echo ""
        echo "Pod resource usage:"
        kubectl top pods -n $NAMESPACE --no-headers | while read line; do
            echo "  $line"
        done
    else
        print_status "WARNING" "Metrics server not available - resource usage not shown"
    fi
}

# Function to show recent events
show_events() {
    echo ""
    print_status "INFO" "Recent events (last 10):"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' --no-headers | tail -10 | while read line; do
        echo "  $line"
    done
}

# Function to show pod details
show_pod_details() {
    echo ""
    print_status "INFO" "User pod details:"
    kubectl get pods -n $NAMESPACE -l app=carta-backend -o wide --no-headers | while read line; do
        echo "  $line"
    done
}

# Function to show service endpoints
show_endpoints() {
    echo ""
    print_status "INFO" "Service endpoints:"
    kubectl get endpoints -n $NAMESPACE --no-headers | while read line; do
        echo "  $line"
    done
}

# Main monitoring function
monitor_system() {
    clear
    echo "🔍 CARTA System Monitor - $(date)"
    echo "=================================="
    
    # Check namespace
    if ! check_namespace; then
        print_status "ERROR" "Cannot continue without namespace"
        exit 1
    fi
    
    # Check all components
    check_deployments
    check_services
    check_user_pods
    check_database
    
    # Show additional details
    show_pod_details
    show_endpoints
    show_events
    check_resources
    
    echo ""
    echo "🔄 Refreshing in $REFRESH_INTERVAL seconds... (Press Ctrl+C to stop)"
}

# Function to show help
show_help() {
    echo "CARTA System Monitor"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -i, --interval N    Set refresh interval in seconds (default: 10)"
    echo "  -o, --once          Run once and exit"
    echo "  -d, --details       Show detailed information"
    echo ""
    echo "Examples:"
    echo "  $0                  # Monitor continuously with 10s refresh"
    echo "  $0 -i 5            # Monitor with 5s refresh"
    echo "  $0 -o              # Run once and exit"
}

# Parse command line arguments
ONCE=false
DETAILS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -o|--once)
            ONCE=true
            shift
            ;;
        -d|--details)
            DETAILS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
if [ "$ONCE" = true ]; then
    monitor_system
else
    # Continuous monitoring
    trap 'echo ""; print_status "INFO" "Monitoring stopped"; exit 0' INT
    
    while true; do
        monitor_system
        sleep $REFRESH_INTERVAL
    done
fi 