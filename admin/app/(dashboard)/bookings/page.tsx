'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { StatusBadge } from '@/components/status-badge';
import { bookingsApi } from '@/lib/api/endpoints';
import { formatDateTime, formatTZS } from '@/lib/utils';
import type { Booking } from '@/types/api';

const columns: ColumnDef<Booking>[] = [
  {
    accessorKey: 'confirmation_code',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono font-medium">{row.original.confirmation_code}</span>
    ),
  },
  {
    accessorKey: 'passenger_name',
    header: 'Passenger',
  },
  {
    accessorKey: 'driver_name',
    header: 'Driver',
  },
  {
    accessorKey: 'seat_count',
    header: 'Seats',
  },
  {
    accessorKey: 'total_amount',
    header: 'Amount',
    cell: ({ row }) => formatTZS(row.original.total_amount),
  },
  {
    accessorKey: 'status',
    header: 'Status',
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
  {
    accessorKey: 'created_at',
    header: 'Created',
    cell: ({ row }) => formatDateTime(row.original.created_at),
  },
];

export default function BookingsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ['bookings'],
    queryFn: () => bookingsApi.list({ page: 1, page_size: 50 }),
  });

  return (
    <>
      <PageHeader title="Bookings" description="All bookings across the platform" />
      <DataTable columns={columns} data={data?.items ?? []} loading={isLoading} />
    </>
  );
}
