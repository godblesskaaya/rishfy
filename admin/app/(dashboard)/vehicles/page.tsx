'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { Badge } from '@/components/ui/badge';
import { vehiclesApi } from '@/lib/api/endpoints';
import { formatDate } from '@/lib/utils';
import type { Vehicle } from '@/types/api';

const columns: ColumnDef<Vehicle>[] = [
  {
    accessorKey: 'registration_number',
    header: 'Registration',
    cell: ({ row }) => (
      <span className="font-mono font-medium">{row.original.registration_number}</span>
    ),
  },
  {
    accessorKey: 'make',
    header: 'Vehicle',
    cell: ({ row }) => (
      <div>
        <div>{row.original.make} {row.original.model}</div>
        <div className="text-xs text-muted-foreground">
          {row.original.year} · {row.original.color} · {row.original.seat_capacity} seats
        </div>
      </div>
    ),
  },
  {
    accessorKey: 'owner_name',
    header: 'Owner',
  },
  {
    accessorKey: 'latra_verified',
    header: 'LATRA Status',
    cell: ({ row }) =>
      row.original.latra_verified ? (
        <Badge variant="success">Verified</Badge>
      ) : (
        <Badge variant="warning">Pending</Badge>
      ),
  },
  {
    accessorKey: 'latra_expiry',
    header: 'License Expires',
    cell: ({ row }) => formatDate(row.original.latra_expiry),
  },
];

export default function VehiclesPage() {
  const { data, isLoading } = useQuery({
    queryKey: ['vehicles'],
    queryFn: () => vehiclesApi.list({ page: 1, page_size: 50 }),
  });

  return (
    <>
      <PageHeader
        title="Vehicles"
        description="All registered vehicles and LATRA verification status"
      />
      <DataTable
        columns={columns}
        data={data?.items ?? []}
        loading={isLoading}
      />
    </>
  );
}
