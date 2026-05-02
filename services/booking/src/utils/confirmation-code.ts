import { randomBytes } from 'crypto';

// Unambiguous charset: no 0/O, 1/I/L, 2/Z, 5/S, 8/B
const CHARSET = 'ACDEFGHJKMNPQRTUVWXY34679';

export function generateConfirmationCode(): string {
  const bytes = randomBytes(8);
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += CHARSET[bytes[i]! % CHARSET.length];
  }
  return code;
}
