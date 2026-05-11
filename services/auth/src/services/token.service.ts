import { createPrivateKey, createPublicKey, generateKeyPairSync } from 'node:crypto';
import { readFileSync } from 'node:fs';

import jwt from 'jsonwebtoken';

import { config } from '../config.js';
import type { AuthTokens } from '../types/auth.js';

const ACCESS_TTL_SECONDS = 15 * 60;
const REFRESH_TTL_SECONDS = 7 * 24 * 60 * 60;

const generatedKeyPair = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

function resolveKeyMaterial(value?: string, path?: string): string | undefined {
  if (value) return value;
  if (path) {
    try { return readFileSync(path, 'utf-8').trim(); } catch { return undefined; }
  }
  return undefined;
}

const resolvedPrivateKey = resolveKeyMaterial(config.JWT_PRIVATE_KEY, config.JWT_PRIVATE_KEY_PATH);
const resolvedPublicKey = resolveKeyMaterial(config.JWT_PUBLIC_KEY, config.JWT_PUBLIC_KEY_PATH);

const privateKey = createPrivateKey(resolvedPrivateKey ?? generatedKeyPair.privateKey);
const publicKey = createPublicKey(resolvedPublicKey ?? generatedKeyPair.publicKey);

export interface AccessTokenClaims {
  sub: string;
  role: string;
  scope: 'access';
}

export interface RefreshTokenClaims {
  sub: string;
  sid: string;
  scope: 'refresh';
}

export function issueAuthTokens(input: {
  userId: string;
  role: string;
  sessionId: string;
}): AuthTokens {
  const accessToken = jwt.sign(
    { role: input.role, scope: 'access' },
    privateKey,
    {
      algorithm: 'RS256',
      subject: input.userId,
      expiresIn: ACCESS_TTL_SECONDS,
      issuer: config.SERVICE_NAME,
      audience: 'rishfy-api',
    },
  );

  const refreshToken = jwt.sign(
    { sid: input.sessionId, scope: 'refresh' },
    privateKey,
    {
      algorithm: 'RS256',
      subject: input.userId,
      expiresIn: REFRESH_TTL_SECONDS,
      issuer: config.SERVICE_NAME,
      audience: 'rishfy-auth',
    },
  );

  return {
    accessToken,
    refreshToken,
    expiresInSeconds: ACCESS_TTL_SECONDS,
    refreshExpiresInSeconds: REFRESH_TTL_SECONDS,
  };
}

export function verifyRefreshToken(token: string): RefreshTokenClaims {
  return jwt.verify(token, publicKey, {
    algorithms: ['RS256'],
    issuer: config.SERVICE_NAME,
    audience: 'rishfy-auth',
  }) as RefreshTokenClaims;
}

export function verifyAccessToken(token: string): AccessTokenClaims {
  return jwt.verify(token, publicKey, {
    algorithms: ['RS256'],
    issuer: config.SERVICE_NAME,
    audience: 'rishfy-api',
  }) as AccessTokenClaims;
}
