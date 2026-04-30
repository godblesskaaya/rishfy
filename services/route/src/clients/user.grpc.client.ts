import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/user.proto');

interface UserProfile {
  userId: string;
  firstName: string;
  lastName: string;
  profilePictureUrl: string;
  ratingAverage: number;
  ratingCount: number;
  isVerified: boolean;
}

interface DriverEligibility {
  eligible: boolean;
  blockers: string[];
}

let _instance: grpc.Client | null = null;

function getClient(): grpc.Client {
  if (!_instance) {
    const packageDef = protoLoader.loadSync(PROTO_PATH, {
      keepCase: false,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true,
      includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
    });
    const grpcObject = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
    const pkg = (grpcObject['rishfy'] as Record<string, unknown>)['user'] as Record<string, unknown>;
    const UserService = (pkg['v1'] as Record<string, grpc.ServiceClientConstructor>)['UserService'];
    if (!UserService) throw new Error('Failed to load UserService gRPC client definition');
    _instance = new UserService(config.USER_SERVICE_GRPC_URL, grpc.credentials.createInsecure());
  }
  return _instance;
}

type GrpcClientMethod<T> = (req: unknown, cb: (err: grpc.ServiceError | null, res: T) => void) => void;

function callUnary<T>(method: string, request: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    const client = getClient() as unknown as Record<string, GrpcClientMethod<T>>;
    const fn = client[method];
    if (!fn) return reject(new Error(`gRPC method ${method} not found`));
    fn(request, (err, res) => { if (err) reject(err); else resolve(res); });
  });
}

export async function getUserProfile(userId: string): Promise<UserProfile | null> {
  try {
    return await callUnary<UserProfile>('getUserProfile', { userId });
  } catch (err) {
    logger.warn({ err, userId }, 'gRPC getUserProfile failed');
    return null;
  }
}

export async function checkDriverEligibility(userId: string): Promise<DriverEligibility> {
  try {
    return await callUnary<DriverEligibility>('checkDriverEligibility', { userId });
  } catch (err) {
    logger.warn({ err, userId }, 'gRPC checkDriverEligibility failed');
    return { eligible: false, blockers: ['USER_SERVICE_UNAVAILABLE'] };
  }
}
