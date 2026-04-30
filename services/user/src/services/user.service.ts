import { randomUUID } from 'crypto';
import type { Pool } from 'pg';
import { UserRepository } from '../repositories/user.repository.js';
import { buildObjectUrl, generateUploadUrl } from '../clients/minio.client.js';
import { config } from '../config.js';
import { AppError } from '../utils/errors.js';

export class UserService {
  private readonly repo: UserRepository;

  constructor(pool: Pool) {
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

    const profile = await this.repo.createDriverProfile({ user_id: userId, ...data });
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
    return { user, driverProfile: profile };
  }

  async getRepository() {
    return this.repo;
  }
}
