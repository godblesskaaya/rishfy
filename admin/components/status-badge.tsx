import { Badge } from '@/components/ui/badge';
import type {
  BookingStatus,
  PaymentStatus,
  RouteStatus,
  TripStatus,
} from '@/types/api';

const statusConfig: Record<
  string,
  { variant: 'default' | 'secondary' | 'destructive' | 'success' | 'warning' | 'outline'; label: string }
> = {
  // Bookings
  pending: { variant: 'warning', label: 'Pending' },
  confirmed: { variant: 'default', label: 'Confirmed' },
  cancelled: { variant: 'destructive', label: 'Cancelled' },
  completed: { variant: 'success', label: 'Completed' },
  no_show: { variant: 'destructive', label: 'No show' },

  // Trips
  scheduled: { variant: 'secondary', label: 'Scheduled' },
  started: { variant: 'default', label: 'Started' },
  in_progress: { variant: 'default', label: 'In progress' },

  // Payments
  initiated: { variant: 'warning', label: 'Initiated' },
  processing: { variant: 'warning', label: 'Processing' },
  failed: { variant: 'destructive', label: 'Failed' },
  refunded: { variant: 'secondary', label: 'Refunded' },

  // Routes
  draft: { variant: 'secondary', label: 'Draft' },
  posted: { variant: 'default', label: 'Posted' },
  full: { variant: 'warning', label: 'Full' },
};

interface StatusBadgeProps {
  status: BookingStatus | TripStatus | PaymentStatus | RouteStatus | string;
}

export function StatusBadge({ status }: StatusBadgeProps) {
  const config = statusConfig[status] ?? {
    variant: 'outline' as const,
    label: status,
  };
  return <Badge variant={config.variant}>{config.label}</Badge>;
}
