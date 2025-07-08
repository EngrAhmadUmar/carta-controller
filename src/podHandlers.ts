import express, {Request, Response, NextFunction} from 'express';
import httpProxy from "http-proxy";
import * as url from "url";
import * as querystring from "querystring";
import {v4} from "uuid";
import {IncomingMessage} from "http";
import {delay, noCache, verboseError} from "./util";
import {authGuard, getUser, verifyToken} from "./auth";
import {AuthenticatedRequest} from "./types";
import { execFile } from 'child_process';
import { env} from "process";
import chalk from "chalk";

import { KubeConfig, CoreV1Api, V1Pod, V1Service, V1ObjectMeta, V1PodSpec, V1Container, V1VolumeMount, V1Volume, V1EnvVar, V1ResourceRequirements, V1SecurityContext } from '@kubernetes/client-node';

// Kubernetes configuration
const kubNamespace : string = env.K8S_NAMESPACE ? env.K8S_NAMESPACE : 'carta';
const kubBackendImg : string = env.K8S_BACKEND_IMG ? env.K8S_BACKEND_IMG : 'localhost:32000/carta-backend:latest';
const kubImagesPvc : string = env.K8S_IMAGES_PVC ? env.K8S_IMAGES_PVC : 'carta-data-pvc';
const kubLogsPvc : string = env.K8S_LOGS_PVC ? env.K8S_LOGS_PVC : 'carta-logs-pvc';

if (env.K8S_NAMESPACE) {
    console.log(chalk.blue(`Read k8s namespace "${kubNamespace}" from environment`))
}
if (env.K8S_BACKEND_IMG) {
    console.log(chalk.blue(`Read k8s backend image "${kubBackendImg}" from environment`))
}
if (env.K8S_IMAGES_PVC) {
    console.log(chalk.blue(`Read k8s image PVC "${kubImagesPvc}" from environment`))
}

const kc = new KubeConfig();
kc.loadFromCluster();
const k8sApi = kc.makeApiClient(CoreV1Api);

// Pod management tracking
const podMap = new Map<string, { podName: string; serviceName: string; authToken: string; ready: boolean }>();

interface UserPodInfo {
    podName: string;
    serviceName: string;
    authToken: string;
    ready: boolean;
}

export function getUserIdInfo (username: string): Promise<{uid: number, gid: number, groups: number[]}> {
    return new Promise((resolve, reject) => {
        execFile('/usr/bin/id', [username], (error, stdout, stderr) => {
            if (error) {
                // Fallback to default values if user doesn't exist in system
                console.log(chalk.yellow(`User ${username} not found in system, using default values`));
                resolve({ uid: 1000, gid: 1000, groups: [1000] });
            } else {
                const output = stdout.trim();
                const uid_output = output?.match(/uid=(\d+)/);
                const gid_output = output?.match(/gid=(\d+)/);
                const groups_output =  output.match(/groups=(.*)/);

                if (Array.isArray(uid_output) && uid_output[1] !== undefined &&
                    Array.isArray(gid_output) && gid_output[1] !== undefined &&
                    Array.isArray(groups_output) && groups_output[1] !== undefined) {
                        const uid = parseInt(uid_output[1]);
                        const gid = parseInt(gid_output[1]);
                        const groups = groups_output[1].split(',').map(group => parseInt(group.split('(')[0]));
                        if (isNaN(uid) || isNaN(gid) || groups.map(x => isNaN(x)).includes(true)) {
                            reject(new Error("Invalid id info"))
                        } else {
                            resolve({ uid, gid, groups });
                        }
                } else {
                    reject(new Error("Invalid id info"));
                } 
            }
        });
    });
}

// Create Kubernetes service for user pod
async function createUserService(username: string): Promise<void> {
    const serviceName = `carta-backend-${username}-svc`;
    
    const service: V1Service = {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
            name: serviceName,
            namespace: kubNamespace,
            labels: {
                app: 'carta-backend',
                user: username,
                component: 'user-backend'
            }
        } as V1ObjectMeta,
        spec: {
            selector: {
                app: 'carta-backend',
                user: username
            },
            ports: [{
                port: 3002,
                targetPort: 3002,
                protocol: 'TCP'
            }],
            type: 'ClusterIP'
        }
    };

    try {
        console.log(chalk.blue(`Creating service ${serviceName} for user ${username}`));
        await k8sApi.createNamespacedService(kubNamespace, service);
        console.log(chalk.green(`Service ${serviceName} created successfully`));
    } catch (error) {
        if (error.response?.statusCode === 409) {
            console.log(chalk.yellow(`Service ${serviceName} already exists`));
        } else {
            throw error;
        }
    }
}

// Delete Kubernetes service for user pod
async function deleteUserService(username: string): Promise<void> {
    const serviceName = `carta-backend-${username}-svc`;
    
    try {
        console.log(chalk.blue(`Deleting service ${serviceName}`));
        await k8sApi.deleteNamespacedService(serviceName, kubNamespace);
        console.log(chalk.green(`Service ${serviceName} deleted successfully`));
    } catch (error) {
        if (error.response?.statusCode === 404) {
            console.log(chalk.yellow(`Service ${serviceName} not found`));
        } else {
            console.error(chalk.red(`Error deleting service ${serviceName}:`), error);
        }
    }
}

// Enhanced startServer function
async function startServer(username: string): Promise<UserPodInfo> {
    let userInfo : {uid: number, gid: number, groups: number[]} | undefined;
    const podName = `carta-backend-${username}`;
    const serviceName = `carta-backend-${username}-svc`;
    const authToken = v4();

    try {
        userInfo = await getUserIdInfo(username);
        
        if (!userInfo) {
            throw new Error(`User ${username} info could not be found`);
        }

        // Create pod manifest with enhanced configuration
        const pod: V1Pod = {
            apiVersion: 'v1',
            kind: 'Pod',
            metadata: {
                name: podName,
                namespace: kubNamespace,
                labels: {
                    app: 'carta-backend',
                    user: username,
                    component: 'user-backend'
                }
            } as V1ObjectMeta,
            spec: {
                restartPolicy: 'Never',
                securityContext: {
                    runAsUser: userInfo.uid,
                    runAsGroup: userInfo.gid,
                    supplementalGroups: userInfo.groups,
                    fsGroup: userInfo.gid
                } as V1SecurityContext,
                containers: [{
                    name: 'carta-backend',
                    image: kubBackendImg,
                    imagePullPolicy: 'Always',
                    ports: [{ containerPort: 3002, name: 'backend' }],
                    command: ['/usr/local/bin/carta_backend'],
                    args: [
                        '--no_frontend',
                        '--no_database',
                        '--no_log',
                        '--port', '3002',
                        '--top_level_folder', '/data',
                        '--controller_deployment',
                        '/data'
                    ],
                    env: [
                        {
                            name: 'CARTA_AUTH_TOKEN',
                            value: authToken
                        } as V1EnvVar,
                        {
                            name: 'USER',
                            value: username
                        } as V1EnvVar
                    ],
                    volumeMounts: [
                        {
                            name: 'data-volume',
                            mountPath: '/data'
                        } as V1VolumeMount,
                        {
                            name: 'config-volume',
                            mountPath: '/etc/carta',
                            readOnly: true
                        } as V1VolumeMount
                    ],
                    resources: {
                        requests: {
                            memory: '256Mi',
                            cpu: '250m'
                        },
                        limits: {
                            memory: '1Gi',
                            cpu: '1000m'
                        }
                    } as V1ResourceRequirements,
                    securityContext: {
                        allowPrivilegeEscalation: false,
                        readOnlyRootFilesystem: false,
                        runAsNonRoot: true
                    } as V1SecurityContext
                } as V1Container],
                volumes: [
                    {
                        name: 'data-volume',
                        persistentVolumeClaim: {
                            claimName: kubImagesPvc
                        }
                    } as V1Volume,
                    {
                        name: 'config-volume',
                        configMap: {
                            name: 'carta-config'
                        }
                    } as V1Volume
                ]
            } as V1PodSpec
        };

        // Create the pod
        console.log(chalk.blue(`Creating pod ${podName} for user ${username}`));
        await k8sApi.createNamespacedPod(kubNamespace, pod);
        console.log(chalk.green(`Pod ${podName} created successfully`));

        // Create service for the pod
        await createUserService(username);

        // Wait for pod to be ready
        let ready = false;
        for (let i = 0; i < 60; i++) { // Wait up to 60 seconds
            try {
                const podStatus = await k8sApi.readNamespacedPod(podName, kubNamespace);
                const containerStatuses = podStatus.body.status?.containerStatuses;
                
                // Check if container is ready OR if it's running (for restartPolicy Never pods)
                if (containerStatuses && containerStatuses[0]) {
                    const containerStatus = containerStatuses[0];
                    if (containerStatus.ready || 
                        (containerStatus.state?.running && !containerStatus.state?.terminated && !containerStatus.state?.waiting)) {
                        ready = true;
                        console.log(chalk.green(`Pod ${podName} is ready`));
                        break;
                    }
                }
                
                if (containerStatuses && containerStatuses[0]?.state?.terminated) {
                    const terminatedState = containerStatuses[0].state.terminated;
                    console.error(chalk.red(`Pod ${podName} terminated with exit code ${terminatedState.exitCode}`));
                    console.error(chalk.red(`Reason: ${terminatedState.reason || 'Unknown'}`));
                    console.error(chalk.red(`Message: ${terminatedState.message || 'No message'}`));
                    
                    // Try to get container logs for more details
                    try {
                        const logs = await k8sApi.readNamespacedPodLog(podName, kubNamespace);
                        console.error(chalk.red(`Container logs for ${podName}:`));
                        console.error(logs.body);
                    } catch (logError) {
                        console.error(chalk.red(`Could not retrieve logs for ${podName}:`), logError);
                    }
                    
                    throw new Error(`Pod ${podName} terminated unexpectedly (exit code: ${terminatedState.exitCode}, reason: ${terminatedState.reason})`);
                }
                
                // Check for other failure states
                if (containerStatuses && containerStatuses[0]?.state?.waiting) {
                    const waitingState = containerStatuses[0].state.waiting;
                    console.log(chalk.yellow(`Pod ${podName} waiting: ${waitingState.reason} - ${waitingState.message || 'No message'}`));
                }
                
                await delay(1000);
            } catch (error) {
                if (error.response?.statusCode === 404) {
                    await delay(1000);
                    continue;
                }
                throw error;
            }
        }

        if (!ready) {
            throw new Error(`Pod ${podName} failed to become ready within timeout`);
        }

        // Get pod details and logs for debugging
        try {
            const podDetails = await k8sApi.readNamespacedPod(podName, kubNamespace);
            console.log(chalk.blue(`Pod ${podName} details:`));
            console.log(chalk.blue(`  Phase: ${podDetails.body.status?.phase}`));
            console.log(chalk.blue(`  Pod IP: ${podDetails.body.status?.podIP}`));
            console.log(chalk.blue(`  Host IP: ${podDetails.body.status?.hostIP}`));
            
            const containerStatuses = podDetails.body.status?.containerStatuses;
            if (containerStatuses && containerStatuses[0]) {
                console.log(chalk.blue(`  Container: ${containerStatuses[0].name}`));
                console.log(chalk.blue(`  Image: ${containerStatuses[0].image}`));
                console.log(chalk.blue(`  Ready: ${containerStatuses[0].ready}`));
                console.log(chalk.blue(`  Restart Count: ${containerStatuses[0].restartCount}`));
            }
            
            // Get container logs
            try {
                const logs = await k8sApi.readNamespacedPodLog(podName, kubNamespace);
                console.log(chalk.blue(`Container logs for ${podName}:`));
                console.log(logs.body);
            } catch (logError) {
                console.log(chalk.yellow(`Could not retrieve logs for ${podName}:`), logError);
            }
        } catch (detailError) {
            console.log(chalk.yellow(`Could not get pod details for ${podName}:`), detailError);
        }

        return { podName, serviceName, authToken, ready };

    } catch (error) {
        console.error(chalk.red(`Error creating pod for user ${username}:`), error);
        // Cleanup on failure
        try {
            await deleteUserService(username);
            await k8sApi.deleteNamespacedPod(podName, kubNamespace);
        } catch (cleanupError) {
            console.error(chalk.red(`Error during cleanup for ${username}:`), cleanupError);
        }
        throw error;
    }
}

// Enhanced delete user pod and service
async function deleteUserPod(username: string): Promise<void> {
    const podName = `carta-backend-${username}`;
    
    try {
        // Delete service first
        await deleteUserService(username);
        
        // Delete pod
        console.log(chalk.blue(`Deleting pod ${podName}`));
        await k8sApi.deleteNamespacedPod(podName, kubNamespace, undefined, undefined, 2);
        console.log(chalk.green(`Successfully deleted pod for user ${username}`));
    } catch (error) {
        if (error.response?.statusCode === 404) {
            console.log(chalk.yellow(`Pod ${podName} not found`));
        } else {
            console.error(chalk.red(`Error deleting pod for user ${username}:`), error);
            throw error;
        }
    }
}

// Check if user pod exists and is running
async function checkUserPod(username: string): Promise<boolean> {
    const podName = `carta-backend-${username}`;
    
    try {
        const podStatus = await k8sApi.readNamespacedPod(podName, kubNamespace);
        const containerStatuses = podStatus.body.status?.containerStatuses;
        
        if (containerStatuses && containerStatuses[0]) {
            const containerStatus = containerStatuses[0];
            return !!(containerStatus.ready || 
                     (containerStatus.state?.running && !containerStatus.state?.terminated && !containerStatus.state?.waiting));
        }
        return false;
    } catch (error) {
        if (error.response?.statusCode === 404) {
            return false;
        }
        throw error;
    }
}

// Get user pod info
async function getUserPodInfo(username: string): Promise<UserPodInfo | null> {
    const podName = `carta-backend-${username}`;
    const serviceName = `carta-backend-${username}-svc`;
    
    try {
        const pod = await k8sApi.readNamespacedPod(podName, kubNamespace);
        const containerStatuses = pod.body.status?.containerStatuses;
        
        let ready = false;
        if (containerStatuses && containerStatuses[0]) {
            const containerStatus = containerStatuses[0];
            ready = !!(containerStatus.ready || 
                      (containerStatus.state?.running && !containerStatus.state?.terminated && !containerStatus.state?.waiting));
        }
        
        // Get auth token from pod spec
        const authTokenEnv = pod.body.spec?.containers?.[0]?.env?.find(env => env.name === 'CARTA_AUTH_TOKEN');
        const authToken = authTokenEnv?.value || '';
        
        return { podName, serviceName, authToken, ready };
    } catch (error) {
        if (error.response?.statusCode === 404) {
            return null;
        }
        throw error;
    }
}

async function handleCheckServer(req: AuthenticatedRequest, res: Response) {
    if (!req.username) {
        res.status(403).json({success: false, message: "Invalid username"});
        return;
    }

    try {
        const running = await checkUserPod(req.username);
        res.json({
            success: true,
            running: running
        });
    } catch (error) {
        console.error(chalk.red(`Error checking server status for ${req.username}:`), error);
        res.status(500).json({
            success: false,
            message: "Error checking server status"
        });
    }
}

async function handleLog(req: AuthenticatedRequest, res: Response) {
    if (!req.username) {
        res.status(403).json({success: false, message: "Invalid username"});
        return;
    }

    try {
        const podName = `carta-backend-${req.username}`;
        const podLog = await k8sApi.readNamespacedPodLog(podName, kubNamespace);
        
        // Also get pod status for debugging
        let podStatus: any = null;
        try {
            const pod = await k8sApi.readNamespacedPod(podName, kubNamespace);
            podStatus = {
                phase: pod.body.status?.phase,
                podIP: pod.body.status?.podIP,
                ready: pod.body.status?.containerStatuses?.[0]?.ready,
                restartCount: pod.body.status?.containerStatuses?.[0]?.restartCount
            };
        } catch (statusError) {
            console.log(chalk.yellow(`Could not get pod status for ${podName}:`), statusError);
        }
        
        res.json({
            success: true,
            log: podLog.body,
            podStatus: podStatus
        });
    } catch (error) {
        console.error(chalk.red(`Error getting logs for ${req.username}:`), error);
        res.json({success: false});
    }
}

// Fixed handleStartServer implementation
async function handleStartServer(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    const username = req.username;
    const forceRestart = req.body?.forceRestart;
    
    if (!username) {
        return next({statusCode: 403, message: "Invalid username"});
    }

    try {
        // Check if pod already exists
        const existingPod = await getUserPodInfo(username);
        
        if (existingPod && existingPod.ready) {
            if (forceRestart) {
                // Delete existing pod and create new one
                await deleteUserPod(username);
                await delay(2000); // Wait for cleanup
            } else {
                return res.json({success: true, existing: true});
            }
        }

        // Create new pod
        const podInfo = await startServer(username);
        podMap.set(username, podInfo);
        
        res.json({success: true});
    } catch (error) {
        console.error(chalk.red(`Error starting server for ${username}:`), error);
        return next({statusCode: 500, message: `Error starting server for ${username}`});
    }
}

async function handleStopServer(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    if (!req.username) {
        return next({statusCode: 403, message: "Invalid username"});
    }

    try {
        await deleteUserPod(req.username);
        podMap.delete(req.username);
        res.json({success: true});
    } catch (error) {
        console.error(chalk.red(`Error stopping server for ${req.username}:`), error);
        return next({statusCode: 500, message: `Error stopping server for ${req.username}`});
    }
}

export const createUpgradeHandler = (server: httpProxy) => async (req: IncomingMessage, socket: any, head: any) => {
    try {
        if (!req?.url) {
            return socket.end();
        }
        let parsedUrl = url.parse(req.url);
        if (!parsedUrl?.query) {
            console.log(`Incoming Websocket upgrade request could not be parsed: ${req.url}`);
            return socket.end();
        }
        let queryParameters = querystring.parse(parsedUrl.query);
        const tokenString = queryParameters?.token;
        if (!tokenString || Array.isArray(tokenString)) {
            console.log(`Incoming Websocket upgrade request is missing an authentication token`);
            return socket.end();
        }

        const token = await verifyToken(tokenString);
        if (!token || !token.username) {
            console.log(`Incoming Websocket upgrade request has an invalid token`);
            return socket.end();
        }

        const remoteAddress = req.headers?.["x-forwarded-for"] || req.connection?.remoteAddress;
        console.log(`WS upgrade request from ${remoteAddress} for authenticated user ${token.username}`);

        const username = getUser(token.username, token.iss);
        if (!username) {
            console.log(`Could not find username ${token.username} in the user map`);
            return socket.end();
        }

        // Get or create pod for user
        let podInfo = await getUserPodInfo(username);
        
        if (!podInfo || !podInfo.ready) {
            console.log(`Creating new pod for user ${username}`);
            podInfo = await startServer(username);
            podMap.set(username, podInfo);
        }

        // Get service IP for the pod
        const service = await k8sApi.readNamespacedService(podInfo.serviceName, kubNamespace);
        const serviceIP = service.body.spec?.clusterIP;
        
        if (!serviceIP) {
            console.error(`Service IP not found for ${username}`);
            return socket.end();
        }

        console.log(`Redirecting to backend pod for ${username} (${serviceIP}:3002)`);
        req.headers["carta-auth-token"] = podInfo.authToken;
        req.url = "/";
        
        console.log(chalk.blue(`WebSocket upgrade details for ${username}:`));
        console.log(chalk.blue(`  Target: ${serviceIP}:3002`));
        console.log(chalk.blue(`  Auth token: ${podInfo.authToken.substring(0, 8)}...`));
        console.log(chalk.blue(`  Headers: ${JSON.stringify(req.headers)}`));
        
        return server.ws(req, socket, head, { target: { host: serviceIP, port: 3002 } });
        
    } catch (err) {
        console.log(`Error upgrading socket`);
        console.log(err);
        
        // Log more details about the error
        if (err instanceof Error) {
            console.error(chalk.red(`WebSocket upgrade error:`));
            console.error(chalk.red(`  Error: ${err.message}`));
            console.error(chalk.red(`  Stack: ${err.stack}`));
        }
        
        return socket.end();
    }
};

// Fixed createScriptingProxyHandler implementation
export const createScriptingProxyHandler = (server: httpProxy) => async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    const username = req?.username;
    if (!username) {
        return next({statusCode: 401, message: "Not authorized"});
    }

    if (!req.scripting) {
        return next({statusCode: 403, message: "API token supplied does not permit scripting"});
    }

    try {
        // Get or create pod for user
        let podInfo = await getUserPodInfo(username);
        
        if (!podInfo || !podInfo.ready) {
            console.log(`Creating new pod for user ${username}`);
            podInfo = await startServer(username);
            podMap.set(username, podInfo);
        }

        // Get service IP for the pod
        const service = await k8sApi.readNamespacedService(podInfo.serviceName, kubNamespace);
        const serviceIP = service.body.spec?.clusterIP;
        
        if (!serviceIP) {
            console.error(`Service IP not found for ${username}`);
            return next({statusCode: 500, message: `Service not found for ${username}`});
        }

        req.headers["carta-auth-token"] = podInfo.authToken;
        return server.web(req, res, { target: { host: serviceIP, port: 3002 } });
        
    } catch (err) {
        console.log(`Error proxying scripting request for ${req.username}`);
        console.log(err);
        return next({statusCode: 500, message: `Error proxying scripting request for ${req.username}`});
    }
};

export const serverRouter = express.Router();
serverRouter.post("/start", authGuard, noCache, handleStartServer);
serverRouter.post("/stop", authGuard, noCache, handleStopServer);
serverRouter.get("/status", authGuard, noCache, handleCheckServer);
serverRouter.get("/log", authGuard, noCache, handleLog);
