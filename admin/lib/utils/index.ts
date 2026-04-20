import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/**
 * Combines multiple class names, handling Tailwind conflicts.
 * Used everywhere in shadcn/ui components.
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * Format an amount in TZS (Tanzanian Shillings) for display.
 * Integer minor units — 5000 displays as "5,000 TZS".
 */
export function formatTZS(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return `${amount.toLocaleString('en-TZ')} TZS`;
}

/**
 * Format a phone number for display with PII masking.
 * +255712345678 → +255 712 *** 678
 */
export function maskPhone(phone: string | null | undefined): string {
  if (!phone) return '—';
  const trimmed = phone.trim();
  if (trimmed.length < 10) return trimmed;
  return `${trimmed.slice(0, 7)} *** ${trimmed.slice(-3)}`;
}

/**
 * Format a date consistently across the admin.
 */
export function formatDate(date: string | Date | null | undefined): string {
  if (!date) return '—';
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleDateString('en-TZ', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function formatDateTime(date: string | Date | null | undefined): string {
  if (!date) return '—';
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleString('en-TZ', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/**
 * Format duration in seconds as human-readable string.
 * 3660 → "1h 1m"
 */
export function formatDuration(seconds: number | null | undefined): string {
  if (seconds == null) return '—';
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (hrs === 0) return `${mins}m`;
  return `${hrs}h ${mins}m`;
}

/**
 * Format distance in meters as human-readable string.
 * 12500 → "12.5 km", 850 → "850 m"
 */
export function formatDistance(meters: number | null | undefined): string {
  if (meters == null) return '—';
  if (meters < 1000) return `${meters} m`;
  return `${(meters / 1000).toFixed(1)} km`;
}

/**
 * Truncate a string with ellipsis.
 */
export function truncate(str: string, max: number): string {
  if (str.length <= max) return str;
  return `${str.slice(0, max).trimEnd()}…`;
}
