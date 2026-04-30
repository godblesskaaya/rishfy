import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import type { UserRepository } from '../repositories/user.repository.js';
import { logger } from '../logger.js';

// Protos live at repo root shared/protos — resolved relative to service root (two levels up from src/grpc)
const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/user.proto');

function toTimestamp(d: Date | null | undefined): { seconds: number; nanos: number } | undefined {
  if (!d) return undefined;
  return { seconds: Math.floor(d.getTime() / 1000), nanos: 0 };
}

function userToProfile(u: NonNullable<Awaited<ReturnType<UserRepository['findById']>>>) {
  const names = u.full_name.split(' ');
  return {
    user_id: u.id,
    first_name: names[0] ?? '',
    last_name: names.slice(1).join(' '),
    profile_picture_url: u.profile_picture_url ?? '',
    role: u.role.toUpperCase(),
    rating_average: parseFloat(u.average_rating),
    rating_count: u.total_ratings,
    is_verified: u.status === 'active',
    language: 'sw',
    created_at: toTimestamp(u.created_at),
  };
}

export function createUserGrpcServer(repo: UserRepository): grpc.Server {
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
  const UserService = (pkg['v1'] as Record<string, { service: grpc.ServiceDefinition }>)['UserService'];
  if (!UserService) throw new Error('Failed to load UserService gRPC definition');

  const impl: grpc.UntypedServiceImplementation = {
    getUserProfile: async (call: grpc.ServerUnaryCall<{ user_id: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.findById(call.request.user_id);
        if (!user) return cb({ code: grpc.status.NOT_FOUND });
        cb(null, userToProfile(user));
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getUsersBatch: async (call: grpc.ServerUnaryCall<{ user_ids: string[] }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const results = await Promise.all(call.request.user_ids.map((id) => repo.findById(id)));
        cb(null, { users: results.filter(Boolean).map((u) => userToProfile(u!)) });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getDriverProfile: async (call: grpc.ServerUnaryCall<{ user_id: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.findById(call.request.user_id);
        if (!user || user.role !== 'driver') return cb({ code: grpc.status.NOT_FOUND });
        const profile = await repo.findDriverProfile(call.request.user_id);
        if (!profile) return cb({ code: grpc.status.NOT_FOUND });
        const vehicles = await repo.listDriverVehicles(profile.id);
        cb(null, {
          user: userToProfile(user),
          license_number: profile.license_number,
          license_verified: profile.is_verified,
          license_expiry: toTimestamp(profile.license_expiry),
          total_trips: 0,
          total_seats_offered: 0,
          accepting_routes: profile.is_verified,
          vehicles: vehicles.map((v) => ({
            vehicle_id: v.id,
            registration_number: v.plate_number,
            make: v.make,
            model: v.model,
            color: v.color,
            seat_capacity: v.capacity,
            latra_verified: v.status === 'approved',
          })),
        });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getVehicle: async (call: grpc.ServerUnaryCall<{ vehicle_id: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const v = await repo.findVehicle(call.request.vehicle_id);
        if (!v) return cb({ code: grpc.status.NOT_FOUND });
        cb(null, {
          vehicle_id: v.id,
          owner_user_id: '',
          registration_number: v.plate_number,
          make: v.make,
          model: v.model,
          year: v.year,
          color: v.color,
          seat_capacity: v.capacity,
          latra_verified: v.status === 'approved',
          created_at: toTimestamp(v.created_at),
        });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    listDriverVehicles: async (call: grpc.ServerUnaryCall<{ driver_user_id: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const profile = await repo.findDriverProfile(call.request.driver_user_id);
        if (!profile) return cb(null, { vehicles: [] });
        const rows = await repo.listDriverVehicles(profile.id);
        cb(null, {
          vehicles: rows.map((v) => ({
            vehicle_id: v.id,
            registration_number: v.plate_number,
            make: v.make, model: v.model, color: v.color,
            seat_capacity: v.capacity,
            latra_verified: v.status === 'approved',
          })),
        });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    checkDriverEligibility: async (call: grpc.ServerUnaryCall<{ user_id: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.findById(call.request.user_id);
        const profile = user ? await repo.findDriverProfile(user.id) : null;
        const blockers: string[] = [];
        if (!user || user.role !== 'driver') blockers.push('NOT_A_DRIVER');
        if (profile && !profile.is_verified) blockers.push('PROFILE_NOT_VERIFIED');
        if (profile && new Date(profile.license_expiry) < new Date()) blockers.push('LICENSE_EXPIRED');
        cb(null, { eligible: blockers.length === 0, blockers, checked_at: toTimestamp(new Date()) });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    updateUserRating: async (call: grpc.ServerUnaryCall<{ user_id: string; new_rating: number }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.updateRating(call.request.user_id, call.request.new_rating);
        if (!user) return cb({ code: grpc.status.NOT_FOUND });
        cb(null, { new_average: parseFloat(user.average_rating), new_count: user.total_ratings });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getNotificationPreferences: (_call: unknown, cb: grpc.sendUnaryData<unknown>) => {
      cb(null, { push_enabled: true, sms_enabled: true, email_enabled: false, booking_notifications: true, trip_notifications: true, promotional: false, preferred_language: 'sw', quiet_hours_start: '22:00', quiet_hours_end: '07:00' });
    },

    getEmergencyContacts: (_call: unknown, cb: grpc.sendUnaryData<unknown>) => {
      cb(null, { contacts: [] });
    },
  };

  const server = new grpc.Server();
  server.addService(UserService.service, impl);
  return server;
}
