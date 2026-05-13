import nodemailer from 'nodemailer';

import type { Config } from '../config.js';
import { logger } from '../logger.js';

type OtpPayload = {
  destination: string;
  code: string;
  purpose: string;
};

const SUBJECT: Record<string, string> = {
  register: 'Your Rishfy verification code',
  'reset-password': 'Reset your Rishfy password',
};

const BODY = (code: string, purpose: string) => {
  const heading = purpose === 'reset-password' ? 'Password reset' : 'Verify your email';
  const action =
    purpose === 'reset-password'
      ? 'You requested a password reset for your Rishfy account.'
      : 'Thanks for signing up with Rishfy!';
  return `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"/></head>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;">
  <h2 style="margin-bottom:4px;">${heading}</h2>
  <p style="color:#555;">${action} Use the code below to continue:</p>
  <div style="font-size:36px;font-weight:bold;letter-spacing:8px;text-align:center;
              padding:24px;background:#f5f5f5;border-radius:8px;margin:24px 0;">
    ${code}
  </div>
  <p style="color:#888;font-size:13px;">This code expires in 10 minutes. If you didn't request this, ignore this email.</p>
</body>
</html>`;
};

export function createEmailSender(cfg: Pick<Config, 'SMTP_HOST' | 'SMTP_PORT' | 'SMTP_USER' | 'SMTP_PASS' | 'SMTP_FROM'>) {
  if (!cfg.SMTP_HOST || !cfg.SMTP_USER || !cfg.SMTP_PASS) {
    logger.warn('SMTP not configured — OTP emails will be logged only');
    return async (payload: OtpPayload) => {
      logger.info({ ...payload }, '[email-stub] OTP would be emailed');
    };
  }

  const transport = nodemailer.createTransport({
    host: cfg.SMTP_HOST,
    port: cfg.SMTP_PORT,
    secure: cfg.SMTP_PORT === 465,
    auth: { user: cfg.SMTP_USER, pass: cfg.SMTP_PASS },
  });

  return async (payload: OtpPayload): Promise<void> => {
    const subject = SUBJECT[payload.purpose] ?? 'Your Rishfy code';
    try {
      await transport.sendMail({
        from: `"Rishfy" <${cfg.SMTP_FROM ?? cfg.SMTP_USER}>`,
        to: payload.destination,
        subject,
        html: BODY(payload.code, payload.purpose),
        text: `Your ${payload.purpose === 'reset-password' ? 'password reset' : 'verification'} code: ${payload.code}. Expires in 10 minutes.`,
      });
      logger.info({ to: payload.destination, purpose: payload.purpose }, 'OTP email sent');
    } catch (err) {
      logger.error({ err, to: payload.destination }, 'Failed to send OTP email');
      throw err;
    }
  };
}
