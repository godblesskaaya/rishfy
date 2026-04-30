import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { UserService } from '../services/user.service.js';
import { isAppError } from '../utils/errors.js';

const updateProfileSchema = z.object({
  full_name: z.string().min(2).max(255).optional(),
  email: z.string().email().optional(),
});

const becomeDriverSchema = z.object({
  license_number: z.string().min(3).max(50),
  license_expiry: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD'),
  latra_permit_number: z.string().optional(),
});

const addVehicleSchema = z.object({
  make: z.string().min(1).max(100),
  model: z.string().min(1).max(100),
  year: z.number().int().min(1990).max(new Date().getFullYear() + 1),
  color: z.string().min(1).max(50),
  plate_number: z.string().min(3).max(20),
  capacity: z.number().int().min(1).max(20).default(4),
});

const deviceSchema = z.object({
  fcm_token: z.string().min(10),
  platform: z.enum(['ios', 'android']),
  device_id: z.string().min(1).max(255),
});

function handleError(err: unknown, reply: import('fastify').FastifyReply) {
  if (isAppError(err)) {
    return reply.code(err.statusCode).send({ error: err.code, message: err.message });
  }
  throw err;
}

export async function userRoutes(app: FastifyInstance, { svc }: { svc: UserService }) {
  // GET /users/me
  app.get('/me', async (req, reply) => {
    try {
      const userId = (req.headers['x-user-id'] as string);
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const user = await svc.getProfile(userId);
      return reply.send(user);
    } catch (err) { return handleError(err, reply); }
  });

  // PATCH /users/me
  app.patch('/me', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = updateProfileSchema.parse(req.body);
      const user = await svc.updateProfile(userId, body);
      return reply.send(user);
    } catch (err) { return handleError(err, reply); }
  });

  // POST /users/me/profile-picture — returns a presigned MinIO upload URL
  app.post<{ Body: { content_type: string } }>('/me/profile-picture', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const { content_type } = z.object({ content_type: z.string() }).parse(req.body);
      const result = await svc.getProfileUploadUrl(userId, content_type);
      return reply.code(200).send(result);
    } catch (err) { return handleError(err, reply); }
  });

  // PUT /users/me/profile-picture/confirm — after successful upload
  app.put<{ Body: { public_url: string } }>('/me/profile-picture/confirm', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const { public_url } = z.object({ public_url: z.string().url() }).parse(req.body);
      const user = await svc.confirmProfilePicture(userId, public_url);
      return reply.send(user);
    } catch (err) { return handleError(err, reply); }
  });

  // POST /users/me/become-driver
  app.post('/me/become-driver', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = becomeDriverSchema.parse(req.body);
      const result = await svc.becomeDriver(userId, body);
      return reply.code(201).send(result);
    } catch (err) { return handleError(err, reply); }
  });

  // GET /users/me/vehicles
  app.get('/me/vehicles', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      return reply.send(await svc.listVehicles(userId));
    } catch (err) { return handleError(err, reply); }
  });

  // POST /users/me/vehicles
  app.post('/me/vehicles', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = addVehicleSchema.parse(req.body);
      const vehicle = await svc.addVehicle(userId, body);
      return reply.code(201).send(vehicle);
    } catch (err) { return handleError(err, reply); }
  });

  // PATCH /users/me/vehicles/:vehicleId
  app.patch<{ Params: { vehicleId: string } }>('/me/vehicles/:vehicleId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const vehicle = await svc.updateVehicle(userId, req.params.vehicleId, req.body as Record<string, unknown>);
      return reply.send(vehicle);
    } catch (err) { return handleError(err, reply); }
  });

  // DELETE /users/me/vehicles/:vehicleId
  app.delete<{ Params: { vehicleId: string } }>('/me/vehicles/:vehicleId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      await svc.deleteVehicle(userId, req.params.vehicleId);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });

  // POST /users/me/devices
  app.post('/me/devices', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = deviceSchema.parse(req.body);
      const device = await svc.registerDevice(userId, body);
      return reply.code(201).send(device);
    } catch (err) { return handleError(err, reply); }
  });

  // GET /users/drivers/:userId — public driver profile
  app.get<{ Params: { userId: string } }>('/drivers/:userId', async (req, reply) => {
    try {
      const result = await svc.getPublicDriver(req.params.userId);
      // Strip PII
      const { phone_number: _, email: __, ...publicUser } = result.user;
      return reply.send({ user: publicUser, driverProfile: result.driverProfile });
    } catch (err) { return handleError(err, reply); }
  });
}
