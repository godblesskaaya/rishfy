'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { StatusBadge } from '@/components/status-badge';
import { routesApi } from '@/lib/api/endpoints';
import { formatDateTime, formatTZS, truncate } from '@/lib/utils';
import type { Route } from '@/types/api';

const columns: ColumnDef<Route>[] = [
  {
    accessorKey: 'origin',
    header: 'Route',
    cell: ({ row }) => (
      <div>
        <div className="font-medium">
          {truncate(row.original.origin.formatted_address, 30)}
        </div>
        <div className="text-xs text-muted-foreground">
          → {truncate(row.original.destination.formatted_address, 30)}
        </div>
      </div>
    ),
  },
  {
    accessorKey: 'driver_name',
    header: 'Driver',
  },
  {
    accessorKey: 'departure_time',
    header: 'Departure',
    cell: ({ row }) => formatDateTime(row.original.departure_time),
  },
  {
    accessorKey: 'available_seats',
    header: 'Seats',
    cell: ({ row }) => (
      <span>
        {row.original.available_seats} / {row.original.total_seats}
      </span>
    ),
  },
  {
    accessorKey: 'price_per_seat',
    header: 'Price',
    cell: ({ row }) => formatTZS(row.original.price_per_seat),
  },
  {
    accessorKey: 'status',
    header: 'Status',
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
];

export default function RoutesPage() {
  const { data, isLoading } = useQuery({
    queryKey: ['routes'],
    queryFn: () => routesApi.list({ page: 1, page_size: 50 }),
  });

  return (
    <>
      <PageHeader title="Routes" description="All routes posted on the platform" />
      <DataTable columns={columns} data={data?.items ?? []} loading={isLoading} />
    </>
  );
}
