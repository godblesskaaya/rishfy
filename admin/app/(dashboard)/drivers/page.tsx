'use client';

import { useQuery } from '@tanstack/react-query';
import type { ColumnDef } from '@tanstack/react-table';

import { DataTable } from '@/components/data-table/data-table';
import { PageHeader } from '@/components/layout/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { driversApi } from '@/lib/api/endpoints';
import { formatDate, maskPhone } from '@/lib/utils';
import type { Driver } from '@/types/api';

const columns: ColumnDef<Driver>[] = [
  {
    accessorKey: 'first_name',
    header: 'Driver',
    cell: ({ row }) => (
      <div>
        <div className="font-medium">
          {row.original.first_name} {row.original.last_name}
        </div>
        <div className="text-xs text-muted-foreground">
          {maskPhone(row.original.phone_number)}
        </div>
      </div>
    ),
  },
  {
    accessorKey: 'license_number',
    header: 'License',
    cell: ({ row }) => (
      <div className="flex items-center gap-2">
        <span className="font-mono text-sm">{row.original.license_number}</span>
        {row.original.license_verified && (
          <Badge variant="success" className="text-xs">Verified</Badge>
        )}
      </div>
    ),
  },
  {
    accessorKey: 'license_expiry',
    header: 'Expiry',
    cell: ({ row }) => formatDate(row.original.license_expiry),
  },
  {
    accessorKey: 'total_trips',
    header: 'Trips',
  },
  {
    id: 'actions',
    cell: () => (
      <div className="flex gap-2">
        <Button size="sm" variant="success">Approve</Button>
        <Button size="sm" variant="destructive">Reject</Button>
      </div>
    ),
  },
];

export default function DriversPage() {
  const [page] = [1];
  const { data, isLoading } = useQuery({
    queryKey: ['drivers', 'pending', page],
    queryFn: () => driversApi.listPending({ page, page_size: 20 }),
  });

  return (
    <>
      <PageHeader
        title="Driver Verification"
        description="Review and approve new driver applications"
      />
      <DataTable
        columns={columns}
        data={data?.items ?? []}
        loading={isLoading}
        emptyMessage="No pending driver applications"
      />
    </>
  );
}
