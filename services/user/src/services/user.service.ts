import { randomUUID } from 'crypto';
import type { Pool } from 'pg';
import type { Producer } from 'kafkajs';
import { UserRepository } from '../repositories/user.repository.js';
import { buildObjectUrl, generateUploadUrl } from '../clients/minio.client.js';
import { config } from '../config.js';
import { publishDriverUpgraded } from '../events/user.events.js';
import { AppError } from '../utils/errors.js';

export class UserService {
  private readonly repo: UserRepository;

  constructor(
    pool: Pool,
    private readonly kafkaProducer: Producer | null = null,
  ) {
    this.repo = new UserRepository(pool);
  }

  async getProfile(userId: string) {
    const user = await this.repo.findById(userId);
    if (!user) throw new AppError('USER_NOT_FOUND', 404);
    return user;
  }

  async updateProfile(
    userId: string,
    data: { full_name?: string; email?: string },
  ) {
    const user = await this.repo.update(userId, data);
    if (!user) throw new AppError('USER_NOT_FOUND', 404);
    return user;
  }

  async getProfileUploadUrl(userId: string, contentType: string) {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (!allowed.includes(contentType)) {
      throw new AppError('INVALID_CONTENT_TYPE', 400, 'Allowed: jpeg, png, webp');
    }
    const ext = contentType.split('/')[1];
    const key = `profile-pictures/${userId}/${randomUUID()}.${ext}`;
    const uploadUrl = await generateUploadUrl(config.MINIO_BUCKET_USER_UPLOADS, key, contentType);
    const publicUrl = buildObjectUrl(config.MINIO_BUCKET_USER_UPLOADS, key);
    return { uploadUrl, publicUrl };
  }

  async confirmProfilePicture(userId: string, publicUrl: string) {
    const user = await this.repo.update(userId, { profile_picture_url: publicUrl });
    if (!user) throw new AppError('USER_NOT_FOUND', 404);
    return user;
  }

  async becomeDriver(
    userId: string,
    data: { license_number: string; license_expiry: string; latra_permit_number?: string },
  ) {
    const existing = await this.repo.findDriverProfile(userId);
    if (existing) throw new AppError('ALREADY_DRIVER', 409, 'User already has a driver profile');

    const upgraded = await this.repo.upgradeToDriver(userId);
    if (!upgraded) throw new AppError('USER_NOT_FOUND', 404);

    const profile = await this.repo.createDriverProfile({ user_id: upgraded.id, ...data });

    // Account-created synchronization is handled by consuming auth-service `user.registered` events.
    // User-service only owns this role-transition event.
    if (this.kafkaProducer) {
      await publishDriverUpgraded(this.kafkaProducer, {
        user_id: userId,
        license_number: data.license_number,
        upgraded_at: new Date().toISOString(),
      });
    }

    return { user: upgraded, driverProfile: profile };
  }

  async addVehicle(
    userId: string,
    data: { make: string; model: string; year: number; color: string; plate_number: string; capacity: number },
  ) {
    const profile = await this.repo.findDriverProfile(userId);
    if (!profile) throw new AppError('NOT_A_DRIVER', 403, 'User must be a driver to add vehicles');
    return this.repo.createVehicle({ driver_profile_id: profile.id, ...data });
  }

  async listVehicles(userId: string) {
    const profile = await this.repo.findDriverProfile(userId);
    if (!profile) return [];
    return this.repo.listDriverVehicles(profile.id);
  }

  async updateVehicle(userId: string, vehicleId: string, data: Record<string, unknown>) {
    const vehicle = await this.repo.findVehicle(vehicleId);
    if (!vehicle) throw new AppError('VEHICLE_NOT_FOUND', 404);

    const profile = await this.repo.findDriverProfile(userId);
    if (!profile || vehicle.driver_profile_id !== profile.id) {
      throw new AppError('FORBIDDEN', 403);
    }

    return this.repo.updateVehicle(vehicleId, data as Parameters<UserRepository['updateVehicle']>[1]);
  }

  async setActiveVehicle(userId: string, vehicleId: string) {
    const vehicle = await this.repo.findVehicle(vehicleId);
    if (!vehicle) throw new AppError('VEHICLE_NOT_FOUND', 404);

    const profile = await this.repo.findDriverProfile(userId);
    if (!profile || vehicle.driver_profile_id !== profile.id) {
      throw new AppError('FORBIDDEN', 403);
    }

    const activated = await this.repo.setActiveVehicle(profile.id, vehicleId);
    if (!activated) throw new AppError('VEHICLE_NOT_FOUND', 404);

    return activated;
  }

  async deleteVehicle(userId: string, vehicleId: string) {
    const vehicle = await this.repo.findVehicle(vehicleId);
    if (!vehicle) throw new AppError('VEHICLE_NOT_FOUND', 404);

    const profile = await this.repo.findDriverProfile(userId);
    if (!profile || vehicle.driver_profile_id !== profile.id) {
      throw new AppError('FORBIDDEN', 403);
    }

    return this.repo.deleteVehicle(vehicleId);
  }

  async registerDevice(
    userId: string,
    data: { fcm_token: string; platform: string; device_id: string },
  ) {
    return this.repo.upsertDevice({ user_id: userId, ...data });
  }

  async getPublicDriver(userId: string) {
    const user = await this.repo.findById(userId);
    if (!user || user.role !== 'driver') throw new AppError('DRIVER_NOT_FOUND', 404);
    const profile = await this.repo.findDriverProfile(userId);
    const vehicles = profile ? await this.repo.listDriverVehicles(profile.id) : [];
    const reviews = await this.repo.listApprovedRatingsForUser(userId, 5);
    return {
      user,
      driverProfile: profile,
      vehicles,
      activeVehicle: vehicles.find((vehicle) => vehicle.is_active) ?? vehicles[0] ?? null,
      reviews,
    };
  }

  async listPendingDrivers(limit = 50, offset = 0) {
    return this.repo.listPendingDrivers(limit, offset);
  }

  async approveDriverProfile(userId: string) {
    const profile = await this.repo.verifyDriverProfile(userId);
    if (!profile) throw new AppError('DRIVER_NOT_FOUND', 404);
    return profile;
  }

  async rejectDriverProfile(userId: string) {
    const profile = await this.repo.rejectDriverProfile(userId);
    if (!profile) throw new AppError('DRIVER_NOT_FOUND', 404);
    return profile;
  }

  async listRatingsForModeration(status: 'pending' | 'approved' | 'hidden' | undefined, limit = 50, offset = 0) {
    return this.repo.listRatingsForModeration({
      status,
      limit: Math.min(Math.max(limit, 1), 100),
      offset: Math.max(offset, 0),
    });
  }

  async moderateRating(
    ratingId: string,
    data: { status: 'approved' | 'hidden'; moderatedBy: string; hiddenReason?: string | null },
  ) {
    if (data.status === 'hidden' && !data.hiddenReason?.trim()) {
      throw new AppError('HIDDEN_REASON_REQUIRED', 400);
    }
    const rating = await this.repo.moderateRating({
      ratingId,
      status: data.status,
      moderatedBy: data.moderatedBy,
      hiddenReason: data.hiddenReason,
    });
    if (!rating) throw new AppError('RATING_NOT_FOUND', 404);
    return rating;
  }

  async blockUser(blockerId: string, blockedId: string, reason?: string | null) {
    if (blockerId === blockedId) throw new AppError('CANNOT_BLOCK_SELF', 400);
    const blocked = await this.repo.findById(blockedId);
    if (!blocked) throw new AppError('USER_NOT_FOUND', 404);
    return this.repo.blockUser({ blockerId, blockedId, reason });
  }

  async unblockUser(blockerId: string, blockedId: string) {
    await this.repo.unblockUser(blockerId, blockedId);
  }

  async listBlockedUsers(blockerId: string) {
    return this.repo.listBlockedUsers(blockerId);
  }

  async addFavoriteDriver(passengerUserId: string, driverUserId: string) {
    if (passengerUserId === driverUserId) throw new AppError('CANNOT_FAVORITE_SELF', 400);
    const driver = await this.repo.findById(driverUserId);
    if (!driver || driver.role !== 'driver') throw new AppError('DRIVER_NOT_FOUND', 404);
    return this.repo.addFavoriteDriver(passengerUserId, driverUserId);
  }

  async removeFavoriteDriver(passengerUserId: string, driverUserId: string) {
    await this.repo.removeFavoriteDriver(passengerUserId, driverUserId);
  }

  async listFavoriteDrivers(passengerUserId: string) {
    return this.repo.listFavoriteDrivers(passengerUserId);
  }

  async listPaymentMethods(userId: string) {
    return this.repo.listPaymentMethods(userId);
  }

  async addPaymentMethod(
    userId: string,
    data: { label?: string; provider: string; phone: string; isDefault?: boolean },
  ) {
    this.validatePaymentMethod(data);
    return this.repo.addPaymentMethod({
      userId,
      label: data.label?.trim() ?? '',
      provider: data.provider.trim(),
      phone: data.phone.trim(),
      isDefault: data.isDefault,
    });
  }

  async updatePaymentMethod(
    userId: string,
    methodId: string,
    data: { label?: string; provider?: string; phone?: string; isDefault?: boolean },
  ) {
    this.validatePaymentMethod(data, true);
    const method = await this.repo.updatePaymentMethod(userId, methodId, {
      label: data.label?.trim(),
      provider: data.provider?.trim(),
      phone: data.phone?.trim(),
      isDefault: data.isDefault,
    });
    if (!method) throw new AppError('PAYMENT_METHOD_NOT_FOUND', 404);
    return method;
  }

  async deletePaymentMethod(userId: string, methodId: string) {
    const deleted = await this.repo.deletePaymentMethod(userId, methodId);
    if (!deleted) throw new AppError('PAYMENT_METHOD_NOT_FOUND', 404);
  }

  async listEmergencyContacts(userId: string) {
    return this.repo.listEmergencyContacts(userId);
  }

  async addEmergencyContact(
    userId: string,
    data: { name: string; phone: string; relationship?: string | null },
  ) {
    this.validateEmergencyContact(data);
    return this.repo.addEmergencyContact({
      userId,
      name: data.name.trim(),
      phone: data.phone.trim(),
      relationship: data.relationship?.trim() || null,
    });
  }

  async updateEmergencyContact(
    userId: string,
    contactId: string,
    data: { name?: string; phone?: string; relationship?: string | null },
  ) {
    this.validateEmergencyContact(data, true);
    const contact = await this.repo.updateEmergencyContact(userId, contactId, {
      name: data.name?.trim(),
      phone: data.phone?.trim(),
      relationship: data.relationship?.trim() || null,
    });
    if (!contact) throw new AppError('EMERGENCY_CONTACT_NOT_FOUND', 404);
    return contact;
  }

  async deleteEmergencyContact(userId: string, contactId: string) {
    const deleted = await this.repo.deleteEmergencyContact(userId, contactId);
    if (!deleted) throw new AppError('EMERGENCY_CONTACT_NOT_FOUND', 404);
  }

  async listSupportCases(userId: string) {
    return this.repo.listSupportCases(userId);
  }

  async createSupportCase(
    userId: string,
    data: {
      subject: string;
      message: string;
      category?: string;
      priority?: 'low' | 'normal' | 'high' | 'urgent';
      bookingId?: string | null;
    },
  ) {
    const subject = data.subject.trim();
    const message = data.message.trim();
    const category = this.normalizeSupportCategory(data.category);
    if (subject.length < 3) {
      throw new AppError('INVALID_SUPPORT_CASE', 400, 'Subject must be at least 3 characters');
    }
    if (message.length < 10) {
      throw new AppError('INVALID_SUPPORT_CASE', 400, 'Message must be at least 10 characters');
    }
    return this.repo.createSupportCase({
      userId,
      subject,
      message,
      category,
      priority: data.priority ?? this.defaultSupportPriority(category),
      bookingId: data.bookingId ?? null,
    });
  }

  async listSupportCasesForStaff(params: {
    status?: 'open' | 'waiting' | 'resolved' | 'closed';
    priority?: 'low' | 'normal' | 'high' | 'urgent';
    limit?: number;
    offset?: number;
  }) {
    return this.repo.listSupportCasesForStaff({
      status: params.status,
      priority: params.priority,
      limit: Math.min(Math.max(params.limit ?? 50, 1), 100),
      offset: Math.max(params.offset ?? 0, 0),
    });
  }

  async updateSupportCaseForStaff(
    caseId: string,
    data: {
      status?: 'open' | 'waiting' | 'resolved' | 'closed';
      priority?: 'low' | 'normal' | 'high' | 'urgent';
      supportResponded?: boolean;
    },
  ) {
    const supportCase = await this.repo.updateSupportCaseForStaff({
      caseId,
      status: data.status,
      priority: data.priority,
      supportResponded: data.supportResponded,
    });
    if (!supportCase) throw new AppError('SUPPORT_CASE_NOT_FOUND', 404);
    return supportCase;
  }

  private validatePaymentMethod(
    data: { provider?: string; phone?: string },
    partial = false,
  ) {
    if (!partial || data.provider !== undefined) {
      if (!data.provider?.trim()) throw new AppError('INVALID_PAYMENT_METHOD', 400, 'Provider is required');
    }
    if (!partial || data.phone !== undefined) {
      const phone = data.phone?.trim() ?? '';
      if (!/^\+?[0-9]{9,15}$/.test(phone)) {
        throw new AppError('INVALID_PAYMENT_METHOD', 400, 'Phone number must be 9-15 digits');
      }
    }
  }

  private validateEmergencyContact(
    data: { name?: string; phone?: string },
    partial = false,
  ) {
    if (!partial || data.name !== undefined) {
      if (!data.name?.trim()) throw new AppError('INVALID_EMERGENCY_CONTACT', 400, 'Name is required');
    }
    if (!partial || data.phone !== undefined) {
      const phone = data.phone?.trim() ?? '';
      if (!/^\+?[0-9]{9,15}$/.test(phone)) {
        throw new AppError('INVALID_EMERGENCY_CONTACT', 400, 'Phone number must be 9-15 digits');
      }
    }
  }

  private normalizeSupportCategory(category?: string): string {
    const normalized = (category ?? 'general')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_ -]/g, '')
      .replace(/\s+/g, '_');
    if (!normalized) return 'general';
    return normalized.slice(0, 60);
  }

  private defaultSupportPriority(category: string): 'normal' | 'high' | 'urgent' {
    if (category.includes('safety') || category.includes('emergency')) return 'urgent';
    if (category.includes('payment') || category.includes('refund')) return 'high';
    return 'normal';
  }

  async getRepository() {
    return this.repo;
  }
}
