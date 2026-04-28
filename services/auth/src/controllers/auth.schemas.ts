import { z } from 'zod';

const phoneRegex = /^\+?[1-9]\d{7,14}$/;

export const registerSchema = z.object({
  email: z.string().email().optional(),
  phoneNumber: z.string().regex(phoneRegex).optional(),
  password: z.string().min(8),
  fullName: z.string().min(2).max(120).optional(),
}).refine((value) => value.email || value.phoneNumber, {
  message: 'email or phoneNumber is required',
  path: ['email'],
});

export const verifyOtpSchema = z.object({
  userId: z.string().uuid(),
  otpCode: z.string().length(6),
});

export const loginSchema = z.object({
  identifier: z.string().min(3),
  password: z.string().min(8),
});

export const refreshTokenSchema = z.object({
  refreshToken: z.string().min(32),
});

export const logoutSchema = z.object({
  refreshToken: z.string().min(32),
});

export const resetPasswordSchema = z.object({
  identifier: z.string().min(3),
  otpCode: z.string().length(6).optional(),
  newPassword: z.string().min(8).optional(),
}).superRefine((value, ctx) => {
  const isConfirm = value.otpCode || value.newPassword;
  if (isConfirm && (!value.otpCode || !value.newPassword)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'otpCode and newPassword are required together',
      path: ['otpCode'],
    });
  }
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type VerifyOtpInput = z.infer<typeof verifyOtpSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type RefreshTokenInput = z.infer<typeof refreshTokenSchema>;
export type LogoutInput = z.infer<typeof logoutSchema>;
export type ResetPasswordInput = z.infer<typeof resetPasswordSchema>;
