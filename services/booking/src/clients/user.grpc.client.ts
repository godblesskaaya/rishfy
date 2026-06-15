import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/user.proto');

export interface DriverComplianceProfile {
  licenseNumber: string;
  vehicles: Array<{
    vehicleId: string;
    registrationNumber: string;
    latraVerified: boolean;
  }>;
}

export interface VehicleComplianceRecord {
  vehicleId: string;
  registrationNumber: string;
  latraVerified: boolean;
}

let instance: grpc.Client | null = null;

function getClient(): grpc.Client {
  if (!instance) {
    const packageDef = protoLoader.loadSync(PROTO_PATH, {
      keepCase: false,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true,
      includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
    });
    const grpcObject = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
    const pkg = (grpcObject.rishfy as Record<string, unknown>).user as Record<string, unknown>;
    const UserService = (pkg.v1 as Record<string, grpc.ServiceClientConstructor>).UserService;
    if (!UserService) throw new Error('Failed to load UserService gRPC client definition');
    instance = new UserService(config.USER_SERVICE_GRPC_URL, grpc.credentials.createInsecure());
  }
  return instance;
}

type GrpcClientMethod<T> = (req: unknown, cb: (err: grpc.ServiceError | null, res: T) => void) => void;

function callUnary<T>(method: string, request: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    const client = getClient() as unknown as Record<string, GrpcClientMethod<T>>;
    const fn = client[method];
    if (!fn) return reject(new Error(`gRPC method ${method} not found`));
    fn.call(client, request, (err, res) => {
      if (err) reject(err);
      else resolve(res);
    });
  });
}

export async function getDriverComplianceProfile(userId: string): Promise<DriverComplianceProfile | null> {
  try {
    const profile = await callUnary<DriverComplianceProfile>('getDriverProfile', { userId });
    return profile;
  } catch (err) {
    logger.warn({ err, userId }, 'gRPC getDriverProfile failed for LATRA export');
    return null;
  }
}

export async function getVehicleComplianceRecord(vehicleId: string): Promise<VehicleComplianceRecord | null> {
  try {
    return await callUnary<VehicleComplianceRecord>('getVehicle', { vehicleId });
  } catch (err) {
    logger.warn({ err, vehicleId }, 'gRPC getVehicle failed for LATRA export');
    return null;
  }
}
