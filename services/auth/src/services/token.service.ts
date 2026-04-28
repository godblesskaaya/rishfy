import { createPrivateKey, createPublicKey, generateKeyPairSync } from 'node:crypto';

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

const privateKey = createPrivateKey(config.JWT_PRIVATE_KEY ?? generatedKeyPair.privateKey);
const publicKey = createPublicKey(config.JWT_PUBLIC_KEY ?? generatedKeyPair.publicKey);

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
