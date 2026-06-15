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

const blockUserSchema = z.object({
  reason: z.string().max(500).optional(),
});

const paymentMethodSchema = z.object({
  label: z.string().max(80).optional(),
  provider: z.string().min(2).max(40),
  phone: z.string().min(9).max(20),
  isDefault: z.boolean().optional(),
});

const updatePaymentMethodSchema = paymentMethodSchema.partial();

const emergencyContactSchema = z.object({
  name: z.string().min(1).max(120),
  phone: z.string().min(9).max(20),
  relationship: z.string().max(80).optional().nullable(),
});

const updateEmergencyContactSchema = emergencyContactSchema.partial();

const supportCaseSchema = z.object({
  subject: z.string().min(3).max(160),
  message: z.string().min(10).max(4000),
  category: z.string().min(2).max(60).optional(),
  priority: z.enum(['low', 'normal', 'high', 'urgent']).optional(),
  bookingId: z.string().uuid().optional().nullable(),
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

  // PUT /users/me/vehicles/:vehicleId/active
  app.put<{ Params: { vehicleId: string } }>('/me/vehicles/:vehicleId/active', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const vehicle = await svc.setActiveVehicle(userId, req.params.vehicleId);
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

  app.get('/me/payment-methods', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const methods = await svc.listPaymentMethods(userId);
      return reply.send({ methods: methods.map(toPaymentMethodDto) });
    } catch (err) { return handleError(err, reply); }
  });

  app.post('/me/payment-methods', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = paymentMethodSchema.parse(req.body);
      const method = await svc.addPaymentMethod(userId, body);
      return reply.code(201).send(toPaymentMethodDto(method));
    } catch (err) { return handleError(err, reply); }
  });

  app.patch<{ Params: { methodId: string } }>('/me/payment-methods/:methodId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = updatePaymentMethodSchema.parse(req.body);
      const method = await svc.updatePaymentMethod(userId, req.params.methodId, body);
      return reply.send(toPaymentMethodDto(method));
    } catch (err) { return handleError(err, reply); }
  });

  app.delete<{ Params: { methodId: string } }>('/me/payment-methods/:methodId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      await svc.deletePaymentMethod(userId, req.params.methodId);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });

  app.get('/me/emergency-contacts', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const contacts = await svc.listEmergencyContacts(userId);
      return reply.send({ contacts: contacts.map(toEmergencyContactDto) });
    } catch (err) { return handleError(err, reply); }
  });

  app.post('/me/emergency-contacts', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = emergencyContactSchema.parse(req.body);
      const contact = await svc.addEmergencyContact(userId, body);
      return reply.code(201).send(toEmergencyContactDto(contact));
    } catch (err) { return handleError(err, reply); }
  });

  app.patch<{ Params: { contactId: string } }>('/me/emergency-contacts/:contactId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = updateEmergencyContactSchema.parse(req.body);
      const contact = await svc.updateEmergencyContact(userId, req.params.contactId, body);
      return reply.send(toEmergencyContactDto(contact));
    } catch (err) { return handleError(err, reply); }
  });

  app.delete<{ Params: { contactId: string } }>('/me/emergency-contacts/:contactId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      await svc.deleteEmergencyContact(userId, req.params.contactId);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });

  app.get('/me/support-cases', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const cases = await svc.listSupportCases(userId);
      return reply.send({ cases: cases.map(toSupportCaseDto) });
    } catch (err) { return handleError(err, reply); }
  });

  app.post('/me/support-cases', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = supportCaseSchema.parse(req.body);
      const supportCase = await svc.createSupportCase(userId, body);
      return reply.code(201).send(toSupportCaseDto(supportCase));
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

  app.get('/me/blocks', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      return reply.send({ blocks: await svc.listBlockedUsers(userId) });
    } catch (err) { return handleError(err, reply); }
  });

  app.post<{ Params: { userId: string } }>('/me/blocks/:userId', async (req, reply) => {
    try {
      const currentUserId = req.headers['x-user-id'] as string;
      if (!currentUserId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = blockUserSchema.parse(req.body ?? {});
      const block = await svc.blockUser(currentUserId, req.params.userId, body.reason);
      return reply.code(201).send(block);
    } catch (err) { return handleError(err, reply); }
  });

  app.delete<{ Params: { userId: string } }>('/me/blocks/:userId', async (req, reply) => {
    try {
      const currentUserId = req.headers['x-user-id'] as string;
      if (!currentUserId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      await svc.unblockUser(currentUserId, req.params.userId);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });

  app.get('/me/favorite-drivers', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      return reply.send({ favorites: await svc.listFavoriteDrivers(userId) });
    } catch (err) { return handleError(err, reply); }
  });

  app.post<{ Params: { driverId: string } }>('/me/favorite-drivers/:driverId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const favorite = await svc.addFavoriteDriver(userId, req.params.driverId);
      return reply.code(201).send(favorite);
    } catch (err) { return handleError(err, reply); }
  });

  app.delete<{ Params: { driverId: string } }>('/me/favorite-drivers/:driverId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      await svc.removeFavoriteDriver(userId, req.params.driverId);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });

  // GET /users/drivers/:userId — public driver profile
  const publicDriverHandler = async (req: import('fastify').FastifyRequest<{ Params: { userId: string } }>, reply: import('fastify').FastifyReply) => {
    try {
      const result = await svc.getPublicDriver(req.params.userId);
      // Strip PII
      const { phone_number: _, email: __, ...publicUser } = result.user;
      return reply.send({
        user: publicUser,
        driverProfile: result.driverProfile,
        vehicles: result.vehicles,
        activeVehicle: result.activeVehicle,
        reviews: result.reviews,
      });
    } catch (err) { return handleError(err, reply); }
  };

  app.get<{ Params: { userId: string } }>('/drivers/:userId', publicDriverHandler);
  // Alias for strict Sprint 2 ticket path.
  app.get<{ Params: { userId: string } }>('/drivers/:userId/public', publicDriverHandler);
}

function toPaymentMethodDto(method: {
  id: string;
  label: string;
  provider: string;
  phone: string;
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
}) {
  return {
    id: method.id,
    label: method.label,
    provider: method.provider,
    phone: method.phone,
    isDefault: method.is_default,
    createdAt: method.created_at,
    updatedAt: method.updated_at,
  };
}

function toEmergencyContactDto(contact: {
  id: string;
  name: string;
  phone: string;
  relationship: string | null;
  created_at: Date;
  updated_at: Date;
}) {
  return {
    id: contact.id,
    name: contact.name,
    phone: contact.phone,
    relationship: contact.relationship,
    createdAt: contact.created_at,
    updatedAt: contact.updated_at,
  };
}

function toSupportCaseDto(supportCase: {
  id: string;
  user_id: string;
  booking_id: string | null;
  subject: string;
  message: string;
  category: string;
  status: string;
  priority: string;
  last_user_message_at: Date;
  last_support_response_at: Date | null;
  resolved_at: Date | null;
  closed_at: Date | null;
  created_at: Date;
  updated_at: Date;
}) {
  return {
    id: supportCase.id,
    userId: supportCase.user_id,
    bookingId: supportCase.booking_id,
    subject: supportCase.subject,
    message: supportCase.message,
    category: supportCase.category,
    status: supportCase.status,
    priority: supportCase.priority,
    lastUserMessageAt: supportCase.last_user_message_at,
    lastSupportResponseAt: supportCase.last_support_response_at,
    resolvedAt: supportCase.resolved_at,
    closedAt: supportCase.closed_at,
    createdAt: supportCase.created_at,
    updatedAt: supportCase.updated_at,
  };
}
