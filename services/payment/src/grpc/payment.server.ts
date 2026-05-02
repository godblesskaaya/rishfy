import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { PaymentService } from '../services/payment.service.js';
import { PaymentRepository } from '../repositories/payment.repository.js';
import { SettlementRepository } from '../repositories/settlement.repository.js';
import { pgPool } from '../db.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/payment.proto');

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
  includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
});

const grpcObject = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
const pkg = (grpcObject['rishfy'] as Record<string, unknown>)['payment'] as Record<string, unknown>;
const PaymentServiceDef = (pkg['v1'] as Record<string, unknown>)['PaymentService'] as { service: grpc.ServiceDefinition };

const paymentRepo = new PaymentRepository(pgPool);
const settlementRepo = new SettlementRepository(pgPool);
const svc = new PaymentService(paymentRepo);

type Handler<Req, Res> = grpc.handleUnaryCall<Req, Res>;

interface MoneyMsg { amountTzs: string }

interface InitiateReq {
  bookingId: string; userId: string; amount: MoneyMsg;
  method: string; payerPhone: string; idempotencyKey: string;
}
interface GetPaymentReq { paymentId: string }
interface ListPaymentsReq { userId: string; bookingId: string; pagination: { limit: number; cursor: string } }
interface ProcessCallbackReq { provider: string; rawPayload: string; signature: string }
interface RefundReq { paymentId: string; reason: string; initiatedByUserId: string }
interface CreateSettlementReq {
  driverUserId: string; periodStart: { seconds: string }; periodEnd: { seconds: string };
  payoutPhone: string;
}
interface GetEarningsReq { driverUserId: string; fromDate: { seconds: string }; toDate: { seconds: string } }

const initiatePayment: Handler<InitiateReq, unknown> = async (call, callback) => {
  try {
    const { bookingId, userId, amount, method, payerPhone, idempotencyKey } = call.request;
    const result = await svc.initiatePayment({
      bookingId, userId,
      amountTzs: parseInt(amount?.amountTzs ?? '0', 10),
      method, payerPhone, idempotencyKey,
    });
    callback(null, {
      payment: {
        paymentId: result.payment.id,
        bookingId: result.payment.booking_id,
        userId: result.payment.user_id,
        payerPhone: result.payment.payer_phone,
        status: result.payment.status.toUpperCase(),
        providerReference: result.payment.provider_reference ?? '',
        internalReference: result.payment.internal_reference,
      },
      instructions: result.instructions,
      expiresInSeconds: result.expiresInSeconds,
    });
  } catch (err) {
    logger.error({ err }, 'gRPC initiatePayment error');
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getPayment: Handler<GetPaymentReq, unknown> = async (call, callback) => {
  try {
    const payment = await svc.getPayment(call.request.paymentId);
    if (!payment) {
      callback({ code: grpc.status.NOT_FOUND, message: 'payment not found' } as grpc.ServiceError);
      return;
    }
    callback(null, {
      paymentId: payment.id,
      bookingId: payment.booking_id,
      userId: payment.user_id,
      status: payment.status.toUpperCase(),
      providerReference: payment.provider_reference ?? '',
      internalReference: payment.internal_reference,
    });
  } catch (err) {
    logger.error({ err }, 'gRPC getPayment error');
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const listPayments: Handler<ListPaymentsReq, unknown> = async (call, callback) => {
  try {
    const { bookingId } = call.request;
    const payment = bookingId ? await svc.getByBooking(bookingId) : null;
    callback(null, { payments: payment ? [{ paymentId: payment.id, status: payment.status }] : [], pagination: {} });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const processProviderCallback: Handler<ProcessCallbackReq, unknown> = async (call, callback) => {
  try {
    const { provider, rawPayload, signature } = call.request;
    const result = await svc.processCallback(provider, rawPayload, signature);
    callback(null, {
      processed: result.newStatus !== 'error',
      paymentId: result.paymentId,
      newStatus: result.newStatus.toUpperCase(),
      error: result.newStatus === 'error' ? 'processing error' : '',
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const refundPayment: Handler<RefundReq, unknown> = async (call, callback) => {
  try {
    const payment = await svc.getPayment(call.request.paymentId);
    if (!payment) {
      callback({ code: grpc.status.NOT_FOUND, message: 'payment not found' } as grpc.ServiceError);
      return;
    }
    callback(null, {
      payment: { paymentId: payment.id, status: 'REFUNDED' },
      refundReference: `REF-${payment.id}`,
      refundedNow: { amountTzs: String(payment.amount_tzs) },
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const createSettlement: Handler<CreateSettlementReq, unknown> = async (call, callback) => {
  try {
    const { driverUserId, periodStart, periodEnd, payoutPhone } = call.request;
    const fromDate = new Date(parseInt(periodStart?.seconds ?? '0', 10) * 1000);
    const toDate = new Date(parseInt(periodEnd?.seconds ?? '0', 10) * 1000);
    const earnings = await settlementRepo.getDriverEarnings(driverUserId, fromDate, toDate);
    const settlement = await settlementRepo.create({
      driverUserId,
      periodStart: fromDate,
      periodEnd: toDate,
      totalAmountTzs: earnings.total_earnings_tzs,
      platformFeeTzs: earnings.total_platform_fees_tzs,
      netAmountTzs: earnings.pending_balance_tzs,
      bookingCount: earnings.trip_count,
      payoutMethod: 'mobile_money',
      payoutPhone,
      bookingIds: [],
    });
    callback(null, {
      settlementId: settlement.id,
      totalAmount: { amountTzs: String(settlement.net_amount_tzs) },
      bookingCount: settlement.booking_count,
      status: 'PENDING',
    });
  } catch (err) {
    logger.error({ err }, 'gRPC createSettlement error');
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getDriverEarnings: Handler<GetEarningsReq, unknown> = async (call, callback) => {
  try {
    const { driverUserId, fromDate, toDate } = call.request;
    const from = new Date(parseInt(fromDate?.seconds ?? '0', 10) * 1000);
    const to = new Date(parseInt(toDate?.seconds ?? '0', 10) * 1000);
    const summary = await settlementRepo.getDriverEarnings(driverUserId, from, to);
    callback(null, {
      totalEarnings: { amountTzs: String(summary.total_earnings_tzs) },
      totalPlatformFees: { amountTzs: String(summary.total_platform_fees_tzs) },
      totalSettled: { amountTzs: String(summary.total_settled_tzs) },
      pendingBalance: { amountTzs: String(summary.pending_balance_tzs) },
      tripCount: summary.trip_count,
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

export function startGrpcServer(): grpc.Server {
  const server = new grpc.Server();
  server.addService(PaymentServiceDef.service, {
    initiatePayment,
    getPayment,
    listPayments,
    processProviderCallback,
    refundPayment,
    createSettlement,
    getDriverEarnings,
  });

  server.bindAsync(
    `0.0.0.0:${config.GRPC_PORT}`,
    grpc.ServerCredentials.createInsecure(),
    (err, port) => {
      if (err) { logger.error({ err }, 'gRPC bind failed'); process.exit(1); }
      logger.info({ port }, 'payment-service gRPC server listening');
    },
  );

  return server;
}
