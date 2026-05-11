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
    userId: u.id,
    firstName: names[0] ?? '',
    lastName: names.slice(1).join(' '),
    profilePictureUrl: u.profile_picture_url ?? '',
    role: u.role.toUpperCase(),
    ratingAverage: parseFloat(u.average_rating),
    ratingCount: u.total_ratings,
    isVerified: u.status === 'active',
    language: 'sw',
    createdAt: toTimestamp(u.created_at),
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
    getUserProfile: async (call: grpc.ServerUnaryCall<{ userId: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.findById(call.request.userId);
        if (!user) return cb({ code: grpc.status.NOT_FOUND });
        cb(null, userToProfile(user));
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getUsersBatch: async (call: grpc.ServerUnaryCall<{ userIds: string[] }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const results = await Promise.all(call.request.userIds.map((id) => repo.findById(id)));
        cb(null, { users: results.filter(Boolean).map((u) => userToProfile(u!)) });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getDriverProfile: async (call: grpc.ServerUnaryCall<{ userId: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.findById(call.request.userId);
        if (!user || user.role !== 'driver') return cb({ code: grpc.status.NOT_FOUND });
        const profile = await repo.findDriverProfile(call.request.userId);
        if (!profile) return cb({ code: grpc.status.NOT_FOUND });
        const vehicles = await repo.listDriverVehicles(profile.id);
        cb(null, {
          user: userToProfile(user),
          licenseNumber: profile.license_number,
          licenseVerified: profile.is_verified,
          licenseExpiry: toTimestamp(profile.license_expiry),
          totalTrips: 0,
          totalSeatsOffered: 0,
          acceptingRoutes: profile.is_verified,
          vehicles: vehicles.map((v) => ({
            vehicleId: v.id,
            registrationNumber: v.plate_number,
            make: v.make,
            model: v.model,
            color: v.color,
            seatCapacity: v.capacity,
            latraVerified: v.status === 'approved',
          })),
        });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getVehicle: async (call: grpc.ServerUnaryCall<{ vehicleId: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const v = await repo.findVehicle(call.request.vehicleId);
        if (!v) return cb({ code: grpc.status.NOT_FOUND });
        cb(null, {
          vehicleId: v.id,
          ownerUserId: '',
          registrationNumber: v.plate_number,
          make: v.make,
          model: v.model,
          year: v.year,
          color: v.color,
          seatCapacity: v.capacity,
          latraVerified: v.status === 'approved',
          createdAt: toTimestamp(v.created_at),
        });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    listDriverVehicles: async (call: grpc.ServerUnaryCall<{ driverUserId: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const profile = await repo.findDriverProfile(call.request.driverUserId);
        if (!profile) return cb(null, { vehicles: [] });
        const rows = await repo.listDriverVehicles(profile.id);
        cb(null, {
          vehicles: rows.map((v) => ({
            vehicleId: v.id,
            registrationNumber: v.plate_number,
            make: v.make, model: v.model, color: v.color,
            seatCapacity: v.capacity,
            latraVerified: v.status === 'approved',
          })),
        });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    checkDriverEligibility: async (call: grpc.ServerUnaryCall<{ userId: string }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.findById(call.request.userId);
        const profile = user ? await repo.findDriverProfile(user.id) : null;
        const blockers: string[] = [];
        if (!user || user.role !== 'driver') blockers.push('NOT_A_DRIVER');
        if (profile && !profile.is_verified) blockers.push('PROFILE_NOT_VERIFIED');
        if (profile && new Date(profile.license_expiry) < new Date()) blockers.push('LICENSE_EXPIRED');
        cb(null, { eligible: blockers.length === 0, blockers, checkedAt: toTimestamp(new Date()) });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    updateUserRating: async (call: grpc.ServerUnaryCall<{ userId: string; newRating: number }, unknown>, cb: grpc.sendUnaryData<unknown>) => {
      try {
        const user = await repo.updateRating(call.request.userId, call.request.newRating);
        if (!user) return cb({ code: grpc.status.NOT_FOUND });
        cb(null, { newAverage: parseFloat(user.average_rating), newCount: user.total_ratings });
      } catch (err) { logger.error(err); cb({ code: grpc.status.INTERNAL }); }
    },

    getNotificationPreferences: (_call: unknown, cb: grpc.sendUnaryData<unknown>) => {
      cb(null, { pushEnabled: true, smsEnabled: true, emailEnabled: false, bookingNotifications: true, tripNotifications: true, promotional: false, preferredLanguage: 'sw', quietHoursStart: '22:00', quietHoursEnd: '07:00' });
    },

    getEmergencyContacts: (_call: unknown, cb: grpc.sendUnaryData<unknown>) => {
      cb(null, { contacts: [] });
    },
  };

  const server = new grpc.Server();
  server.addService(UserService.service, impl);
  return server;
}
