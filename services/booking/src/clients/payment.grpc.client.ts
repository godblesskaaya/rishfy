import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/payment.proto');

let _instance: grpc.Client | null = null;

function getClient(): grpc.Client {
  if (!_instance) {
    const packageDef = protoLoader.loadSync(PROTO_PATH, {
      keepCase: false, longs: String, enums: String, defaults: true, oneofs: true,
      includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
    });
    const grpcObj = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
    const pkg = ((grpcObj['rishfy'] as Record<string, unknown>)['payment'] as Record<string, unknown>)['v1'] as Record<string, grpc.ServiceClientConstructor>;
    const PaymentService = pkg['PaymentService'];
    if (!PaymentService) throw new Error('PaymentService gRPC def not found');
    _instance = new PaymentService(config.PAYMENT_SERVICE_GRPC_URL, grpc.credentials.createInsecure());
  }
  return _instance;
}

type GrpcClientMethod<T> = (req: unknown, cb: (err: grpc.ServiceError | null, res: T) => void) => void;

function callUnary<T>(method: string, req: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    const client = getClient() as unknown as Record<string, GrpcClientMethod<T>>;
    const fn = client[method];
    if (!fn) return reject(new Error(`gRPC method ${method} not found`));
    fn(req, (err, res) => { if (err) reject(err); else resolve(res); });
  });
}

interface RefundPaymentGrpcResult {
  refundReference?: string;
  refundedNow?: { amountTzs?: string };
  payment?: { status?: string };
}

export interface RefundPaymentResult {
  refundReference: string;
  refundedAmountTzs: number;
  paymentStatus: string;
}

export async function refundPayment(paymentId: string, initiatedByUserId: string, reason: string): Promise<RefundPaymentResult | null> {
  try {
    const response = await callUnary<RefundPaymentGrpcResult>('refundPayment', {
      paymentId,
      reason,
      initiatedByUserId,
    });

    return {
      refundReference: response.refundReference ?? '',
      refundedAmountTzs: parseInt(response.refundedNow?.amountTzs ?? '0', 10),
      paymentStatus: response.payment?.status ?? '',
    };
  } catch (err) {
    logger.warn({ err, paymentId }, 'refundPayment gRPC failed');
    return null;
  }
}
